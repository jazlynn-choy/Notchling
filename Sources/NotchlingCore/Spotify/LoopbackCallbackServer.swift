import Foundation
import Network

/// A one-shot HTTP listener on 127.0.0.1 that catches the browser's redirect after sign-in.
///
/// Bound to the loopback address only, so nothing else on the network can reach it, and it
/// shuts down as soon as it has the callback, an error, or the timeout.
public struct LoopbackCallbackServer: AuthCallbackReceiving {
    public init() {}

    public func waitForCallback(port: UInt16, path: String, timeout: Duration) async throws -> URL {
        let session = Session(port: port, path: path)
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: URL.self) { group in
                group.addTask { try await session.run() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw SpotifyError.signInFailed("Sign-in timed out. Try again.")
                }
                defer {
                    group.cancelAll()
                    session.stop()
                }
                return try await group.next()!
            }
        } onCancel: {
            session.stop()
        }
    }

    /// Owns the listener. All state is touched only on `queue`.
    private final class Session: @unchecked Sendable {
        let port: UInt16
        let path: String
        let queue = DispatchQueue(label: "notchling.auth-callback")
        var listener: NWListener?
        var continuation: CheckedContinuation<URL, Error>?

        init(port: UInt16, path: String) {
            self.port = port
            self.path = path
        }

        func run() async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { self.start(continuation) }
            }
        }

        func stop() {
            queue.async { self.finish(.failure(CancellationError())) }
        }

        private func start(_ continuation: CheckedContinuation<URL, Error>) {
            self.continuation = continuation
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                             port: NWEndpoint.Port(rawValue: port)!)
                parameters.allowLocalEndpointReuse = true
                let listener = try NWListener(using: parameters)
                listener.stateUpdateHandler = { [weak self] state in
                    if case .failed(let error) = state {
                        self?.finish(.failure(SpotifyError.signInFailed("Couldn't listen for the sign-in (\(error)).")))
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
                listener.start(queue: queue)
                self.listener = listener
            } catch {
                finish(.failure(error))
            }
        }

        private func handle(_ connection: NWConnection) {
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
                guard let self else { return }
                let target = data.flatMap { LoopbackCallbackServer.requestTarget(fromRequest: $0) }
                let matches = target.map { $0.hasPrefix(self.path + "?") || $0 == self.path } ?? false
                Self.respond(on: connection, ok: matches)
                // Ignore other requests (like /favicon.ico) and keep waiting for the real one.
                if matches, let target, let url = URL(string: "http://127.0.0.1:\(self.port)\(target)") {
                    self.finish(.success(url))
                }
            }
        }

        private static func respond(on connection: NWConnection, ok: Bool) {
            let body = ok
                ? "<html><body style=\"font:16px -apple-system;text-align:center;margin-top:80px\">"
                    + "<h2>Notchling is connected to Spotify</h2><p>You can close this tab.</p></body></html>"
                : "Not found"
            let head = "HTTP/1.1 \(ok ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\n"
                + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
        }

        private func finish(_ result: Result<URL, Error>) {
            listener?.cancel()
            listener = nil
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    /// `"GET /callback?code=x HTTP/1.1\r\n…"` → `"/callback?code=x"`. Public for tests.
    public static func requestTarget(fromRequest data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              let line = text.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/") else { return nil }
        return String(parts[1])
    }
}

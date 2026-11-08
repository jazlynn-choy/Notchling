import Foundation

/// The user's Spotify sign-in: starts it, keeps the token fresh, and remembers it.
///
/// Only the long-lived refresh token is stored, and in the Keychain, not UserDefaults.
/// The short-lived access token lives in memory and is refreshed when it's about to expire.
@MainActor
public final class SpotifyConnection: ObservableObject {
    public enum Status: Equatable, Sendable {
        case needsClientID, disconnected, connecting, connected
        case failed(String)
    }

    static let clientIDKey = "spotifyClientID"
    static let refreshTokenKey = "spotify.refreshToken"

    @Published public var clientID: String {
        didSet {
            let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != clientID { clientID = trimmed; return }
            defaults.set(clientID, forKey: Self.clientIDKey)
            // A token belongs to one Client ID, so changing it signs out.
            if clientID != oldValue { disconnect() }
        }
    }
    @Published public private(set) var status: Status

    private let http: HTTPClient
    private let secrets: SecretStore
    private let callbacks: AuthCallbackReceiving
    private let openURL: @MainActor (URL) -> Void
    private let defaults: UserDefaults
    private let clock: () -> Date
    private var tokens: SpotifyTokens?
    /// Shared so two searches at once trigger one refresh, not two.
    private var refreshTask: Task<SpotifyTokens, Error>?

    public init(http: HTTPClient, secrets: SecretStore, callbacks: AuthCallbackReceiving,
                defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init,
                openURL: @escaping @MainActor (URL) -> Void) {
        self.http = http
        self.secrets = secrets
        self.callbacks = callbacks
        self.defaults = defaults
        self.clock = clock
        self.openURL = openURL
        let id = defaults.string(forKey: Self.clientIDKey) ?? ""
        clientID = id
        if id.isEmpty {
            status = .needsClientID
        } else if let refresh = secrets.read(Self.refreshTokenKey) {
            // Access token fetched lazily on first use.
            tokens = SpotifyTokens(accessToken: "", refreshToken: refresh, expiresAt: .distantPast)
            status = .connected
        } else {
            status = .disconnected
        }
    }

    public var isConnected: Bool { status == .connected }

    /// Opens Spotify's sign-in page in the browser and waits for it to redirect back.
    public func connect() async {
        guard !clientID.isEmpty else { status = .needsClientID; return }
        status = .connecting
        let verifier = SpotifyAuth.makeVerifier()
        let state = UUID().uuidString
        let callbacks = callbacks
        // Start listening before opening the browser, so the redirect can't arrive first.
        let callback = Task {
            try await callbacks.waitForCallback(port: SpotifyAuth.port, path: SpotifyAuth.callbackPath,
                                                timeout: .seconds(180))
        }
        openURL(SpotifyAuth.authorizeURL(clientID: clientID, challenge: SpotifyAuth.challenge(for: verifier),
                                         state: state))
        do {
            let code = try SpotifyAuth.code(from: try await callback.value, expectedState: state)
            let request = SpotifyAuth.tokenRequest([
                "grant_type": "authorization_code", "code": code, "redirect_uri": SpotifyAuth.redirectURI,
                "client_id": clientID, "code_verifier": verifier,
            ])
            let (data, response) = try await http.send(request)
            guard response.statusCode == 200 else { throw SpotifyError.signInFailed(Self.message(from: data)) }
            let fresh = try SpotifyAuth.tokens(from: data, now: clock())
            tokens = fresh
            secrets.write(fresh.refreshToken, for: Self.refreshTokenKey)
            status = .connected
        } catch {
            callback.cancel()
            status = .failed(error.localizedDescription)
        }
    }

    public func disconnect() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        secrets.delete(Self.refreshTokenKey)
        status = clientID.isEmpty ? .needsClientID : .disconnected
    }

    /// Message shown when Spotify itself ends the sign-in (revoked, or the app was removed).
    public static let signedOutMessage = "Spotify signed Notchling out. Click Connect to sign in again."

    /// Checks the saved sign-in still works, and renews it early so it never lapses. Run at
    /// launch, after the Mac wakes, and on a timer. Being offline is not a reason to sign out:
    /// only Spotify rejecting the refresh token is.
    public func keepAlive() async {
        guard tokens != nil else { return }
        _ = try? await accessToken(minimumValidity: 20 * 60)
    }

    /// A valid access token, refreshed first if it expires within `minimumValidity` seconds.
    public func accessToken(minimumValidity: TimeInterval = 60) async throws -> String {
        guard let current = tokens else { throw SpotifyError.notConnected }
        if current.expiresAt > clock().addingTimeInterval(minimumValidity) { return current.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }

        let request = SpotifyAuth.tokenRequest(["grant_type": "refresh_token",
                                                "refresh_token": current.refreshToken,
                                                "client_id": clientID])
        let http = http, clock = clock
        let task = Task { () throws -> SpotifyTokens in
            let (data, response) = try await http.send(request)
            if response.statusCode == 400 || response.statusCode == 401 { throw SpotifyError.notConnected }
            guard response.statusCode == 200 else { throw SpotifyError.server(response.statusCode) }
            return try SpotifyAuth.tokens(from: data, now: clock(), previousRefreshToken: current.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            tokens = fresh
            // Spotify may rotate the refresh token; always keep the newest one.
            secrets.write(fresh.refreshToken, for: Self.refreshTokenKey)
            if status != .connected { status = .connected }
            return fresh.accessToken
        } catch SpotifyError.notConnected {
            // The refresh token was revoked (e.g. removed in Spotify's account page).
            disconnect()
            status = .failed(Self.signedOutMessage)
            throw SpotifyError.notConnected
        }
    }

    /// Forces a refresh on next use, after Spotify rejects a token early.
    public func invalidateAccessToken() {
        tokens?.expiresAt = .distantPast
    }

    private static func message(from data: Data) -> String {
        struct Body: Decodable { let errorDescription: String? }
        return (try? SpotifyAuth.snakeCaseDecoder.decode(Body.self, from: data))?.errorDescription
            ?? "Spotify sign-in failed."
    }
}

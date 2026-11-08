import Foundation

/// Searches Spotify's whole catalog with the Web API. Playback still goes through the
/// Spotify app (AppleScript `play track`), which works on free and Premium accounts.
public struct SpotifyCatalog: SongCatalog {
    let http: HTTPClient
    let token: @Sendable () async throws -> String
    let invalidateToken: @Sendable () async -> Void

    public init(http: HTTPClient,
                token: @escaping @Sendable () async throws -> String,
                invalidateToken: @escaping @Sendable () async -> Void) {
        self.http = http
        self.token = token
        self.invalidateToken = invalidateToken
    }

    public func search(_ query: String, limit: Int) async throws -> [SongResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let (data, response) = try await authorizedGet(Self.searchURL(query: query, limit: limit))
        switch response.statusCode {
        case 200: return try Self.parseSearch(data)
        case 429: throw SpotifyError.rateLimited
        default: throw SpotifyError.server(response.statusCode)
        }
    }

    /// One retry with a fresh token if Spotify says the current one expired early.
    private func authorizedGet(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var result = try await http.send(request(url, token: try await token()))
        if result.1.statusCode == 401 {
            await invalidateToken()
            result = try await http.send(request(url, token: try await token()))
        }
        return result
    }

    private func request(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func searchURL(query: String, limit: Int) -> URL {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [.init(name: "q", value: query), .init(name: "type", value: "track"),
                                 .init(name: "limit", value: String(min(max(limit, 1), 50)))]
        return components.url!
    }

    public static func parseSearch(_ data: Data) throws -> [SongResult] {
        struct Response: Decodable {
            struct Tracks: Decodable { let items: [Item] }
            struct Item: Decodable {
                let uri: String
                let name: String
                let artists: [Artist]
            }
            struct Artist: Decodable { let name: String }
            let tracks: Tracks
        }
        return try JSONDecoder().decode(Response.self, from: data).tracks.items.map {
            SongResult(id: $0.uri, title: $0.name, artist: $0.artists.map(\.name).joined(separator: ", "),
                       app: .spotify)
        }
    }
}

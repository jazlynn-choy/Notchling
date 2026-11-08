import CryptoKit
import Foundation

/// The pieces of Spotify's "Authorization Code with PKCE" sign-in, as pure functions.
///
/// PKCE is the flow meant for apps that can't keep a secret: there's no client secret
/// in the app, just a Client ID, and a one-time code verifier proves that whoever swaps
/// the code for a token is the same app that started the sign-in.
public enum SpotifyAuth {
    public static let port: UInt16 = 43821
    public static let callbackPath = "/callback"
    /// Spotify only allows plain http for loopback IPs (not "localhost").
    public static let redirectURI = "http://127.0.0.1:\(port)\(callbackPath)"
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    // MARK: PKCE

    /// 64 random URL-safe characters (RFC 7636 allows 43–128).
    public static func makeVerifier() -> String {
        let bytes = (0..<48).map { _ in UInt8.random(in: .min ... .max) }
        return base64URL(Data(bytes))
    }

    /// `BASE64URL(SHA256(verifier))`, per RFC 7636 §4.2.
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: URLs and requests

    public static func authorizeURL(clientID: String, challenge: String, state: String) -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
            // Search needs no scopes; asking for none keeps the consent screen minimal.
        ]
        return components.url!
    }

    /// Pulls the code out of the redirect, checking `state` so a request from some other
    /// page can't inject its own code.
    public static func code(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw SpotifyError.signInFailed(error == "access_denied" ? "You cancelled the Spotify sign-in." : error)
        }
        guard value("state") == expectedState else { throw SpotifyError.signInFailed("The sign-in reply didn't match.") }
        guard let code = value("code"), !code.isEmpty else { throw SpotifyError.signInFailed("Spotify sent no code.") }
        return code
    }

    public static func tokenRequest(_ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(fields).utf8)
        return request
    }

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    /// Parses a token response. A refresh response may leave out `refresh_token`, in which
    /// case the old one stays valid, so it's passed in as the fallback.
    public static func tokens(from data: Data, now: Date, previousRefreshToken: String? = nil) throws -> SpotifyTokens {
        struct Response: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let refresh = response.refresh_token ?? previousRefreshToken else {
            throw SpotifyError.signInFailed("Spotify didn't send a refresh token.")
        }
        return SpotifyTokens(accessToken: response.access_token, refreshToken: refresh,
                             expiresAt: now.addingTimeInterval(response.expires_in))
    }
}

public struct SpotifyTokens: Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
}

public enum SpotifyError: LocalizedError, Equatable {
    case notConnected
    case signInFailed(String)
    case rateLimited
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Connect Spotify in Settings to search all of Spotify."
        case .signInFailed(let reason): return reason
        case .rateLimited: return "Spotify is busy. Try again in a moment."
        case .server(let code): return "Spotify returned an error (\(code))."
        }
    }
}

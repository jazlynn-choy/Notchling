import Foundation
import Network
import Testing
@testable import NotchlingCore

@Suite("Spotify sign-in pieces")
struct SpotifyAuthTests {
    @Test func challengeMatchesRFC7636Example() {
        // RFC 7636, Appendix B.
        #expect(SpotifyAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierIsURLSafeAndLongEnough() {
        let verifier = SpotifyAuth.makeVerifier()
        #expect((43...128).contains(verifier.count))
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(SpotifyAuth.makeVerifier() != verifier)
    }

    @Test func authorizeURLCarriesPKCEAndNoScopes() throws {
        let url = SpotifyAuth.authorizeURL(clientID: "abc", challenge: "ch", state: "st")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["client_id"] == "abc")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["redirect_uri"] == "http://127.0.0.1:43821/callback")
        #expect(query["scope"] == nil)
    }

    @Test func callbackCodeRequiresMatchingState() throws {
        let good = URL(string: "http://127.0.0.1/callback?code=c0de&state=s1")!
        #expect(try SpotifyAuth.code(from: good, expectedState: "s1") == "c0de")
        #expect(throws: SpotifyError.self) { try SpotifyAuth.code(from: good, expectedState: "other") }
        let denied = URL(string: "http://127.0.0.1/callback?error=access_denied&state=s1")!
        #expect(throws: SpotifyError.signInFailed("You cancelled the Spotify sign-in.")) {
            try SpotifyAuth.code(from: denied, expectedState: "s1")
        }
    }

    @Test func formEncodingEscapesReservedCharacters() {
        #expect(SpotifyAuth.formEncode(["b": "x y&z", "a": "1/2"]) == "a=1%2F2&b=x%20y%26z")
    }

    @Test func refreshResponseWithoutNewRefreshTokenKeepsTheOldOne() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let tokens = try SpotifyAuth.tokens(from: Data(#"{"access_token":"A","expires_in":3600}"#.utf8),
                                            now: now, previousRefreshToken: "R-old")
        #expect(tokens == SpotifyTokens(accessToken: "A", refreshToken: "R-old",
                                        expiresAt: now.addingTimeInterval(3600)))
    }

    @Test func parsesSearchResults() throws {
        let json = #"""
        {"tracks":{"items":[
          {"uri":"spotify:track:1","name":"Espresso","artists":[{"name":"Sabrina Carpenter"}]},
          {"uri":"spotify:track:2","name":"Die With A Smile","artists":[{"name":"Lady Gaga"},{"name":"Bruno Mars"}]}
        ]}}
        """#
        let results = try SpotifyCatalog.parseSearch(Data(json.utf8))
        #expect(results.map(\.artist) == ["Sabrina Carpenter", "Lady Gaga, Bruno Mars"])
        #expect(results.allSatisfy { $0.app == .spotify })
        #expect(results.first?.id == "spotify:track:1")
    }

    @Test func searchResultsCarryTheAlbumSoItKeepsPlaying() throws {
        let json = #"""
        {"tracks":{"items":[{"uri":"spotify:track:1","name":"Venom","artists":[{"name":"Little Simz"}],
          "album":{"uri":"spotify:album:9","images":[
            {"url":"https://i/640","width":640},{"url":"https://i/300","width":300},{"url":"https://i/64","width":64}]}}]}}
        """#
        let song = try #require(try SpotifyCatalog.parseSearch(Data(json.utf8)).first)
        #expect(song.contextURI == "spotify:album:9")
        #expect(song.artworkURL?.absoluteString == "https://i/64")
    }

    @Test func requestTargetParsing() {
        #expect(LoopbackCallbackServer.requestTarget(fromRequest: Data("GET /callback?code=1 HTTP/1.1\r\nHost: x\r\n\r\n".utf8))
                == "/callback?code=1")
        #expect(LoopbackCallbackServer.requestTarget(fromRequest: Data("POST /callback HTTP/1.1\r\n".utf8)) == nil)
        #expect(LoopbackCallbackServer.requestTarget(fromRequest: Data("garbage".utf8)) == nil)
    }

    /// A real listener on a real port, hit by a real HTTP request, including a stray
    /// favicon request first, as browsers do.
    @Test func loopbackServerReturnsTheCallbackURL() async throws {
        let port: UInt16 = 43_917
        let server = LoopbackCallbackServer()
        let waiting = Task { try await server.waitForCallback(port: port, path: "/callback", timeout: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(200))
        let favicon = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/favicon.ico")!)
        #expect((favicon.1 as? HTTPURLResponse)?.statusCode == 404)
        let (_, response) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(port)/callback?code=xyz&state=s")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let url = try await waiting.value
        #expect(url.absoluteString == "http://127.0.0.1:\(port)/callback?code=xyz&state=s")
    }
}

@MainActor
@Suite("Spotify connection")
struct SpotifyConnectionTests {
    let http = FakeHTTPClient()
    let secrets = InMemorySecretStore()
    let browser = FakeAuthCallback()
    var now = Date(timeIntervalSince1970: 1_794_063_600)

    func make(defaults: UserDefaults = makeIsolatedDefaults(), clientID: String? = "client-1") -> SpotifyConnection {
        if let clientID { defaults.set(clientID, forKey: SpotifyConnection.clientIDKey) }
        let browser = browser, now = now
        return SpotifyConnection(http: http, secrets: secrets, callbacks: browser, defaults: defaults,
                                 clock: { now }, openURL: { browser.authorizeURL = $0 })
    }

    @Test func needsAClientIDFirst() {
        #expect(make(clientID: nil).status == .needsClientID)
    }

    @Test func connectExchangesTheCodeAndStoresOnlyTheRefreshToken() async throws {
        http.handler = { _ in (200, #"{"access_token":"A1","expires_in":3600,"refresh_token":"R1"}"#) }
        let spotify = make()
        await spotify.connect()
        #expect(spotify.status == .connected)
        #expect(secrets.values == [SpotifyConnection.refreshTokenKey: "R1"])
        let body = http.formBody(of: try #require(http.requests.first))
        #expect(body["code"] == "the-code")
        #expect(body["grant_type"] == "authorization_code")
        #expect(body["code_verifier"]?.isEmpty == false)
        #expect(try await spotify.accessToken() == "A1")
        #expect(http.requests.count == 1)   // fresh token used as is
    }

    @Test func tamperedStateIsRejected() async {
        browser.reply = { _ in "/callback?code=evil&state=forged" }
        let spotify = make()
        await spotify.connect()
        #expect(spotify.status == .failed("The sign-in reply didn't match."))
        #expect(http.requests.isEmpty)
    }

    @Test func signedInStateSurvivesRelaunchAndRefreshesOnFirstUse() async throws {
        secrets.values[SpotifyConnection.refreshTokenKey] = "R1"
        http.handler = { _ in (200, #"{"access_token":"A2","expires_in":3600}"#) }
        let spotify = make()
        #expect(spotify.status == .connected)
        #expect(try await spotify.accessToken() == "A2")
        #expect(http.formBody(of: http.requests[0])["grant_type"] == "refresh_token")
    }

    @Test func concurrentCallsShareOneRefresh() async throws {
        secrets.values[SpotifyConnection.refreshTokenKey] = "R1"
        http.handler = { _ in (200, #"{"access_token":"A2","expires_in":3600}"#) }
        let spotify = make()
        async let first = spotify.accessToken()
        async let second = spotify.accessToken()
        let tokens = try await [first, second]
        #expect(tokens == ["A2", "A2"])
        #expect(http.requests.count == 1)
    }

    @Test func revokedRefreshTokenSignsOut() async {
        secrets.values[SpotifyConnection.refreshTokenKey] = "R1"
        http.handler = { _ in (400, #"{"error":"invalid_grant"}"#) }
        let spotify = make()
        await #expect(throws: SpotifyError.notConnected) { try await spotify.accessToken() }
        #expect(spotify.status == .failed(SpotifyConnection.signedOutMessage))
        #expect(secrets.values.isEmpty)
    }

    @Test func keepAliveRenewsEarlyButNotOnEveryCall() async throws {
        secrets.values[SpotifyConnection.refreshTokenKey] = "R1"
        var issued = 0
        http.handler = { _ in
            issued += 1
            return (200, #"{"access_token":"A\#(issued)","expires_in":3600,"refresh_token":"R\#(issued + 1)"}"#)
        }
        let spotify = make()
        await spotify.keepAlive()   // launch: validates by refreshing once
        await spotify.keepAlive()   // still fresh: no request
        #expect(http.requests.count == 1)
        #expect(spotify.status == .connected)
        #expect(secrets.values[SpotifyConnection.refreshTokenKey] == "R2")   // rotated token kept
    }

    @Test func beingOfflineDoesNotSignOut() async {
        secrets.values[SpotifyConnection.refreshTokenKey] = "R1"
        http.handler = { _ in throw URLError(.notConnectedToInternet) }
        let spotify = make()
        await spotify.keepAlive()
        #expect(spotify.status == .connected)
        #expect(secrets.values[SpotifyConnection.refreshTokenKey] == "R1")
    }

    @Test func changingClientIDSignsOut() {
        secrets.values[SpotifyConnection.refreshTokenKey] = "R1"
        let spotify = make()
        spotify.clientID = "  client-2 "
        #expect(spotify.clientID == "client-2")
        #expect(spotify.status == .disconnected)
        #expect(secrets.values.isEmpty)
    }

    @Test func catalogRetriesOnceWithAFreshTokenAfter401() async throws {
        let http = FakeHTTPClient()
        var calls = 0
        http.handler = { _ in
            calls += 1
            return calls == 1 ? (401, "") : (200, #"{"tracks":{"items":[]}}"#)
        }
        final class Box: @unchecked Sendable { var invalidated = 0 }
        let box = Box()
        let catalog = SpotifyCatalog(http: http, token: { "T" }, invalidateToken: { box.invalidated += 1 })
        #expect(try await catalog.search("x", limit: 5).isEmpty)
        #expect(calls == 2)
        #expect(box.invalidated == 1)
    }

    @Test func catalogReportsRateLimiting() async {
        let http = FakeHTTPClient()
        http.handler = { _ in (429, "") }
        let catalog = SpotifyCatalog(http: http, token: { "T" }, invalidateToken: {})
        await #expect(throws: SpotifyError.rateLimited) { try await catalog.search("x", limit: 5) }
    }

    @Test func searchShowsAConnectHintWhenSpotifyIsNotConnected() async {
        struct NotConnected: SongCatalog {
            func search(_ query: String, limit: Int) async throws -> [SongResult] { throw SpotifyError.notConnected }
        }
        let search = MusicSearch(media: FakeMediaProvider(), catalogs: [.spotify: NotConnected()],
                                 source: .spotify, debounce: .milliseconds(5))
        search.query = "anything"
        await search.settle()
        #expect(search.errorMessage == SpotifyError.notConnected.errorDescription)
        #expect(search.results.isEmpty)
    }
}

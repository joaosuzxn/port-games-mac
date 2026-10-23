import CoreImage
import Foundation
import Testing
@testable import LauncherCore

// MARK: - Fakes

/// Answers each request with the next canned response for the first route its URL contains.
actor FakeHTTP: HTTPClient {
    struct Response {
        var status = 200
        var json: String
        var eresult: Int? = 1
    }

    private var routes: [(path: String, responses: [Response])] = []
    private(set) var requests: [URLRequest] = []

    func on(_ path: String, _ responses: Response...) {
        routes.append((path, responses))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url?.absoluteString ?? ""
        guard let index = routes.firstIndex(where: { url.contains($0.path) && !$0.responses.isEmpty }) else {
            throw URLError(.cannotConnectToHost)
        }
        let response = routes[index].responses.removeFirst()
        var headers = ["Content-Type": "application/json"]
        if let eresult = response.eresult { headers["x-eresult"] = String(eresult) }
        return (Data(response.json.utf8),
            HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: headers)!)
    }

    /// The form fields of a POST, or the query items of a GET.
    func fields(of index: Int) -> [String: String] {
        let request = requests[index]
        var components = URLComponents()
        if let body = request.httpBody {
            components.percentEncodedQuery = String(decoding: body, as: UTF8.self)
        } else {
            components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        }
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}

final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: SteamSession?

    init(_ session: SteamSession? = nil) { self.session = session }

    func load() throws -> SteamSession? { lock.withLock { session } }
    func save(_ s: SteamSession) throws { lock.withLock { session = s } }
    func clear() throws { lock.withLock { session = nil } }
}

/// A JWT with only the claims the launcher reads (Steam's refresh tokens are JWTs).
func jwt(steamID: UInt64 = 76561198000000001, expires: Date = Date().addingTimeInterval(3600 * 24 * 100)) -> String {
    func encode(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    return encode(#"{"typ":"JWT","alg":"EdDSA"}"#) + "."
        + encode(#"{"sub":"\#(steamID)","exp":\#(Int(expires.timeIntervalSince1970))}"#) + ".c2lnbmF0dXJl"
}

private let begin = FakeHTTP.Response(json: """
    {"response":{"client_id":"111","challenge_url":"https://s.team/q/1/111","request_id":"cmVxdWVzdA==","interval":5,"version":1}}
    """)
private let pending = FakeHTTP.Response(json: #"{"response":{}}"#)

private func approved(_ refresh: String = jwt()) -> FakeHTTP.Response {
    FakeHTTP.Response(json: """
        {"response":{"refresh_token":"\(refresh)","access_token":"access-1","had_remote_interaction":true,"account_name":"joao"}}
        """)
}

/// Records the waits instead of sleeping.
private actor Sleeps {
    private(set) var all: [Duration] = []
    func add(_ d: Duration) { all.append(d) }
}

// MARK: - Tests

@Suite("SteamAuth")
struct SteamAuthTests {
    @Test func qrHappyPath() async throws {
        let http = FakeHTTP()
        await http.on("BeginAuthSessionViaQR", begin)
        await http.on("PollAuthSessionStatus", pending, approved())
        let store = MemoryTokenStore()
        let sleeps = Sleeps()
        let auth = SteamAuth(http: http, store: store, sleep: { await sleeps.add($0) })

        let login = try await auth.beginQR()
        #expect(login.challengeURL.absoluteString == "https://s.team/q/1/111")
        let session = try await auth.waitForApproval(login) { _ in }

        #expect(session == SteamSession(
            accountName: "joao", steamID: 76561198000000001, refreshToken: jwt(), accessToken: "access-1"))
        #expect(try store.load() == session)
        // Polled at Steam's interval, not in a tight loop.
        #expect(await sleeps.all == [.seconds(5), .seconds(5)])
        let beginFields = await http.fields(of: 0)
        #expect(beginFields["device_friendly_name"] == "Port Games")
        #expect(beginFields["platform_type"] == "1")
        let pollFields = await http.fields(of: 1)
        #expect(pollFields["client_id"] == "111")
        #expect(pollFields["request_id"] == "cmVxdWVzdA==")
    }

    @Test func qrNewChallengeURL() async throws {
        let http = FakeHTTP()
        await http.on("BeginAuthSessionViaQR", begin)
        await http.on("PollAuthSessionStatus",
            FakeHTTP.Response(json: #"{"response":{"new_client_id":"222","new_challenge_url":"https://s.team/q/1/222"}}"#),
            approved())
        let auth = SteamAuth(http: http, store: MemoryTokenStore(), sleep: { _ in })
        let shown = Sleeps()  // reused as a recorder of the URLs shown

        let login = try await auth.beginQR()
        _ = try await auth.waitForApproval(login) { url in
            Task { await shown.add(.seconds(url.absoluteString == "https://s.team/q/1/222" ? 1 : 0)) }
        }

        // The new QR replaced the old one, and the next poll uses the new client id.
        #expect(await http.fields(of: 2)["client_id"] == "222")
        try await Task.sleep(for: .milliseconds(50))
        #expect(await shown.all == [.seconds(1)])
    }

    @Test func expiredQRIsAnError() async throws {
        let http = FakeHTTP()
        await http.on("BeginAuthSessionViaQR", begin)
        await http.on("PollAuthSessionStatus", FakeHTTP.Response(json: #"{"response":{}}"#, eresult: 9))
        let auth = SteamAuth(http: http, store: MemoryTokenStore(), sleep: { _ in })

        let login = try await auth.beginQR()
        await #expect(throws: SteamAuthError.loginFailed(eresult: 9)) {
            try await auth.waitForApproval(login) { _ in }
        }
    }

    @Test func validSessionRenewsAccessToken() async throws {
        let http = FakeHTTP()
        await http.on("GenerateAccessTokenForApp", FakeHTTP.Response(json: #"{"response":{"access_token":"access-2"}}"#))
        let stored = SteamSession(accountName: "joao", steamID: 76561198000000001, refreshToken: jwt(), accessToken: "old")
        let store = MemoryTokenStore(stored)

        let session = try await SteamAuth(http: http, store: store).validSession()

        #expect(session?.accessToken == "access-2")
        #expect(try store.load()?.accessToken == "access-2")
        let fields = await http.fields(of: 0)
        #expect(fields["refresh_token"] == jwt())
        #expect(fields["steamid"] == "76561198000000001")
    }

    @Test(arguments: [
        FakeHTTP.Response(status: 401, json: "", eresult: nil),
        FakeHTTP.Response(json: #"{"response":{}}"#, eresult: 26),  // revoked
    ])
    func revokedTokenClearsAndReturnsNil(response: FakeHTTP.Response) async throws {
        let http = FakeHTTP()
        await http.on("GenerateAccessTokenForApp", response)
        let store = MemoryTokenStore(SteamSession(accountName: "joao", steamID: 1, refreshToken: jwt(), accessToken: "old"))

        #expect(try await SteamAuth(http: http, store: store).validSession() == nil)
        #expect(try store.load() == nil)
    }

    /// Steam being busy or down is not a logout: the session stays and the error goes up.
    @Test(arguments: [
        FakeHTTP.Response(status: 429, json: "", eresult: nil),
        FakeHTTP.Response(json: #"{"response":{}}"#, eresult: 20),  // ServiceUnavailable
        FakeHTTP.Response(json: #"{"response":{}}"#, eresult: 84),  // RateLimitExceeded
        FakeHTTP.Response(json: #"{"response":{}}"#),  // OK but no access token
    ])
    func transientFailureKeepsTheSession(response: FakeHTTP.Response) async throws {
        let http = FakeHTTP()
        await http.on("GenerateAccessTokenForApp", response)
        let stored = SteamSession(accountName: "joao", steamID: 1, refreshToken: jwt(), accessToken: "old")
        let store = MemoryTokenStore(stored)

        await #expect(throws: (any Error).self) { try await SteamAuth(http: http, store: store).validSession() }
        #expect(try store.load() == stored)
    }

    @Test func expiredRefreshTokenNeedsNoNetwork() async throws {
        let http = FakeHTTP()
        let store = MemoryTokenStore(SteamSession(
            accountName: "joao", steamID: 1, refreshToken: jwt(expires: Date().addingTimeInterval(-60)), accessToken: "old"))

        #expect(try await SteamAuth(http: http, store: store).validSession() == nil)
        #expect(try store.load() == nil)
        #expect(await http.requests.isEmpty)
    }

    @Test func offlineKeepsTheSession() async throws {
        // No route: the fake fails like a missing network. That is not a reason to forget the login.
        let http = FakeHTTP()
        let stored = SteamSession(accountName: "joao", steamID: 1, refreshToken: jwt(), accessToken: "old")
        let store = MemoryTokenStore(stored)

        await #expect(throws: URLError.self) { try await SteamAuth(http: http, store: store).validSession() }
        #expect(try store.load() == stored)
    }

    @Test func noStoredSessionIsNil() async throws {
        #expect(try await SteamAuth(http: FakeHTTP(), store: MemoryTokenStore()).validSession() == nil)
    }

    @Test func qrImageEncodesTheURL() throws {
        let url = URL(string: "https://s.team/q/1/1234567890")!
        let png = try QRImage.png(for: url, scale: 8)

        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let image = try #require(CIImage(data: png))
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil))
        let message = (detector.features(in: image).first as? CIQRCodeFeature)?.messageString
        #expect(message == url.absoluteString)
    }
}

import Foundation
import Testing
@testable import LauncherCore

@Suite("LoggingHTTPClient")
struct LoggingHTTPClientTests {
    @Test func logsTheAnswerButNoSecret() async throws {
        try await withAsyncScratchDirectory { dir in
            let refresh = jwt(steamID: 76561198000000001)
            let fake = FakeHTTP()
            await fake.on("GenerateAccessTokenForApp", FakeHTTP.Response(
                json: #"{"response":{"access_token":"\#(refresh)","extra":1}}"#, eresult: 63))
            let log = dir.appendingPathComponent("logs/steam-api.log")
            let client = LoggingHTTPClient(base: fake, log: log)
            var request = URLRequest(url: URL(string:
                "https://api.steampowered.com/IAuthenticationService/GenerateAccessTokenForApp/v1/?access_token=SECRET1")!)
            request.httpMethod = "POST"
            request.httpBody = Data("refresh_token=SECRET2&steamid=1".utf8)

            _ = try await client.send(request)

            let text = try String(contentsOf: log, encoding: .utf8)
            #expect(text.contains("POST /IAuthenticationService/GenerateAccessTokenForApp/v1"))
            #expect(text.contains("HTTP 200"))
            #expect(text.contains("eresult 63"))
            #expect(text.contains("access_token"))  // the key, not the value
            #expect(text.contains("extra"))
            #expect(text.contains("sub=76561198000000001"))
            #expect(text.contains("exp="))
            for secret in ["SECRET1", "SECRET2", refresh, "c2lnbmF0dXJl"] {
                #expect(!text.contains(secret), "\(secret) leaked")
            }
        }
    }
}

import Foundation

/// Sends one HTTP request. A protocol so the Steam code can be tested with canned responses.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Calls to Steam's Web API (`api.steampowered.com`).
struct SteamWebAPI {
    let http: HTTPClient

    static let base = URL(string: "https://api.steampowered.com")!

    struct Reply {
        let status: Int
        /// Steam's result code (`x-eresult`); 1 is OK.
        let eresult: Int?
        /// The `response` object of the body, empty when there is none.
        let response: [String: Any]
    }

    /// POST with form fields.
    func post(_ method: String, _ fields: [String: String]) async throws -> Reply {
        var request = URLRequest(url: Self.base.appendingPathComponent(method + "/v1/"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // `+` is a space in a form body; URLComponents leaves it alone.
        request.httpBody = Data((components.percentEncodedQuery ?? "")
            .replacingOccurrences(of: "+", with: "%2B").utf8)
        return try await send(request)
    }

    /// GET with query fields.
    func get(_ method: String, _ fields: [String: String]) async throws -> Reply {
        var components = URLComponents(url: Self.base.appendingPathComponent(method + "/v1/"), resolvingAgainstBaseURL: false)!
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return try await send(URLRequest(url: components.url!))
    }

    private func send(_ request: URLRequest) async throws -> Reply {
        let (data, response) = try await http.send(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return Reply(
            status: response.statusCode,
            eresult: (response.value(forHTTPHeaderField: "x-eresult")).flatMap { Int($0) },
            response: json?["response"] as? [String: Any] ?? [:])
    }
}

/// Wraps a client and appends one line per Steam call to a log: method, path, HTTP status, EResult,
/// `x-error_message`, the keys of the `response` object and the claims of any token in it (subject,
/// audience, expiry). Never a query, a body or a token: they hold secrets.
public struct LoggingHTTPClient: HTTPClient {
    let base: HTTPClient
    let log: URL

    public init(base: HTTPClient, log: URL) {
        self.base = base
        self.log = log
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let line = "[\(Date().ISO8601Format())] \(request.httpMethod ?? "GET") \(request.url?.path ?? "?")"
        do {
            let (data, response) = try await base.send(request)
            var parts = [line, "→ HTTP \(response.statusCode)"]
            if let eresult = response.value(forHTTPHeaderField: "x-eresult") { parts.append("eresult \(eresult)") }
            if let message = response.value(forHTTPHeaderField: "x-error_message") { parts.append("message \"\(message)\"") }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let fields = json?["response"] as? [String: Any] {
                parts.append("keys \(fields.keys.sorted())")
                for key in fields.keys.sorted() where key.hasSuffix("token") {
                    guard let token = fields[key] as? String, let claims = JWT.claims(token) else { continue }
                    let aud = (claims["aud"] as? [String])?.joined(separator: ",") ?? "\(claims["aud"] ?? "-")"
                    parts.append("\(key){sub=\(claims["sub"] ?? "-") aud=\(aud) exp=\(claims["exp"] ?? "-")}")
                }
            }
            append(parts.joined(separator: " "))
            return (data, response)
        } catch {
            append(line + " → error \(error)")
            throw error
        }
    }

    private func append(_ line: String) {
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(log.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle.write(Data((line + "\n").utf8))
    }
}

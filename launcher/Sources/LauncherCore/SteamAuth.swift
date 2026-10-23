import CoreImage
import Foundation
import ImageIO
import Security
import UniformTypeIdentifiers

/// A logged-in Steam account: the refresh token (long-lived, from the QR login) and an access token
/// made from it.
public struct SteamSession: Codable, Equatable, Sendable {
    public var accountName: String
    public var steamID: UInt64
    public var refreshToken: String
    public var accessToken: String

    public init(accountName: String, steamID: UInt64, refreshToken: String, accessToken: String) {
        self.accountName = accountName
        self.steamID = steamID
        self.refreshToken = refreshToken
        self.accessToken = accessToken
    }
}

public enum SteamAuthError: Error, LocalizedError, Equatable {
    /// No valid login: show the QR again.
    case notLoggedIn
    /// Steam refused or expired the QR login (`eresult`).
    case loginFailed(eresult: Int)
    /// Steam answered with something unexpected.
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "not logged in to Steam; log in again with the QR code"
        case .loginFailed(let eresult): return "the Steam QR login failed or expired (EResult \(eresult)); try again"
        case .unexpectedResponse(let detail): return "unexpected answer from Steam: \(detail)"
        }
    }
}

/// Where the session is kept between runs.
public protocol TokenStore: Sendable {
    func load() throws -> SteamSession?
    func save(_ s: SteamSession) throws
    func clear() throws
}

/// The session in the login Keychain (generic password, service `com.portgames.steam`).
public struct KeychainTokenStore: TokenStore {
    let service: String

    public init(service: String = "com.portgames.steam") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "session"]
    }

    public func load() throws -> SteamSession? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        let status = SecItemCopyMatching(search as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw keychainError(status) }
        return try JSONDecoder().decode(SteamSession.self, from: data)
    }

    public func save(_ s: SteamSession) throws {
        let data = try JSONEncoder().encode(s)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw keychainError(added) }
        } else if status != errSecSuccess {
            throw keychainError(status)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }

    private func keychainError(_ status: OSStatus) -> Error {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}

/// A QR login in progress: what to show, and what to poll with.
public struct QRLogin: Sendable {
    public let challengeURL: URL
    public let interval: Duration
    let clientID: String
    let requestID: String
}

/// Steam login by QR code (scanned with the Steam app on the phone), with the token kept for later runs.
public actor SteamAuth {
    private let api: SteamWebAPI
    private let store: TokenStore
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        http: HTTPClient, store: TokenStore,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        api = SteamWebAPI(http: http)
        self.store = store
        self.sleep = sleep
    }

    public func beginQR() async throws -> QRLogin {
        let reply = try await api.post(
            "IAuthenticationService/BeginAuthSessionViaQR",
            ["device_friendly_name": "Port Games", "platform_type": "1"])
        guard reply.status == 200, reply.eresult ?? 1 == 1,
            let clientID = Self.string(reply.response["client_id"]),
            let url = (reply.response["challenge_url"] as? String).flatMap(URL.init(string:)),
            let requestID = reply.response["request_id"] as? String
        else { throw SteamAuthError.loginFailed(eresult: reply.eresult ?? reply.status) }
        let interval = (reply.response["interval"] as? Double) ?? 5
        return QRLogin(challengeURL: url, interval: .milliseconds(Int(interval * 1000)), clientID: clientID, requestID: requestID)
    }

    /// Polls until the login is approved on the phone, saves the session and returns it. When Steam
    /// replaces the QR, `newChallenge` gets the URL to show instead.
    public func waitForApproval(
        _ login: QRLogin, newChallenge: @Sendable (URL) -> Void
    ) async throws -> SteamSession {
        var clientID = login.clientID
        while true {
            try await sleep(login.interval)
            let reply = try await api.post(
                "IAuthenticationService/PollAuthSessionStatus",
                ["client_id": clientID, "request_id": login.requestID])
            guard reply.status == 200, reply.eresult ?? 1 == 1 else {
                throw SteamAuthError.loginFailed(eresult: reply.eresult ?? reply.status)
            }
            if let newID = Self.string(reply.response["new_client_id"]) { clientID = newID }
            if let url = (reply.response["new_challenge_url"] as? String).flatMap(URL.init(string:)) {
                newChallenge(url)
            }
            if let refresh = reply.response["refresh_token"] as? String,
                let access = reply.response["access_token"] as? String
            {
                guard let steamID = JWT.subject(refresh) else {
                    throw SteamAuthError.unexpectedResponse("refresh token without a SteamID")
                }
                let session = SteamSession(
                    accountName: reply.response["account_name"] as? String ?? "", steamID: steamID,
                    refreshToken: refresh, accessToken: access)
                try store.save(session)
                return session
            }
        }
    }

    /// The saved session with a fresh access token, or `nil` when there is none or Steam no longer
    /// accepts it (then it is forgotten, and the QR must be shown again). Network errors are thrown and
    /// keep the session: being offline is not a logout.
    public func validSession() async throws -> SteamSession? {
        guard var session = try store.load() else { return nil }
        if let expiry = JWT.expiry(session.refreshToken), expiry <= Date() {
            try store.clear()
            return nil
        }
        let reply = try await api.post(
            "IAuthenticationService/GenerateAccessTokenForApp",
            ["refresh_token": session.refreshToken, "steamid": String(session.steamID)])
        if reply.status >= 500 { throw URLError(.badServerResponse) }
        guard reply.status == 200, reply.eresult ?? 1 == 1, let access = reply.response["access_token"] as? String else {
            try store.clear()
            return nil
        }
        session.accessToken = access
        // Steam may rotate the refresh token as well.
        if let refresh = reply.response["refresh_token"] as? String { session.refreshToken = refresh }
        try store.save(session)
        return session
    }

    /// Steam sends 64-bit IDs as strings (and some as numbers).
    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}

/// The two claims read from Steam's JWTs; the signature is Steam's business, not checked here.
enum JWT {
    static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func subject(_ token: String) -> UInt64? {
        (claims(token)?["sub"] as? String).flatMap { UInt64($0) }
    }

    static func expiry(_ token: String) -> Date? {
        (claims(token)?["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
    }
}

public enum QRImageError: Error {
    case renderFailed
}

/// The QR code of a login URL, as a PNG.
public enum QRImage {
    public static func png(for url: URL, scale: CGFloat) throws -> Data {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw QRImageError.renderFailed }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
            let image = CIContext().createCGImage(code, from: code.extent)
        else { throw QRImageError.renderFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw QRImageError.renderFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw QRImageError.renderFailed }
        return data as Data
    }
}

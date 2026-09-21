//
//  TokenService.swift
//  iPhone → authenticated token service → short-lived Millicast publish token.
//
//  • The Millicast API secret NEVER exists on the phone. It lives only in the backend
//    (backend/token-service, a Cloudflare Worker secret).
//  • The phone holds an operator key (Keychain). It trades it for a session token (12 h),
//    then asks for a publish token that expires (default 4 h) and is revoked on STOP.
//  • Publish tokens are kept in memory only.
//

import Foundation

struct SessionToken: Codable, Equatable {
    let token: String
    let expiresAt: Date
    func isValid(margin: TimeInterval = 300, now: Date = Date()) -> Bool { expiresAt.timeIntervalSince(now) > margin }
}

struct PublishCredentials: Equatable {
    let streamName: String
    let token: String
    let tokenID: String?
    let apiURL: String
    let expiresAt: Date?
    let isDeveloperToken: Bool
}

struct OperatorCredentials: Codable, Equatable {
    var operatorID: String
    var operatorKey: String
}

enum TokenServiceError: LocalizedError, Equatable {
    case notConfigured, insecureURL, notSignedIn, http(Int, String), badResponse
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Token service URL is not set (DTEK_TOKEN_SERVICE_URL)."
        case .insecureURL: return "Token service must use HTTPS."
        case .notSignedIn: return "Sign in with your operator key first."
        case .http(let code, let msg): return "Token service error \(code): \(msg)"
        case .badResponse: return "Token service returned an unexpected response."
        }
    }
}

final class TokenService {
    private let keychain: KeychainStore
    private let session: URLSession
    private let baseURL: URL?

    static let millicastPublishAPI = "https://director.millicast.com/api/director/publish"

    private enum Account {
        static let operatorCreds = "operator.credentials"
        static let session = "session.token"
        static let devToken = "dev.publish.token"
        static let devStream = "dev.stream.name"
    }

    init(keychain: KeychainStore = KeychainStore(), bundle: Bundle = .main) {
        self.keychain = keychain
        let cfg = URLSessionConfiguration.ephemeral          // no cookies / no disk cache of tokens
        cfg.timeoutIntervalForRequest = 10
        cfg.tlsMinimumSupportedProtocolVersion = .TLSv12
        cfg.urlCache = nil
        self.session = URLSession(configuration: cfg)
        let raw = ((bundle.object(forInfoDictionaryKey: "DTEKTokenServiceURL") ?? bundle.object(forInfoDictionaryKey: "DEKATokenServiceURL")) as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        self.baseURL = raw.isEmpty || raw.contains("example.com") ? nil : URL(string: raw)
    }

    var isConfigured: Bool { baseURL != nil }
    var serviceHost: String { baseURL?.host ?? "not configured" }

    // MARK: Operator sign-in

    var isSignedIn: Bool { keychain.codable(OperatorCredentials.self, for: Account.operatorCreds) != nil }

    func signIn(_ creds: OperatorCredentials) async throws {
        try keychain.setCodable(creds, for: Account.operatorCreds)
        try? keychain.delete(Account.session)
        _ = try await validSession()     // proves the key works
    }

    func signOut() {
        try? keychain.delete(Account.operatorCreds)
        try? keychain.delete(Account.session)
    }

    // MARK: Developer token (testing without a backend — clearly flagged in the UI)

    func setDeveloperToken(_ token: String, streamName: String) throws {
        try keychain.setString(token, for: Account.devToken)
        try keychain.setString(streamName, for: Account.devStream)
    }
    func clearDeveloperToken() { try? keychain.delete(Account.devToken); try? keychain.delete(Account.devStream) }
    var hasDeveloperToken: Bool { keychain.string(for: Account.devToken) != nil }

    // MARK: Tokens

    func publishCredentials(streamName: String) async throws -> PublishCredentials {
        if baseURL == nil, let dev = keychain.string(for: Account.devToken) {
            let name = keychain.string(for: Account.devStream) ?? streamName
            return PublishCredentials(streamName: name, token: dev, tokenID: nil,
                                      apiURL: Self.millicastPublishAPI, expiresAt: nil, isDeveloperToken: true)
        }
        let s = try await validSession()
        struct Req: Encodable { let streamName: String }
        struct Res: Decodable { let streamName: String; let token: String; let tokenId: String?; let apiUrl: String?; let expiresAt: Date? }
        let res: Res = try await request("v1/publish-token", method: "POST", body: Req(streamName: streamName), bearer: s.token)
        return PublishCredentials(streamName: res.streamName, token: res.token, tokenID: res.tokenId,
                                  apiURL: res.apiUrl ?? Self.millicastPublishAPI, expiresAt: res.expiresAt,
                                  isDeveloperToken: false)
    }

    /// Revoke the publish token when the operator stops (best effort; it also expires on its own).
    func revoke(_ creds: PublishCredentials) async {
        guard let id = creds.tokenID, let s = try? await validSession() else { return }
        struct Empty: Decodable {}
        let _: Empty? = try? await request("v1/publish-token/\(id)", method: "DELETE", body: Optional<String>.none, bearer: s.token)
    }

    /// GET /v1/health — reachability only, no credentials sent.
    func healthCheck() async -> Bool {
        guard let baseURL, baseURL.scheme?.lowercased() == "https" else { return false }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/health"))
        req.timeoutInterval = 5
        guard let (_, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// Proves the operator key still works (creates/refreshes the session, no publish token).
    func verifySession() async throws { _ = try await validSession() }

    private func validSession() async throws -> SessionToken {
        if let cached = keychain.codable(SessionToken.self, for: Account.session), cached.isValid() { return cached }
        guard let creds = keychain.codable(OperatorCredentials.self, for: Account.operatorCreds) else {
            throw TokenServiceError.notSignedIn
        }
        struct Res: Decodable { let sessionToken: String; let expiresAt: Date }
        let res: Res = try await request("v1/session", method: "POST", body: creds, bearer: nil)
        let token = SessionToken(token: res.sessionToken, expiresAt: res.expiresAt)
        try keychain.setCodable(token, for: Account.session)     // rotation: replaced on every refresh
        return token
    }

    private func request<B: Encodable, R: Decodable>(_ path: String, method: String, body: B?, bearer: String?) async throws -> R {
        guard let baseURL else { throw TokenServiceError.notConfigured }
        guard baseURL.scheme?.lowercased() == "https" else { throw TokenServiceError.insecureURL }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw TokenServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            if http.statusCode == 401 { try? keychain.delete(Account.session) }
            throw TokenServiceError.http(http.statusCode, String(msg))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if data.isEmpty, let empty = try? decoder.decode(R.self, from: Data("{}".utf8)) { return empty }
        do { return try decoder.decode(R.self, from: data) } catch { throw TokenServiceError.badResponse }
    }
}

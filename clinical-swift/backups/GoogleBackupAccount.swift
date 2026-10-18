import CryptoKit
import Foundation
import Security

nonisolated struct GoogleBackupConfiguration: Sendable {
    let clientID: String
    let callbackScheme: String

    var redirectURI: String { callbackScheme + ":/oauthredirect" }

    static func live() throws -> Self {
        guard
            let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleBackupClientID")
                as? String,
            let scheme = Bundle.main.object(forInfoDictionaryKey: "GoogleBackupCallbackScheme")
                as? String,
            clientID.hasSuffix(".apps.googleusercontent.com"), !scheme.isEmpty,
            !clientID.contains("$("), !scheme.contains("$(")
        else { throw BackupError.configurationRequired }
        return Self(clientID: clientID, callbackScheme: scheme)
    }
}

nonisolated struct GoogleAuthorizationRequest: Sendable {
    let url: URL
    let configuration: GoogleBackupConfiguration
    let verifier: String
    let state: String

    init(configuration: GoogleBackupConfiguration) throws {
        self.configuration = configuration
        verifier = try Self.randomValue()
        state = try Self.randomValue()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(
                name: "scope", value: "openid email https://www.googleapis.com/auth/drive.file"),
            URLQueryItem(
                name: "code_challenge",
                value: Data(SHA256.hash(data: Data(verifier.utf8))).base64URL),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account"),
        ]
        guard let url = components?.url else { throw BackupError.configurationRequired }
        self.url = url
    }

    private static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
        else { throw BackupError.authorizationRequired }
        return Data(bytes).base64URL
    }
}

nonisolated struct GoogleBackupTokens: Codable, Sendable {
    let accountID: String
    let email: String
    let clientID: String
    var accessToken: String
    let refreshToken: String
    var expiresAt: Date
    var deviceCheck: BackupDeviceCheck? = nil
}

nonisolated struct BackupDeviceCheck: Codable, Sendable {
    let clientID: String
    let callbackScheme: String
    let checkedAt: Date
    let releaseOnDevice: Bool
}

actor GoogleBackupAccount {
    private let session: URLSession
    private let keychain: BackupKeychain

    init(session: URLSession = .shared, keychain: BackupKeychain = BackupKeychain()) {
        self.session = session
        self.keychain = keychain
    }

    func complete(
        _ request: GoogleAuthorizationRequest, callback: URL, expectedAccountID: String?
    ) async throws -> GoogleBackupTokens {
        guard callback.scheme == request.configuration.callbackScheme,
            let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
            components.queryItems?.first(where: { $0.name == "state" })?.value == request.state,
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            components.queryItems?.contains(where: { $0.name == "error" }) != true
        else { throw BackupError.authorizationRequired }
        let response = try await exchange([
            "client_id": request.configuration.clientID,
            "code": code, "code_verifier": request.verifier,
            "redirect_uri": request.configuration.redirectURI, "grant_type": "authorization_code",
        ])
        guard let userURL = URL(string: "https://openidconnect.googleapis.com/v1/userinfo") else {
            throw BackupError.configurationRequired
        }
        var userRequest = URLRequest(url: userURL)
        userRequest.setValue("Bearer " + response.access_token, forHTTPHeaderField: "Authorization")
        let (data, http) = try await session.data(for: userRequest)
        try GoogleDriveClient.check(http)
        let identity = try JSONDecoder().decode(Identity.self, from: data)
        guard expectedAccountID == nil || expectedAccountID == identity.sub else {
            throw BackupError.accountChanged
        }
        guard let refreshToken = response.refresh_token else {
            throw BackupError.authorizationRequired
        }
        let tokens = GoogleBackupTokens(
            accountID: identity.sub, email: identity.email,
            clientID: request.configuration.clientID, accessToken: response.access_token,
            refreshToken: refreshToken, expiresAt: .now.addingTimeInterval(response.expires_in)
        )
        try keychain.save(tokens)
        return tokens
    }

    func accessToken(expectedAccountID: String) async throws -> String {
        try Task.checkCancellation()
        let tokens = try keychain.load()
        guard tokens.accountID == expectedAccountID else { throw BackupError.accountChanged }
        if tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.accessToken }
        // Refresh stays in the caller's task so background expiration cancels its request.
        let response = try await exchange([
            "client_id": tokens.clientID, "refresh_token": tokens.refreshToken,
            "grant_type": "refresh_token",
        ])
        try Task.checkCancellation()
        var refreshed = tokens
        refreshed.accessToken = response.access_token
        refreshed.expiresAt = .now.addingTimeInterval(response.expires_in)
        try keychain.save(refreshed)
        return refreshed.accessToken
    }

    private func exchange(_ fields: [String: String]) async throws -> TokenResponse {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw BackupError.configurationRequired
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        request.httpBody = form.percentEncodedQuery?.replacing("+", with: "%2B").data(using: .utf8)
        request.timeoutInterval = 60
        let (data, response) = try await session.data(for: request)
        try GoogleDriveClient.check(response)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: TimeInterval
    }

    private struct Identity: Decodable {
        let sub: String
        let email: String
    }
}

nonisolated struct BackupKeychain: Sendable {
    var service = "in.bitehaus.clinical.backups"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "google",
        ]
    }

    func load() throws -> GoogleBackupTokens {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { throw BackupError.authorizationRequired }
        return try JSONDecoder().decode(GoogleBackupTokens.self, from: data)
    }

    func remove() {
        SecItemDelete(query as CFDictionary)
    }

    func save(_ tokens: GoogleBackupTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw BackupError.authorizationRequired
            }
        } else if status != errSecSuccess {
            throw BackupError.authorizationRequired
        }
    }
}

nonisolated extension Data {
    fileprivate var base64URL: String {
        base64EncodedString().replacing("+", with: "-").replacing("/", with: "_").replacing(
            "=", with: "")
    }
}

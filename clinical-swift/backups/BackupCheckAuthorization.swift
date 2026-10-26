#if INTERNAL_BACKUP_CHECK
    import AuthenticationServices
    import Dependencies
    import Observation
    import SwiftUI

    @MainActor @Observable
    final class BackupCheckAuthorization {
        @ObservationIgnored @Dependency(\.date.now) private var now
        private(set) var isConnecting = false
        private(set) var email: String?
        private(set) var problem: String?
        private let account: GoogleBackupAccount
        private let credentialsURL: URL

        static var isRequested: Bool {
            CommandLine.arguments.contains("--backup-check-authorize")
        }

        init(
            account: GoogleBackupAccount = GoogleBackupAccount(
                keychain: BackupKeychain(service: "in.bitehaus.clinical.backups.check")),
            credentialsURL: URL = .documentsDirectory.appending(
                path: "backup-check-credentials.json")
        ) {
            self.account = account
            self.credentialsURL = credentialsURL
        }

        func connect(authenticate: (GoogleAuthorizationRequest) async throws -> URL) async {
            guard !isConnecting else { return }
            isConnecting = true
            email = nil
            problem = nil
            defer { isConnecting = false }
            do {
                let request = try GoogleAuthorizationRequest(configuration: .live())
                let callback = try await authenticate(request)
                // Test authorization has no clinic dataset or pending upload to reassign.
                var tokens = try await account.complete(
                    request, callback: callback, expectedAccountID: nil)
                #if DEBUG || targetEnvironment(simulator)
                    let releaseOnDevice = false
                #else
                    let releaseOnDevice = true
                #endif
                tokens.deviceCheck = BackupDeviceCheck(
                    clientID: request.configuration.clientID,
                    callbackScheme: request.configuration.callbackScheme,
                    checkedAt: now, releaseOnDevice: releaseOnDevice)
                // Only an explicit internal build can export isolated test credentials.
                try BackupFiles.save(tokens, to: credentialsURL)
                email = tokens.email
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    struct BackupCheckAuthorizationView: View {
        @Environment(\.webAuthenticationSession) private var authentication
        @State private var authorization = BackupCheckAuthorization()

        var body: some View {
            NavigationStack {
                Form {
                    Section("Test account") {
                        Text("Use a separate Google account for backup checks.")
                        if let email = authorization.email {
                            LabeledContent("Account", value: email)
                            Text("Test credentials saved. You can export them now.")
                        }
                        if let problem = authorization.problem {
                            Text(problem).foregroundStyle(AppColor.warning)
                        }
                        AsyncButton("Connect Google Drive", systemImage: "externaldrive") {
                            await authorization.connect { request in
                                try await authentication.authenticate(
                                    using: request.url,
                                    callback: .customScheme(request.configuration.callbackScheme),
                                    additionalHeaderFields: [:])
                            }
                        }
                        .disabled(authorization.isConnecting)
                    }
                }
                .navigationTitle("Backup check setup")
            }
        }
    }
#endif

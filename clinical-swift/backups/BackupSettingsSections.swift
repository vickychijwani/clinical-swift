import AuthenticationServices
import ClinicalModels
import SwiftUI

struct BackupSettingsSections: View {
    @Environment(BackupCoordinator.self) private var backups
    @Environment(\.webAuthenticationSession) private var authentication

    var body: some View {
        Section("Patient data backups") {
            LabeledContent("Status", value: backups.status)
            if let capturedAt = backups.state.lastSuccess?.capturedAt {
                LabeledContent("Last successful snapshot") {
                    Text(
                        capturedAt,
                        format: ClinicDate.formatStyle.day().month().year().hour().minute()
                    )
                }
            } else {
                LabeledContent("Last successful snapshot", value: "None")
            }
            if let problem = backups.problem {
                Text(problem).foregroundStyle(AppColor.warning)
            }
        }
        Section("Google Drive") {
            if let email = backups.state.accountEmail {
                LabeledContent("Account", value: email)
            }
            AsyncButton(
                backups.state.accountID == nil
                    ? "Connect Google Drive" : "Reconnect Google Drive",
                systemImage: "externaldrive"
            ) {
                await backups.connect { request in
                    try await authentication.authenticate(
                        using: request.url,
                        callback: .customScheme(request.configuration.callbackScheme),
                        additionalHeaderFields: [:]
                    )
                }
            }
            .disabled(backups.isRunning || backups.isConnecting)
            AsyncButton("Retry backup", systemImage: "arrow.clockwise") {
                await backups.retry()
            }
            .disabled(
                backups.isRunning || backups.isConnecting || backups.state.accountID == nil)
        }
    }
}

import AuthenticationServices
import ClinicalModels
import SwiftUI

struct BackupSettingsView: View {
    @Environment(BackupCoordinator.self) private var backups
    @Environment(TelemetryCoordinator.self) private var telemetry
    @Environment(\.webAuthenticationSession) private var authentication
    @Environment(\.trayDismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
                Section {
                    LabeledContent("Status", value: telemetry.statusText)
                    if let lastUploadedAt = telemetry.lastUploadedAt {
                        LabeledContent("Last upload") {
                            Text(
                                lastUploadedAt,
                                format: ClinicDate.formatStyle.day().month().year().hour().minute()
                            )
                        }
                    } else {
                        LabeledContent("Last upload", value: "Never")
                    }
                    if let error = telemetry.lastUploadError {
                        Text(error).foregroundStyle(AppColor.warning)
                    }
                    AsyncButton("Send logs now", systemImage: "arrow.up.doc") {
                        await telemetry.sendNow()
                    }
                    .disabled(telemetry.isUploading || !telemetry.isUploadConfigured)
                    ShareLink(
                        "Export logs",
                        item: telemetry.exportDocument,
                        preview: SharePreview("Clinical diagnostic logs")
                    )
                    Toggle(
                        "Verbose logging",
                        isOn: Binding(
                            get: { telemetry.isVerboseEnabled },
                            set: { telemetry.setVerboseEnabled($0) }
                        )
                    )
                } header: {
                    Text("Diagnostics")
                } footer: {
                    if let expiresAt = telemetry.verboseExpiresAt, telemetry.isVerboseEnabled {
                        Text(
                            "Verbose logging captures debug logs and SQL statements. It turns off automatically at \(expiresAt, format: ClinicDate.formatStyle.day().month().hour().minute())."
                        )
                    }
                }
                TimelineTuningSettings()
            }
            .onAppear {
                telemetry.refreshState()
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .trayOptions(size: .full)
    }
}

/// Shows the Settings button in the trailing toolbar only when backups need attention.
struct BackupWarningToolbar: ToolbarContent {
    @Environment(BackupCoordinator.self) private var backups
    var showsTrailingSpacer = false

    var body: some ToolbarContent {
        if backups.needsAttention {
            ToolbarItem(placement: .topBarTrailing) {
                BackupSettingsButton()
            }
            if showsTrailingSpacer {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
        }
    }
}

private struct BackupSettingsButton: View {
    @Environment(Router.self) private var router

    var body: some View {
        Button("Settings", systemImage: "gearshape") { router.requestSettings() }
            .badge(Text("!"))
            .disabled(router.activePresentation != nil)
    }
}

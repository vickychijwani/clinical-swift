import ClinicalModels
import SwiftUI

struct DiagnosticsSettingsSection: View {
    @Environment(TelemetryCoordinator.self) private var telemetry

    var body: some View {
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
        .onAppear {
            telemetry.refreshState()
        }
    }
}

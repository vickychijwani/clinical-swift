import SwiftUI

struct SettingsView: View {
    @Environment(\.trayDismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                BackupSettingsSections()
                DiagnosticsSettingsSection()
                TimelineTuningSettings()
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

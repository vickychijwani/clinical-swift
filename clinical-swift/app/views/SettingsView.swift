import SwiftUI

struct SettingsView: View {
    @Environment(\.trayDismiss) private var dismiss
    @AppStorage(DayCapacitySettings.showIndicatorsKey) private var showDayCapacityIndicators = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Schedule") {
                    Toggle("Day indicators", isOn: $showDayCapacityIndicators)
                }
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

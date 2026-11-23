import SwiftUI

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

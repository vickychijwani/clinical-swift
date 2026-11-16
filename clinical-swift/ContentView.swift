import SQLiteData
import SwiftUI

struct ContentView: View {
    @Bindable var router: Router
    @State private var editor: ScheduleEditorStore

    init(router: Router, initialEditorSession: ScheduleEditorSession? = nil) {
        self.router = router
        _editor = State(initialValue: ScheduleEditorStore(session: initialEditorSession))
    }

    var body: some View {
        AppTabs(router: router)
            .modifier(AppTrayHost())
            .environment(router)
            .environment(editor)
            .task(id: router.unavailableTimeNavigationRequest?.id) {
                guard let request = router.unavailableTimeNavigationRequest else { return }
                await router.resolveUnavailableTime(request)
            }
            .alert(
                "Unavailable Time",
                isPresented: Binding(
                    get: { router.navigationErrorMessage != nil },
                    set: { if !$0 { router.navigationErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { router.navigationErrorMessage = nil }
            } message: {
                Text(router.navigationErrorMessage ?? "")
            }
            .onOpenURL { url in
                router.open(url)
            }
            .timelineTuningRoot()
            .colorLabRoot()
    }

}

private struct AppTabs: View {
    @Bindable var router: Router

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                NavigationStack(path: $router.schedulePath) {
                    ScheduleView()
                }
            }

            Tab("Patients", systemImage: "person.2", value: AppTab.patients) {
                NavigationStack(path: $router.patientsPath) {
                    PatientsView()
                }
            }

            Tab("Payments", systemImage: "indianrupeesign", value: AppTab.payments) {
                NavigationStack(path: $router.paymentsPath) {
                    PaymentsView()
                }
            }
        }
    }
}

#Preview {
    let database = try! prepareDependencies {
        let database = try appDatabase(seedSamples: true)
        $0.defaultDatabase = database
        return database
    }
    ContentView(router: Router())
        .environment(
            BackupCoordinator(
                database: database,
                store: BackupStateStore(
                    directory: .temporaryDirectory.appending(path: UUID().uuidString))))
}

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

private enum AppTrayItem: Identifiable {
    case details(DetailsPresentation)
    case patientEdit(PatientEditRequest)
    case appointmentMessage(AppointmentMessageRequest)
    case settings(SettingsRequest)
    case scheduleEditor(ScheduleEditorSession)

    nonisolated var id: UUID {
        switch self {
        case .details(let presentation): presentation.id
        case .patientEdit(let request): request.id
        case .appointmentMessage(let request): request.id
        case .settings(let request): request.id
        case .scheduleEditor(let session): session.id
        }
    }
}

private struct AppTrayHost: ViewModifier {
    @Environment(Router.self) private var router
    @Environment(ScheduleEditorStore.self) private var editor

    func body(content: Content) -> some View {
        content.tray(
            item: Binding(
                // These values are projections of Router.activePresentation, not independent sheet state.
                // Route dismissal through the router to preserve a replacement during the tray's exit.
                get: { trayItem },
                set: { value in
                    guard value == nil, let current = trayItem else { return }
                    switch current {
                    case .scheduleEditor(let session): session.isShowingSheet = false
                    default: router.dismissPresentation()
                    }
                }),
            didAppear: router.presentationDidAppear,
            didDismiss: { id in
                router.presentationDidDismiss(id, retainingScheduleEditor: editor.session?.id)
            }
        ) { item in
            switch item {
            case .scheduleEditor(let session):
                ScheduleEditorSheet(session: session)
            case .details(let details):
                DetailsFlowView(presentation: details)
                    .id(details.visitID)
            case .patientEdit(let request):
                EditPatientView(patient: request.patient)
            case .appointmentMessage(let request):
                AppointmentMessageView(id: request.appointmentID)
            case .settings:
                BackupSettingsView()
            }
        }
    }

    private var trayItem: AppTrayItem? {
        guard let presentation = router.activePresentation else { return nil }
        switch presentation {
        case .scheduleCreation, .appointmentBooking, .appointmentEdit, .unavailableTimeEditor:
            guard let session = editor.session, session.id == presentation.id,
                session.isShowingSheet
            else { return nil }
            return .scheduleEditor(session)
        case .details(let details):
            return .details(details)
        case .patientEdit(let request):
            return .patientEdit(request)
        case .appointmentMessage(let request):
            return .appointmentMessage(request)
        case .settings(let request):
            return .settings(request)
        }
    }
}

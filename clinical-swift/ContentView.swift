import SQLiteData
import SwiftUI
import UIKit

struct ContentView: View {
    @Bindable var router: Router
    @State private var editor: ScheduleEditorStore

    init(
        router: Router,
        initialEditorSession: ScheduleEditorSession? = nil,
        initialToast: ToastItem? = nil
    ) {
        self.router = router
        _editor = State(initialValue: ScheduleEditorStore(session: initialEditorSession))
        #if DEBUG
            let resolvedToast =
                initialToast
                ?? (CommandLine.arguments.contains("--preview-toast")
                    ? ToastItem(
                        message: "Completed",
                        actionTitle: "Book follow-up",
                        duration: nil
                    ) {}
                    : nil)
            if let resolvedToast, router.toast.current == nil {
                router.toast.show(resolvedToast)
            }
        #else
            if let initialToast, router.toast.current == nil {
                router.toast.show(initialToast)
            }
        #endif
    }

    var body: some View {
        AppTabs(router: router)
            .modifier(AppTrayHost())
            .environment(router)
            .environment(editor)
            .environment(router.toast)
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
            .onShake {
                router.requestSettings()
            }
            .timelineTuningRoot()
            .colorLabRoot()
    }

}

private struct AppTabs: View {
    @Bindable var router: Router
    @Environment(ScheduleEditorStore.self) private var editor
    @Environment(ToastStore.self) private var toast

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
        .toastOverlay(toast, bottomClearance: editor.session == nil ? 64 : 16)
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

#Preview("Toast active") {
    let database = try! prepareDependencies {
        let database = try appDatabase(seedSamples: true)
        $0.defaultDatabase = database
        return database
    }
    ContentView(
        router: Router(),
        initialToast: ToastItem(
            message: "Appointment completed",
            actionTitle: "View",
            duration: nil
        ) {}
    )
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

extension Notification.Name {
    nonisolated static let deviceDidShake = Notification.Name("clinical.deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: self)
        }
        super.motionEnded(motion, with: event)
    }
}

extension View {
    fileprivate func onShake(perform action: @escaping @MainActor () -> Void) -> some View {
        modifier(ShakeDetectorModifier(action: action))
    }
}

private struct ShakeDetectorModifier: ViewModifier {
    let action: @MainActor () -> Void
    @State private var windowBox = WeakWindowBox()

    func body(content: Content) -> some View {
        content
            .background(WindowObserver(windowBox: windowBox))
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { notification in
                // Ignore shakes from separate alert or system windows.
                guard let window = notification.object as? UIWindow, window === windowBox.window
                else { return }
                action()
            }
            .uiTestShakeBridge(windowBox: windowBox)
    }
}

extension View {
    @ViewBuilder
    fileprivate func uiTestShakeBridge(windowBox: WeakWindowBox) -> some View {
        #if DEBUG
            if CommandLine.arguments.contains(where: { $0.hasPrefix("--ui-testing-") }) {
                modifier(UITestShakeBridgeModifier(windowBox: windowBox))
            } else {
                self
            }
        #else
            self
        #endif
    }
}

#if DEBUG
    private struct UITestShakeBridgeModifier: ViewModifier {
        let windowBox: WeakWindowBox

        func body(content: Content) -> some View {
            content
                .onAppear {
                    UITestShakeHook.installIfNeeded()
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: UITestShakeHook.localNotificationName)
                ) { _ in
                    windowBox.window?.motionEnded(.motionShake, with: nil)
                }
        }
    }

    private enum UITestShakeHook {
        private static let darwinNotificationName =
            "in.bitehaus.clinical.ui-testing.shake" as CFString
        nonisolated static let localNotificationName = Notification.Name(
            "clinical.uiTestingSimulateShake")

        static func installIfNeeded() {
            _ = registration
        }

        private static let registration: Void = {
            // XCUITest has no shake API, so UI tests trigger the real window hook via Darwin notify.
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                nil,
                { _, _, _, _, _ in
                    Task { @MainActor in
                        NotificationCenter.default.post(name: localNotificationName, object: nil)
                    }
                },
                darwinNotificationName,
                nil,
                .deliverImmediately
            )
        }()
    }
#endif

@MainActor
private final class WeakWindowBox {
    weak var window: UIWindow?
}

private struct WindowObserver: UIViewRepresentable {
    let windowBox: WeakWindowBox

    func makeUIView(context: Context) -> ObserverView {
        ObserverView(windowBox: windowBox)
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        uiView.windowBox = windowBox
        windowBox.window = uiView.window
    }

    final class ObserverView: UIView {
        var windowBox: WeakWindowBox

        init(windowBox: WeakWindowBox) {
            self.windowBox = windowBox
            super.init(frame: .zero)
            isHidden = true
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowBox.window = window
        }
    }
}

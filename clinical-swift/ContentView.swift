import ClinicalModels
import SQLiteData
import SwiftUI

struct ContentView: View {
    @Bindable var router: Router
    var initialEditorSession: ScheduleEditorSession? = nil
    @Namespace private var appointmentZoom
    @State private var presentedDetails: DetailsPresentation? = nil

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                NavigationStack(path: $router.schedulePath) {
                    ScheduleView(editorSession: initialEditorSession)
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
        .sheet(
            item: detailsPresentationBinding,
            onDismiss: {
                presentedDetails = nil
                router.presentationDidDismiss()
            }
        ) { presentation in
            DetailsFlowSheet(presentation: presentation)
                .modifier(
                    AppointmentZoomTransition(route: presentation.root, namespace: appointmentZoom)
                )
                .id(presentation.id)
                .onAppear {
                    if router.detailsPresentation?.id == presentation.id {
                        // Keep the source copy until onDismiss. The router clears its route before the zoom ends.
                        // Retain the session so an in-place root change also changes the source.
                        presentedDetails = presentation
                    }
                    router.presentationDidAppear(presentation.id)
                }
        }
        .sheet(
            item: patientEditRequestBinding,
            onDismiss: router.presentationDidDismiss
        ) { request in
            EditPatientView(patient: request.patient)
                .onAppear {
                    router.presentationDidAppear(request.id)
                }
        }
        .sheet(
            item: appointmentMessageRequestBinding,
            onDismiss: router.presentationDidDismiss
        ) { request in
            AppointmentMessageView(id: request.appointmentID)
                .onAppear {
                    router.presentationDidAppear(request.id)
                }
        }
        .environment(router)
        .environment(\.appointmentZoomNamespace, appointmentZoom)
        .environment(\.appointmentZoomSourceID, appointmentZoomID)
        .sheet(
            item: presentationBinding(get: { router.settingsRequest }),
            onDismiss: router.presentationDidDismiss
        ) { request in
            BackupSettingsView()
                .onAppear { router.presentationDidAppear(request.id) }
        }
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

    private var appointmentZoomID: Appointment.ID? {
        guard case .appointment(let id)? = (router.detailsPresentation ?? presentedDetails)?.root
        else {
            return nil
        }
        return id
    }

    private var detailsPresentationBinding: Binding<DetailsPresentation?> {
        presentationBinding(get: { router.detailsPresentation })
    }

    private var appointmentMessageRequestBinding: Binding<AppointmentMessageRequest?> {
        presentationBinding(get: { router.appointmentMessageRequest })
    }

    private var patientEditRequestBinding: Binding<PatientEditRequest?> {
        presentationBinding(get: { router.patientEditRequest })
    }

    private func presentationBinding<Value: Identifiable>(
        get: @escaping @MainActor @Sendable () -> Value?
    ) -> Binding<Value?> {
        // These values are projections of Router.activePresentation, not independent sheet state.
        // Route a sheet's nil write-back through the router so it can distinguish user dismissal
        // from an in-progress replacement and preserve the single-presentation invariant.
        Binding(
            get: get,
            set: { newValue in
                guard newValue == nil else { return }
                router.dismissPresentation()
            }
        )
    }
}

extension EnvironmentValues {
    @Entry var appointmentZoomNamespace: Namespace.ID? = nil
    @Entry var appointmentZoomSourceID: Appointment.ID? = nil
}

private struct AppointmentZoomTransition: ViewModifier {
    let route: Route
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if case .appointment(let id) = route {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
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

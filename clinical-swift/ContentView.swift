import SQLiteData
import SwiftUI

struct ContentView: View {
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
        }
        .sheet(
            item: detailsPresentationBinding,
            onDismiss: router.presentationDidDismiss
        ) { presentation in
            DetailsFlowSheet(presentation: presentation)
                .colorLabOverlay()
                .id(presentation.id)
                .onAppear {
                    router.presentationDidAppear(presentation.id)
                }
        }
        .sheet(
            item: patientEditRequestBinding,
            onDismiss: router.presentationDidDismiss
        ) { request in
            EditPatientView(patient: request.patient)
                .colorLabOverlay()
                .onAppear {
                    router.presentationDidAppear(request.id)
                }
        }
        .sheet(
            item: appointmentMessageRequestBinding,
            onDismiss: router.presentationDidDismiss
        ) { request in
            AppointmentMessageView(id: request.appointmentID)
                .colorLabOverlay()
                .onAppear {
                    router.presentationDidAppear(request.id)
                }
        }
        .environment(router)
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
        .colorLabOverlay()
        .timelineTuningRoot()
        .colorLabRoot()
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

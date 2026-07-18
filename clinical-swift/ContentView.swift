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
        .onOpenURL { url in
            router.open(url)
        }
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
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    ContentView(router: Router())
}

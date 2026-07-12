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
            item: $router.detailsPresentation,
            onDismiss: router.detailsDidDismiss
        ) { presentation in
            DetailsFlowSheet(presentation: presentation)
                .id(presentation.id)
        }
        .sheet(
            item: patientEditRequestBinding,
            onDismiss: router.patientEditorDidDismiss
        ) { request in
            EditPatientView(patient: request.patient)
        }
        .sheet(
            item: appointmentMessageRequestBinding,
            onDismiss: router.appointmentMessageDidDismiss
        ) { request in
            AppointmentMessageView(id: request.appointmentID)
        }
        .environment(router)
        .onOpenURL { url in
            router.open(url)
        }
    }

    private var appointmentMessageRequestBinding: Binding<AppointmentMessageRequest?> {
        Binding(
            get: { router.appointmentMessageRequest },
            set: { newValue in
                guard newValue == nil, let requestID = router.appointmentMessageRequest?.id else {
                    return
                }
                router.consumeAppointmentMessageRequest(requestID)
            }
        )
    }

    private var patientEditRequestBinding: Binding<PatientEditRequest?> {
        Binding(
            get: { router.patientEditRequest },
            set: { newValue in
                guard newValue == nil, let requestID = router.patientEditRequest?.id else {
                    return
                }
                router.consumePatientEditRequest(requestID)
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

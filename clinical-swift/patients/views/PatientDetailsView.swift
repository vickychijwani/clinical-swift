import SQLiteData
import SwiftUI

struct PatientDetailsView: View {
    @Environment(Router.self) private var router

    @FetchOne private var row: PatientListRow?
    @FetchAll private var appointmentRows: [PatientTimelineAppointmentRow]

    let onSelectAppointment: @MainActor @Sendable (Appointment.ID) -> Void

    init(
        id: Patient.ID,
        onSelectAppointment: @escaping @MainActor @Sendable (Appointment.ID) -> Void
    ) {
        _row = FetchOne(patientDetailsQuery(id: id))
        _appointmentRows = FetchAll(
            patientTimelineAppointmentsQuery(patientID: id),
            animation: .default
        )
        self.onSelectAppointment = onSelectAppointment
    }

    var body: some View {
        Group {
            if let details = row?.item {
                ViewPatientView(
                    details: details,
                    appointmentRows: appointmentRows,
                    onSelectAppointment: onSelectAppointment
                )
            } else {
                ContentUnavailableView(
                    "Patient Unavailable",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("This patient no longer exists.")
                )
                .navigationTitle("Patient Details")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let patient = row?.item.patient {
                    Button("Edit Patient", systemImage: "pencil") {
                        router.requestPatientEdit(patient)
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    NavigationStack {
        PatientDetailsView(id: samplePatients[0].id) { _ in }
    }
    .environment(Router())
}

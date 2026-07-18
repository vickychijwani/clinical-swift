import SQLiteData
import SwiftUI

struct PatientDetailsView: View {
    @Environment(Router.self) private var router
    @FetchOne private var row: PatientDetailsSelection?
    @FetchAll private var appointmentRecords: [AppointmentRecord]
    @State private var isPatientNameVisible = true

    let onSelectAppointment: @MainActor @Sendable (Appointment.ID) -> Void

    init(
        id: Patient.ID,
        onSelectAppointment: @escaping @MainActor @Sendable (Appointment.ID) -> Void
    ) {
        _row = FetchOne(patientDetailsQuery(id: id))
        _appointmentRecords = FetchAll(
            patientTimelineAppointmentsQuery(patientID: id),
            animation: .default
        )
        self.onSelectAppointment = onSelectAppointment
    }

    var body: some View {
        Group {
            if let details = row?.details {
                ViewPatientView(
                    details: details,
                    appointments: appointmentRecords.compactMap {
                        $0.appointment(patientName: details.patient.displayName)
                    },
                    onNameVisibilityChange: { isPatientNameVisible = $0 },
                    onSelectAppointment: onSelectAppointment
                )
            } else {
                ContentUnavailableView(
                    "Patient Unavailable",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("This patient no longer exists.")
                )
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let patient = row?.details.patient {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit Patient", systemImage: "pencil") {
                        router.requestPatientEdit(patient)
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
    }

    private var navigationTitle: String {
        guard let patient = row?.details.patient else { return "Patient Details" }
        return PatientDetailsNavigationTitle.text(
            patientDisplayName: patient.displayName,
            isNameVisible: isPatientNameVisible
        )
    }
}

nonisolated enum PatientDetailsNavigationTitle {
    // Display patient name in nav title when the name field is almost entirely off-screen (1% visible)
    static let nameVisibilityThreshold = 0.01

    static func text(patientDisplayName: String, isNameVisible: Bool) -> String {
        isNameVisible ? "Patient Details" : patientDisplayName
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

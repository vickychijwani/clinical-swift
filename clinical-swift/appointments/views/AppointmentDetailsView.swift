import SQLiteData
import SwiftUI

struct AppointmentDetailsView: View {
    @Environment(Router.self) private var router

    @FetchOne private var row: ScheduleAppointmentRow?

    let onSelectPatient: @MainActor @Sendable (Patient.ID) -> Void

    init(
        id: Appointment.ID,
        onSelectPatient: @escaping @MainActor @Sendable (Patient.ID) -> Void
    ) {
        _row = FetchOne(appointmentDetailsQuery(id: id))
        self.onSelectPatient = onSelectPatient
    }

    var body: some View {
        Group {
            if let details = row?.details {
                ScrollView {
                    AppointmentDetailsCard(
                        appointment: details.appointment,
                        variant: .standard(
                            patient: details.patient,
                            onSelectPatient: {
                                onSelectPatient(details.patient.id)
                            }
                        )
                    )
                    .padding()
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                ContentUnavailableView(
                    "Appointment Unavailable",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("This appointment no longer exists.")
                )
            }
        }
        .navigationTitle("Appointment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let appointment = row?.appointment,
                    appointment.status == .scheduled
                {
                    Button("Edit Appointment", systemImage: "pencil") {
                        router.requestAppointmentEdit(appointment.id)
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
        AppointmentDetailsView(id: sampleAppointments[0].id) { _ in }
    }
    .environment(Router())
}

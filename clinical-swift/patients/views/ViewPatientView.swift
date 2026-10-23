import ClinicalModels
import SwiftUI

struct ViewPatientView: View {
    @Environment(Router.self) private var router

    let details: PatientDetails
    let appointments: [Appointment]
    let onNameVisibilityChange: @MainActor @Sendable (Bool) -> Void
    let onSelectAppointment: @MainActor @Sendable (Appointment.ID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                PatientSummaryView(
                    item: details,
                    onNameVisibilityChange: onNameVisibilityChange
                )
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color.white)
                .clipShape(.rect(cornerRadius: 32))

                PatientActionsView(scheduleAppointment: scheduleAppointment)

                Text("Appointments")
                    .font(.headline)

                if appointments.isEmpty {
                    Text("No appointments yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appointments) { appointment in
                        AppointmentDetailsCard(
                            appointment: appointment,
                            variant: .patientTimeline(
                                onSelectAppointment: {
                                    onSelectAppointment(appointment.id)
                                }
                            )
                        )
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("AppBackground"))
    }

    private func scheduleAppointment() {
        router.requestAppointmentBooking(for: details.patient)
    }
}

private struct PatientActionsView: View {
    let scheduleAppointment: () -> Void

    var body: some View {
        GlassEffectContainer {
            Button {
                scheduleAppointment()
            } label: {
                Label("Schedule Appointment", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
    }
}

#Preview {
    Text("")
        .sheet(
            item: .constant(
                PatientDetails(
                    patient: Patient(
                        id: UUID(),
                        name: "Dev Malhotra",
                        phone: "+123",
                        dob: .now.date(byAddingWeeks: -1000),
                        gender: .male
                    ),
                    nextAppointmentDate: nil
                )
            )
        ) { item in
            NavigationStack {
                ViewPatientView(
                    details: item,
                    appointments: [],
                    onNameVisibilityChange: { _ in },
                    onSelectAppointment: { _ in }
                )
            }
            .environment(Router())
            .presentationDetents([.medium, .large])
        }
}

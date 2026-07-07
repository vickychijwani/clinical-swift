import SwiftUI

struct ViewPatientView: View {
    @Environment(Router.self) private var router
    @State private var isPatientNameVisible = true

    let details: PatientDetails
    let appointments: [Appointment]
    let onSelectAppointment: @MainActor @Sendable (Appointment.ID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                PatientSummaryView(
                    item: details,
                    onNameVisibilityChange: { isPatientNameVisible in
                        self.isPatientNameVisible = isPatientNameVisible
                    }
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
        .navigationTitle(
            PatientDetailsNavigationTitle.text(
                patientDisplayName: details.patient.displayName,
                isNameVisible: isPatientNameVisible
            )
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit Patient", systemImage: "pencil", action: editPatient)
                    .labelStyle(.iconOnly)
            }
        }
    }

    private func scheduleAppointment() {
        router.requestAppointmentBooking(for: details.patient)
    }

    private func editPatient() {
        router.requestPatientEdit(details.patient)
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

nonisolated enum PatientDetailsNavigationTitle {
    // Display patient name in nav title when the name field is almost entirely off-screen (1% visible)
    static let nameVisibilityThreshold = 0.01

    static func text(patientDisplayName: String, isNameVisible: Bool) -> String {
        isNameVisible ? "Patient Details" : patientDisplayName
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
                    onSelectAppointment: { _ in }
                )
            }
            .environment(Router())
            .presentationDetents([.medium, .large])
        }
}

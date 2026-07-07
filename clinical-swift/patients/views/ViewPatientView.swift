import SwiftUI

struct ViewPatientView: View {
    @Environment(\.openURL) private var openURL
    @State private var isPatientNameVisible = true

    let details: PatientDetails
    let appointmentRows: [PatientTimelineAppointmentRow]
    let onSelectAppointment: @MainActor @Sendable (Appointment.ID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                PatientItemView(
                    item: details,
                    onNameVisibilityChange: { isPatientNameVisible in
                        self.isPatientNameVisible = isPatientNameVisible
                    }
                )
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color.white)
                .clipShape(.rect(cornerRadius: 8))

                HStack(spacing: 12) {
                    Button {
                        callPatient()
                    } label: {
                        Label("Call", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(telURL == nil)

                    Button {
                        openWhatsAppChat()
                    } label: {
                        Label("WhatsApp", systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(whatsappURL == nil)
                }

                Text("Appointments")
                    .font(.headline)

                if appointmentRows.isEmpty {
                    Text("No appointments yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appointmentRows) { row in
                        if let appointment = row.appointment(
                            patientName: details.patient.displayName
                        ) {
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
    }

    private var normalizedPhoneNumber: String? {
        PhoneNumber.normalizedE164(details.patient.phone)
    }

    private var whatsappPhoneNumber: String? {
        normalizedPhoneNumber?.filter(\.isNumber)
    }

    private var telURL: URL? {
        guard let normalizedPhoneNumber else { return nil }
        return URL(string: "tel://\(normalizedPhoneNumber)")
    }

    private var whatsappURL: URL? {
        guard let whatsappPhoneNumber else { return nil }
        return URL(string: "https://wa.me/\(whatsappPhoneNumber)")
    }

    private func callPatient() {
        guard let telURL else { return }
        openURL(telURL)
    }

    private func openWhatsAppChat() {
        guard let whatsappURL else { return }
        openURL(whatsappURL)
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
                    appointmentRows: [],
                    onSelectAppointment: { _ in }
                )
            }
            .presentationDetents([.medium, .large])
        }
}

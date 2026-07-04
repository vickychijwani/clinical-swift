import SwiftUI

struct ViewPatientView: View {
    @Environment(\.openURL) private var openURL

    let details: PatientDetails

    var body: some View {
        VStack(spacing: 12) {
            PatientItemView(item: details)
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .background(Color("AppBackground"))
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
                ViewPatientView(details: item)
            }
            .presentationDetents([.medium, .large])
        }
}

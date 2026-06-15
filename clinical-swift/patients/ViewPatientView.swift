import SwiftUI
import UIKit

struct ViewPatientView: View {
    let details: PatientDetails

    var body: some View {
        VStack(spacing: 12) {
            PatientRow(item: patientListItem)
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
        .navigationTitle("Patient Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    var patientListItem: PatientListItem {
        PatientListItem(
            patient: details.patient,
            nextAppointmentDate: details.nextAppointmentDate
        )
    }

    var phoneNumber: String? {
        details.patient.phone
    }

    var telURL: URL? {
        guard let phoneNumber else { return nil }

        let allowedCharacters = CharacterSet(charactersIn: "+0123456789")
        let sanitizedPhoneNumber = phoneNumber
            .unicodeScalars
            .filter { allowedCharacters.contains($0) }
            .map(String.init)
            .joined()

        guard !sanitizedPhoneNumber.isEmpty else { return nil }

        return URL(string: "tel://\(sanitizedPhoneNumber)")
    }

    var whatsappURL: URL? {
        guard let phoneNumber else { return nil }

        let sanitizedPhoneNumber = phoneNumber
            .filter(\.isNumber)

        guard !sanitizedPhoneNumber.isEmpty else { return nil }

        return URL(string: "https://wa.me/\(sanitizedPhoneNumber)")
    }

    func callPatient() {
        guard let telURL else { return }

        UIApplication.shared.open(telURL)
    }

    func openWhatsAppChat() {
        guard let whatsappURL else { return }

        UIApplication.shared.open(whatsappURL)
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
        ) { details in
            NavigationStack {
                ViewPatientView(details: details)
                    .background(Color("AppBackground"))
            }
            .presentationDetents([.medium, .large])
        }
}

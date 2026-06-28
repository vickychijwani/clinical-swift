import SwiftUI

struct AppointmentDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let details: AppointmentDetails

    @State private var selectedDetent: PresentationDetent = .medium

    var body: some View {
        ScrollView {
            AppointmentDetailsCard(
                appointment: details.appointment,
                variant: .standard(patient: details.patient)
            )
            .padding()
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Appointment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
            }
        }
        .presentationDetents([.height(220), .medium, .large], selection: $selectedDetent)
        .presentationBackground(Color("AppBackground"))
        .presentationContentInteraction(.resizes)
    }
}

#Preview {
    let patient = Patient(
        name: "Aarav Mehta",
        dob: Date(timeIntervalSinceReferenceDate: -410_313_600),
        gender: .male
    )
    let appointment = Appointment(
        patientName: patient.displayName,
        start: Date(timeIntervalSinceReferenceDate: 798_208_200),
        durationMinutes: 30,
        status: .scheduled
    )

    AppointmentDetailsSheet(
        details: AppointmentDetails(
            appointment: appointment,
            patient: patient
        )
    )
}

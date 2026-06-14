import SwiftUI

struct PatientAvatar: View {
    let patient: Patient

    var body: some View {
        Text(initials)
            .font(.headline.pointSize(13))
            .bold()
            .foregroundStyle(.green)
            .frame(width: 34, height: 34)
            .background(.green.opacity(0.16))
            .clipShape(.circle)
            .accessibilityHidden(true)
    }

    private var initials: String {
        guard let name = patient.name else {
            return "?"
        }

        let parts = name.split(separator: " ")
        let initialCharacters = parts.compactMap(\.first).prefix(2)
        let value = String(initialCharacters).uppercased()

        return value.isEmpty ? "?" : value
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    PatientAvatar(patient: samplePatients[1])
        .padding()
}

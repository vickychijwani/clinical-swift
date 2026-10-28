import SwiftUI

struct PatientSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.icon)

            TextField("Name", text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    text = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(AppColor.icon)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(AppColor.surface)
        .clipShape(.rect(cornerRadius: 18))
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    @Previewable @State var searchText = ""

    PatientSearchField(text: $searchText)
        .padding()
        .background(AppColor.canvas)
}

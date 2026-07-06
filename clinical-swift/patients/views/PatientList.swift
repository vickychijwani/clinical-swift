import SwiftUI

struct PatientList: View {
    let sections: [PatientSection]
    let onSelectPatient: (Patient.ID) -> Void

    @Binding var searchText: String

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        Button {
                            onSelectPatient(item.id)
                        } label: {
                            PatientItemView(item: item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(
                            EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
                        )
                    }
                } header: {
                    Text(section.id)
                }
                .sectionIndexLabel(section.id)
            }
        }
        .searchable(text: $searchText)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    PatientList(
        sections: PatientSection.sections(from: samplePatientDetails),
        onSelectPatient: { _ in },
        searchText: .constant("")
    )
    .background(Color("AppBackground"))
}

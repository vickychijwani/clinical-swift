import SwiftUI

struct PatientList: View {
    let sections: [PatientSection]

    @Binding var searchText: String
    @Binding var viewingPatient: PatientDetails?

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        PatientItemView(item: item)
                            .listRowInsets(
                                EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
                            )
                            .onTapGesture {
                                viewingPatient = item
                            }
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
        searchText: .constant(""),
        viewingPatient: .constant(nil)
    )
    .background(Color("AppBackground"))
}

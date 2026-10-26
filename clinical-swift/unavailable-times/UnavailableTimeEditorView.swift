import SwiftUI

struct UnavailableTimeEditorView: View {
    @Bindable var model: UnavailableTimeEditorModel
    @FocusState private var labelIsFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                ScheduleEditorSection(title: "Label") {
                    TextField("Optional label", text: $model.draft.label)
                        .focused($labelIsFocused)
                        .submitLabel(.continue)
                        .onSubmit { model.finishLabelEntry() }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color("AppBackground"))
            .navigationTitle("Unavailable Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.left") {
                        model.finishLabelEntry()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", systemImage: "checkmark") {
                        model.finishLabelEntry()
                    }
                }
            }
            .disabled(model.isWorking)
            .task { labelIsFocused = true }
        }
        .interactiveDismissDisabled()
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color("AppBackground"))
        .presentationBackgroundInteraction(.disabled)
    }
}

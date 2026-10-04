import SwiftUI

struct UnavailableTimeEditorView: View {
    @Bindable var model: UnavailableTimeEditorModel

    var body: some View {
        NavigationStack {
            ConfirmingFormSheet(
                hasUnsavedChanges: model.hasUnsavedChanges,
                title: "Discard unsaved unavailable time?",
                message: "Your unavailable time has not been saved.",
                allowsInteractiveDismiss: false
            ) { guardedDismiss in
                UnavailableTimeEditorForm(model: model, guardedDismiss: guardedDismiss)
            }
        }
        .modifier(FittedSheetModifier(fitsVertically: true))
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color("AppBackground"))
        .presentationBackgroundInteraction(.enabled)
    }
}

private struct UnavailableTimeEditorForm: View {
    @Bindable var model: UnavailableTimeEditorModel
    let guardedDismiss: FormSheetDismissAction

    var body: some View {
        VStack(alignment: .leading) {
            ScheduleEditorSection(title: "Label") {
                TextField("Optional label", text: $model.draft.label)
            }
            ScheduleTimeSection(
                start: Binding(
                    get: { model.draft.start }, set: { model.selectStart($0) }
                ))
            ScheduleDurationSection(
                durationMinutes: Binding(
                    get: { model.draft.durationMinutes }, set: { model.selectDuration($0) }
                ))
            if model.purpose.editedID != nil {
                ConfirmingAsyncButton(
                    "Delete Unavailable Time", role: .destructive,
                    message: Text("Delete this unavailable time?")
                ) {
                    await model.delete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .padding()
        .disabled(model.isWorking)
        .fittedSheetContent()
        .navigationTitle(model.purpose.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                FormSheetCancelButton(action: guardedDismiss)
                    .disabled(model.isWorking)
            }
            ToolbarItem(placement: .confirmationAction) {
                AsyncButton("Done", systemImage: "checkmark") {
                    await model.save()
                }
                .labelStyle(.iconOnly)
                .disabled(model.isWorking)
            }
        }
        .alert(
            "Unable to change unavailable time",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

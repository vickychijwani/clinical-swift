import ClinicalModels
import SwiftUI

struct PaymentEntryForm: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = PaymentEntryModel()
    @FocusState private var focusedField: Field?

    private enum Field { case note, amount }

    var body: some View {
        VStack {
            Picker(
                "Kind",
                selection: Binding(get: { model.kind }, set: { model.selectKind($0) })
            ) {
                ForEach(PaymentEntryModel.Kind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(
                model.kind.placeholder,
                text: Binding(get: { model.note }, set: { model.setNote($0) })
            )
            .font(.subheadline)
            .textFieldStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(AppColor.surface, in: .capsule)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .note)
            .submitLabel(.next)
            .onSubmit {
                model.finishNote()
                if model.kind != .patient || model.patient != nil { focusedField = .amount }
            }

            if focusedField == .note && (model.kind == .patient || !model.matchingLabels.isEmpty) {
                PaymentEntrySuggestions(model: model) { focusedField = .amount }
            }

            HStack {
                HStack {
                    Text("₹")
                        .foregroundStyle(AppColor.secondaryText)
                    TextField("Amount", text: $model.amountText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .amount)
                }
                .font(.body)
                .controlSize(.small)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.surface, in: .capsule)

                AsyncButton {
                    if await model.save() { focusedField = nil }
                } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .contentShape(.rect)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .disabled(!model.canAdd)
            }
            // The amount surface takes the button's height, including its native glass insets.
            .fixedSize(horizontal: false, vertical: true)

            PaymentMethodPicker(selection: $model.method)
        }
        .controlSize(.mini)
        .frame(maxWidth: .infinity)
        .disabled(model.isSaving)
        .onChange(of: focusedField) { oldValue, _ in
            if oldValue == .note { model.finishNote() }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await model.loadPatients() }
        }
        .alert(
            "Unable to add payment",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct PaymentEntrySuggestions: View {
    let model: PaymentEntryModel
    let didSelect: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                if model.kind == .patient {
                    ForEach(model.patients) { patient in
                        Button {
                            model.selectPatient(patient)
                            didSelect()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(patient.displayName)
                                if let phone = patient.phone {
                                    Text(phone)
                                        .font(.caption)
                                        .foregroundStyle(AppColor.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(.rect)
                        }
                    }
                    if model.patients.isEmpty {
                        Text("No matching patients")
                            .foregroundStyle(AppColor.secondaryText)
                    }
                } else {
                    ForEach(model.matchingLabels, id: \.self) { label in
                        Button {
                            model.selectLabel(label)
                            didSelect()
                        } label: {
                            Text(label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .contentShape(.rect)
                        }
                    }
                }
            }
            .font(.subheadline)
            .buttonStyle(.plain)
        }
        .frame(maxHeight: 180)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

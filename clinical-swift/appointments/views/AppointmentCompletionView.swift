import ClinicalModels
import SwiftUI

struct AppointmentCompletionView: View {
    @Environment(Router.self) private var router
    @Bindable var model: AppointmentCompletionModel
    let presentationID: UUID
    @FocusState private var amountIsFocused: Bool
    @State private var amountText: String

    init(model: AppointmentCompletionModel, presentationID: UUID) {
        self.model = model
        self.presentationID = presentationID
        _amountText = State(initialValue: model.amountText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Amount paid")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal)
                    HStack {
                        Text("₹")
                        TextField(
                            "Amount paid",
                            text: $amountText,
                            prompt: Text("0")
                        )
                        .keyboardType(.numberPad)
                        .focused($amountIsFocused)
                        .accessibilityIdentifier("completion-amount")
                    }
                    .padding()
                    .background(AppColor.surface)
                    .clipShape(.capsule)
                    if model.amount == nil {
                        Text("Enter a valid whole-rupee amount.")
                            .foregroundStyle(.red)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Payment method")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal)
                    PaymentMethodPicker(
                        selection: Binding(
                            get: { model.paymentMethod }, set: { model.selectMethod($0) })
                    )
                    .accessibilityIdentifier("completion-method")
                }
                GlassEffectContainer {
                    AsyncButton {
                        if await model.save() {
                            router.finishAppointmentCompletion(
                                model, presentationID: presentationID)
                        }
                    } label: {
                        Label {
                            Text(model.buttonTitle)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .accessibilityIdentifier("completion-action-title")
                        } icon: {
                            Image(systemName: model.buttonSymbol)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.appGlassProminent)
                    .controlSize(.regular)
                    .labelStyle(.titleAndIcon)
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("complete-appointment")
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.canvas)
        .disabled(model.isSaving || model.didSave)
        #if DEBUG
            .overlay(alignment: .topTrailing) {
                if AppointmentCompletionUITestData.saveGate.isWaiting {
                    Button("Finish test save") {
                        AppointmentCompletionUITestData.saveGate.release()
                    }
                    .accessibilityIdentifier("release-test-save")
                }
            }
        #endif
        .navigationTitle("Complete Appointment")
        .navigationSubtitle("For \(model.patientName)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isSaving)
        .task {
            // Let the tray finish its initial layout pass before requesting the keyboard.
            await Task.yield()
            guard !Task.isCancelled else { return }
            amountIsFocused = true
        }
        .onChange(of: amountText) {
            model.setAmountText(amountText)
            if amountText != model.amountText { amountText = model.amountText }
        }
        .alert(
            "Unable to complete appointment",
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

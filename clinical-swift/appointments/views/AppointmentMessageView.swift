import ClinicalModels
import MessageUI
import SQLiteData
import SwiftUI

struct AppointmentMessageView: View {
    static let traySize = TraySize.height(560)
    @Environment(\.trayDismiss) private var dismiss

    @State private var detailsModel: AppointmentMessageDetailsModel

    init(id: Appointment.ID) {
        _detailsModel = State(initialValue: AppointmentMessageDetailsModel(appointmentID: id))
    }

    var body: some View {
        NavigationStack {
            Group {
                if detailsModel.isLoading {
                    ProgressView()
                } else if let model = detailsModel.messageModel {
                    AppointmentMessageComposeView(model: model) { request in
                        if await model.openWhatsApp(request) {
                            dismiss()
                        }
                    }
                } else if let errorMessage = detailsModel.errorMessage {
                    ContentUnavailableView(
                        "Messaging Unavailable",
                        systemImage: "message.badge.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if detailsModel.details == nil {
                    ContentUnavailableView(
                        "Appointment Unavailable",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("This appointment no longer exists.")
                    )
                }
            }
            .navigationTitle("Send Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .task(id: detailsModel.appointmentID) {
                await detailsModel.load()
            }
        }
        .trayOptions(size: Self.traySize, allowsInteractiveDismiss: false, showsIndicator: false)
    }
}

private struct AppointmentMessageComposeView: View {
    @Environment(ToastStore.self) private var toast: ToastStore?
    @Bindable var model: AppointmentMessageModel
    @State private var isPickingRecipient = false
    @State private var pendingWhatsAppRequest: AppointmentWhatsAppRequest?

    let onSMSWasSent: @MainActor (_ request: AppointmentWhatsAppRequest) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Message Type", selection: $model.kind) {
                ForEach(AppointmentMessageKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $model.message)
                .frame(minHeight: 220)
                .padding(8)
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(AppColor.destructive)
            }

            HStack(spacing: 4) {
                Text("Sending to")

                Button {
                    isPickingRecipient = true
                } label: {
                    Label(model.recipientLabel, systemImage: model.recipientSystemImage)
                        .labelIconToTitleSpacing(4)
                        .dottedUnderline()
                        .foregroundStyle(AppColor.accent)
                }
                .buttonStyle(.plain)
                .disabled(model.isSavingRecipient)
            }
            .foregroundStyle(AppColor.secondaryText)
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            AsyncButton {
                model.startSend()
            } label: {
                Label("Send", systemImage: "arrow.up.message")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appGlassProminent)
            .disabled(!model.hasValidRecipientPhone || model.isSavingRecipient)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.canvas)
        .task {
            await model.loadRecipientName()
        }
        .sheet(isPresented: $isPickingRecipient) {
            ContactPhonePicker { phone, contactName in
                Task {
                    switch await model.selectRecipient(phone: phone, name: contactName) {
                    case .saved:
                        toast?.show(message: "Patient contact number saved")
                    case .unchanged:
                        break
                    case .invalidPhone:
                        toast?.show(message: "Invalid phone number")
                    case .failed:
                        toast?.show(message: "Save failed")
                    }
                }
                // No need to set isPickingRecipient to false, dismissal is automatic
            }
            .ignoresSafeArea()
        }
        .sheet(
            item: $model.smsDraft,
            onDismiss: {
                guard let request = pendingWhatsAppRequest else { return }
                pendingWhatsAppRequest = nil

                Task { @MainActor in
                    await onSMSWasSent(request)
                }
            }
        ) { draft in
            MessageComposeView(draft: draft) { result in
                pendingWhatsAppRequest = model.finishSMS(with: result)
            }
        }
    }
}

private struct MessageComposeView: UIViewControllerRepresentable {
    let draft: AppointmentSMSDraft
    let onFinish: @MainActor (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let viewController = MFMessageComposeViewController()
        viewController.messageComposeDelegate = context.coordinator
        viewController.recipients = [draft.recipient]
        viewController.body = draft.body
        return viewController
    }

    func updateUIViewController(
        _ uiViewController: MFMessageComposeViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: @MainActor (MessageComposeResult) -> Void

        init(onFinish: @escaping @MainActor (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            // SwiftUI owns the sheet presentation, so changing its bound item must dismiss it.
            Task { @MainActor in
                self.onFinish(result)
            }
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    AppointmentMessageView(id: sampleAppointments[0].id)
}

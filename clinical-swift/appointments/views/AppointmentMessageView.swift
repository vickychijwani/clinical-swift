import MessageUI
import SQLiteData
import SwiftUI

struct AppointmentMessageView: View {
    @Environment(\.dismiss) private var dismiss

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
        .interactiveDismissDisabled()
        .presentationDetents([.large])
        .presentationBackground(Color("AppBackground"))
    }
}

private struct AppointmentMessageComposeView: View {
    @Bindable var model: AppointmentMessageModel
    @State private var isPickingRecipient = false

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
                    .foregroundStyle(.red)
            }

            HStack(spacing: 4) {
                Text("Sending to")

                Button {
                    isPickingRecipient = true
                } label: {
                    Label(model.recipientLabel, systemImage: model.recipientSystemImage)
                        .labelIconToTitleSpacing(4)
                        .dottedUnderline()
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            Button(action: model.startSend) {
                Label("Send", systemImage: "arrow.up.message")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(!model.hasValidRecipientPhone)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color("AppBackground"))
        .task {
            await model.loadRecipientName()
        }
        .sheet(isPresented: $isPickingRecipient) {
            ContactPhonePicker { phone, contactName in
                model.selectRecipient(phone: phone, name: contactName)
                // No need to set isPickingRecipient to false, dismissal is automatic
            }
            .ignoresSafeArea()
        }
        .sheet(item: $model.smsDraft) { draft in
            MessageComposeView(draft: draft) { result in
                if let request = model.finishSMS(with: result) {
                    await onSMSWasSent(request)
                }
            }
        }
    }
}

private struct MessageComposeView: UIViewControllerRepresentable {
    let draft: AppointmentSMSDraft
    let onFinish: @MainActor (MessageComposeResult) async -> Void

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
        let onFinish: @MainActor (MessageComposeResult) async -> Void

        init(onFinish: @escaping @MainActor (MessageComposeResult) async -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true) {
                Task { @MainActor in
                    await self.onFinish(result)
                }
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

import SQLiteData
import SwiftUI

struct AppointmentDetailsView: View {
    @Environment(Router.self) private var router

    @State private var model: AppointmentDetailsModel

    let onSelectPatient: @MainActor @Sendable (Patient.ID) -> Void

    init(
        id: Appointment.ID,
        onSelectPatient: @escaping @MainActor @Sendable (Patient.ID) -> Void
    ) {
        _model = State(initialValue: AppointmentDetailsModel(appointmentID: id))
        self.onSelectPatient = onSelectPatient
    }

    var body: some View {
        Group {
            if let details = model.details {
                ScrollView {
                    VStack {
                        AppointmentDetailsCard(
                            appointment: details.appointment,
                            variant: .standard(
                                patient: details.patient,
                                onSelectPatient: {
                                    onSelectPatient(details.patient.id)
                                }
                            )
                        )

                        if model.showsStatusActions {
                            AppointmentStatusActionsView(
                                isUpdating: model.isUpdatingStatus,
                                onComplete: {
                                    model.requestStatus(.completed)
                                },
                                onCancel: {
                                    model.requestStatus(.cancelled)
                                }
                            )
                        }
                    }
                    .padding()
                    .fittedSheetContent()
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                ContentUnavailableView(
                    "Appointment Unavailable",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("This appointment no longer exists.")
                )
            }
        }
        .navigationTitle("Appointment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let appointment = model.details?.appointment,
                    appointment.status == .scheduled
                {
                    Button("Edit Appointment", systemImage: "pencil") {
                        router.requestAppointmentEdit(appointment.id)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(model.isUpdatingStatus)
                }
            }
        }
        .alert(
            model.prompt?.title ?? "",
            isPresented: Binding(
                get: { model.prompt != nil },
                set: { if !$0 { model.dismissPrompt() } }
            )
        ) {
            switch model.prompt {
            case .completeConfirmation:
                Button("Complete") {
                    performStatusUpdate(.completed)
                }
                Button("Not Yet", role: .cancel) {
                    model.dismissPrompt()
                }

            case .cancelConfirmation:
                Button("Cancel Appointment", role: .destructive) {
                    performStatusUpdate(.cancelled)
                }
                Button("Keep Scheduled", role: .cancel) {
                    model.dismissPrompt()
                }

            case .error:
                Button("OK", role: .cancel) {
                    model.dismissPrompt()
                }

            case nil:
                EmptyView()
            }
        } message: {
            Text(model.prompt?.message ?? "")
        }
    }

    private func performStatusUpdate(_ status: Appointment.Status) {
        Task {
            if await model.updateStatus(to: status) {
                router.dismissDetails()
            }
        }
    }
}

private struct AppointmentStatusActionsView: View {
    let isUpdating: Bool
    let onComplete: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    var body: some View {
        HStack {
            Button("Complete", systemImage: "checkmark", action: onComplete)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            Button(role: .destructive, action: onCancel) {
                Label("Cancel", systemImage: "xmark.bin")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .buttonSizing(.flexible)
        .controlSize(.mini)
        .disabled(isUpdating)
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    NavigationStack {
        AppointmentDetailsView(id: sampleAppointments[0].id) { _ in }
    }
    .environment(Router())
}

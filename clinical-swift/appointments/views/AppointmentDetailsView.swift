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
                    VStack(alignment: .leading, spacing: 12) {
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
                            AppointmentDetailsActionsView(
                                isUpdating: model.isUpdatingStatus,
                                onComplete: {
                                    model.requestStatus(.completed)
                                },
                                onReschedule: {
                                    router.requestAppointmentEdit(details)
                                },
                                onCancel: {
                                    model.requestStatus(.cancelled)
                                }
                            )
                        }
                    }
                    .padding()
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

private struct AppointmentDetailsActionsView: View {
    let isUpdating: Bool
    let onComplete: @MainActor () -> Void
    let onReschedule: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    var body: some View {
        GlassEffectContainer {
            HStack {
                Button {
                    onComplete()
                } label: {
                    Label("Complete", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                Button {
                    onReschedule()
                } label: {
                    Label(
                        "Reschedule",
                        systemImage: "clock.arrow.trianglehead.clockwise.rotate.90.path.dotted"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button(role: .destructive) {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.bin")
                }
                .buttonStyle(.glass)
            }
            .disabled(isUpdating)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

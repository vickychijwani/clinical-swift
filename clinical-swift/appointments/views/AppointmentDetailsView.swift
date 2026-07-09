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
                                    await performStatusUpdate(.completed)
                                },
                                onReschedule: {
                                    router.requestAppointmentEdit(details)
                                },
                                onCancel: {
                                    await performStatusUpdate(.cancelled)
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
            "Unable to update appointment",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func performStatusUpdate(_ status: Appointment.Status) async {
        if await model.updateStatus(to: status) {
            router.dismissDetails()
        }
    }
}

private struct AppointmentDetailsActionsView: View {
    let isUpdating: Bool
    let onComplete: @MainActor () async -> Void
    let onReschedule: @MainActor () -> Void
    let onCancel: @MainActor () async -> Void

    var body: some View {
        GlassEffectContainer {
            HStack {
                ConfirmingAsyncButton(
                    "Complete",
                    message: Text("Mark this appointment as completed?"),
                    action: onComplete
                ) {
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

                ConfirmingAsyncButton(
                    "Cancel Appointment",
                    role: .destructive,
                    message: Text(
                        "This appointment will be hidden from the schedule and appointment history."
                    ),
                    action: onCancel
                ) {
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

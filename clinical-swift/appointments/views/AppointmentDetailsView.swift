import ClinicalModels
import SQLiteData
import SwiftUI

struct AppointmentDetailsView: View {
    @Environment(Router.self) private var router
    @State private var model: AppointmentDetailsModel
    @State private var hasResolvedInitialDetails = false
    @State private var visitID = UUID()

    let presentationID: DetailsPresentation.ID
    let onSelectPatient: @MainActor @Sendable (Patient.ID) -> Void

    init(
        id: Appointment.ID,
        presentationID: DetailsPresentation.ID,
        onSelectPatient: @escaping @MainActor @Sendable (Patient.ID) -> Void
    ) {
        _model = State(initialValue: AppointmentDetailsModel(appointmentID: id))
        self.presentationID = presentationID
        self.onSelectPatient = onSelectPatient
    }

    var body: some View {
        Group {
            if let details = model.details {
                // The appointment date is unknown until this record resolves. Keep the sheet
                // neutral until the router has aligned the Schedule tab and day; rendering sooner
                // would show details for date X over a schedule displaying date Y.
                if canRender(details) {
                    AppointmentDetailsContent(
                        model: model,
                        presentationID: presentationID,
                        onComplete: {
                            router.beginAppointmentCompletion(
                                details, visitID: visitID, presentationID: presentationID)
                        },
                        onSelectPatient: onSelectPatient
                    )
                } else {
                    ProgressView()
                        .task(id: details.appointment.start) {
                            router.alignSchedule(
                                with: details.appointment.start,
                                appointmentID: details.appointment.id,
                                presentationID: presentationID
                            )
                        }
                }
            } else if hasResolvedInitialDetails {
                AppointmentDetailsContent(
                    model: model,
                    presentationID: presentationID,
                    onSelectPatient: onSelectPatient
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Appointment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let details = model.details, model.showsMessagingAction {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        "Send Appointment Confirmation",
                        systemImage: "arrow.up.message"
                    ) {
                        router.requestAppointmentMessage(details)
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
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
        .task {
            _ = try? await model.load()
            guard !Task.isCancelled else { return }
            hasResolvedInitialDetails = true
        }
    }

    private func canRender(_ details: AppointmentDetails) -> Bool {
        let appointmentID = details.appointment.id
        guard
            router.isCurrentDetailsRoute(
                .appointment(appointmentID),
                presentationID: presentationID
            )
        else {
            // A covered route must keep its resolved content and navigation preferences mounted.
            return true
        }

        return router.scheduleIsAligned(
            with: details.appointment.start,
            appointmentID: appointmentID,
            presentationID: presentationID
        )
    }
}

private struct AppointmentDetailsContent: View {
    @Environment(Router.self) private var router

    @Bindable var model: AppointmentDetailsModel

    let presentationID: DetailsPresentation.ID
    let onSelectPatient: @MainActor @Sendable (Patient.ID) -> Void
    var onComplete: @MainActor () -> Void = {}

    init(
        model: AppointmentDetailsModel,
        presentationID: DetailsPresentation.ID,
        onComplete: @escaping @MainActor () -> Void = {},
        onSelectPatient: @escaping @MainActor @Sendable (Patient.ID) -> Void
    ) {
        self.model = model
        self.presentationID = presentationID
        self.onComplete = onComplete
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
                                onComplete: onComplete,
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
    }

    private func performStatusUpdate(_ status: Appointment.Status) async {
        let visitID =
            router.detailsPresentation?.id == presentationID
            ? router.detailsPresentation?.visitID
            : nil
        if await model.updateStatus(to: status), let visitID {
            router.dismissDetails(presentationID: presentationID, visitID: visitID)
        }
    }
}

struct AppointmentDetailsActionsView: View {
    var showsActions = true
    let isUpdating: Bool
    let onComplete: @MainActor () -> Void
    let onReschedule: @MainActor () -> Void
    let onCancel: @MainActor () async -> Void
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer {
            if showsActions {
                HStack {
                    Button(action: onComplete) {
                        Label("Complete", systemImage: "checkmark")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appGlassProminent)
                    .glassEffectID("complete", in: glassNamespace)
                    .glassEffectTransition(.materialize)

                    Button {
                        onReschedule()
                    } label: {
                        Label(
                            "Reschedule",
                            systemImage: "clock.arrow.trianglehead.clockwise.rotate.90.path.dotted"
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("reschedule", in: glassNamespace)
                    .glassEffectTransition(.materialize)

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
                    .glassEffectID("cancel", in: glassNamespace)
                    .glassEffectTransition(.materialize)
                }
                .disabled(isUpdating)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(AppMotion.animation(.smooth(duration: 0.28)), value: showsActions)
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    NavigationStack {
        AppointmentDetailsContent(
            model: AppointmentDetailsModel(appointmentID: sampleAppointments[0].id),
            presentationID: UUID()
        ) { _ in }
    }
    .environment(Router())
}

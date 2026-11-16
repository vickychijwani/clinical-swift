import SwiftUI

private enum AppTrayItem: Identifiable {
    case app(AppPresentation)
    case schedule(ScheduleEditorSession)

    nonisolated var id: UUID {
        switch self {
        case .app(let presentation): presentation.id
        case .schedule(let session): session.id
        }
    }
}

struct AppTrayHost: ViewModifier {
    @Environment(Router.self) private var router
    @Environment(ScheduleEditorStore.self) private var editor

    func body(content: Content) -> some View {
        content.tray(
            item: Binding(
                // These values are projections of Router.activePresentation, not independent sheet state.
                // Route dismissal through the router to preserve a replacement during the tray's exit.
                get: { trayItem },
                set: { value in
                    guard value == nil, let current = trayItem else { return }
                    switch current {
                    case .schedule(let session): session.isShowingSheet = false
                    case .app: router.dismissPresentation()
                    }
                }),
            didAppear: router.presentationDidAppear,
            didDismiss: { id in
                router.presentationDidDismiss(id, retainingScheduleEditor: editor.session?.id)
            }
        ) { item in
            switch item {
            case .schedule(let session):
                ScheduleEditorSheet(session: session)
            case .app(let presentation):
                switch presentation {
                case .details(let details):
                    DetailsFlowView(presentation: details)
                        .id(details.visitID)
                case .patientEdit(let request):
                    EditPatientView(patient: request.patient)
                case .appointmentMessage(let request):
                    AppointmentMessageView(id: request.appointmentID)
                case .settings:
                    BackupSettingsView()
                case .scheduleCreation, .appointmentBooking, .appointmentEdit,
                    .unavailableTimeEditor:
                    EmptyView()
                }
            }
        }
    }

    private var trayItem: AppTrayItem? {
        guard let presentation = router.activePresentation else { return nil }
        switch presentation {
        case .scheduleCreation, .appointmentBooking, .appointmentEdit, .unavailableTimeEditor:
            guard let session = editor.session, session.id == presentation.id,
                session.isShowingSheet
            else { return nil }
            return .schedule(session)
        default:
            return .app(presentation)
        }
    }
}

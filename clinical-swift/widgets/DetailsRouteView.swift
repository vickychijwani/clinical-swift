import SwiftUI

struct DetailsRouteView: View {
    @Environment(Router.self) private var router
    let route: Route
    // Forward the stable sheet-session identity so async appointment resolution cannot align the
    // schedule on behalf of a details flow that has since been replaced.
    let presentationID: DetailsPresentation.ID
    let onNavigate: @MainActor @Sendable (Route) -> Void

    var body: some View {
        Group {
            switch route {
            case .patient(let id):
                PatientDetailsView(id: id) { appointmentID in
                    onNavigate(.appointment(appointmentID))
                }
            case .appointment(let id):
                AppointmentDetailsView(
                    id: id,
                    presentationID: presentationID
                ) { patientID in
                    onNavigate(.patient(patientID))
                }
            case .appointmentCompletion(let visitID):
                if let model = router.detailsPresentation?.completionDrafts[visitID] {
                    AppointmentCompletionView(model: model, presentationID: presentationID)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.canvas)
    }
}

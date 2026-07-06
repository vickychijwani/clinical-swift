import SwiftUI

struct DetailsRouteView: View {
    let route: Route
    let onNavigate: @MainActor @Sendable (Route) -> Void

    var body: some View {
        switch route {
        case .patient(let id):
            PatientDetailsView(id: id) { appointmentID in
                onNavigate(.appointment(appointmentID))
            }
        case .appointment(let id):
            AppointmentDetailsView(id: id) { patientID in
                onNavigate(.patient(patientID))
            }
        }
    }
}

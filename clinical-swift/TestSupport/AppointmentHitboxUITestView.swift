#if DEBUG
    import Foundation
    import SwiftUI

    struct AppointmentHitboxUITestView: View {
        @State private var selectedAppointment: Appointment?

        private static let leftAppointmentID = UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
        )
        private static let rightAppointmentID = UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)
        )

        private static let appointments = [
            Appointment(
                id: leftAppointmentID,
                patientName: String(repeating: "Very Long Patient Name ", count: 10),
                start: Date.now.setTime(9, 0),
                durationMinutes: 60,
                status: .scheduled
            ),
            Appointment(
                id: rightAppointmentID,
                patientName: "Short Name",
                start: Date.now.setTime(9, 0),
                durationMinutes: 60,
                status: .scheduled
            ),
        ]

        var body: some View {
            VStack(spacing: 0) {
                Text(selectionStatus)
                    .accessibilityIdentifier("selection-status")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Timeline(
                    appointments: Self.appointments,
                    scale: TimelineScale(appointments: Self.appointments),
                    showsNowMarker: false,
                    onSelectAppointment: { selectedAppointment = $0 }
                )
                .frame(width: 300)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private var selectionStatus: String {
            guard let selectedAppointment else {
                return "No appointment selected"
            }
            return selectedAppointment.id == Self.leftAppointmentID
                ? "Selected left appointment"
                : "Selected right appointment"
        }
    }
#endif

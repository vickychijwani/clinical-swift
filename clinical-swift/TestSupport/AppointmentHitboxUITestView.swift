import ClinicalModels
#if DEBUG
    import Foundation
    import SwiftUI

    struct AppointmentHitboxUITestView: View {
        @State private var selectedAppointment: Appointment?
        @State private var selectedBlock: UnavailableTime?

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
                    items: Self.items,
                    scale: TimelineScale(items: Self.items),
                    showsNowMarker: false,
                    onSelectItem: { item in
                        switch item {
                        case .appointment(let appointment):
                            selectedBlock = nil
                            selectedAppointment = appointment
                        case .unavailableTime(let block):
                            selectedAppointment = nil
                            selectedBlock = block
                        }
                    }
                )
                .frame(width: 300)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private static var items: [TimelineItem] {
            guard CommandLine.arguments.contains("--ui-testing-mixed-hitboxes") else {
                return appointments.map(TimelineItem.appointment)
            }
            return [
                .appointment(appointments[0]),
                .unavailableTime(
                    UnavailableTime(
                        id: leftAppointmentID,
                        label: String(repeating: "Long block label ", count: 10),
                        start: appointments[0].start, durationMinutes: 60
                    )),
                .unavailableTime(
                    UnavailableTime(
                        id: rightAppointmentID, label: "Travel",
                        start: appointments[0].start, durationMinutes: 60
                    )),
            ]
        }

        private var selectionStatus: String {
            if let selectedBlock {
                return selectedBlock.id == Self.leftAppointmentID
                    ? "Selected middle block" : "Selected right block"
            }
            guard let selectedAppointment else {
                return "No appointment selected"
            }
            return selectedAppointment.id == Self.leftAppointmentID
                ? "Selected left appointment"
                : "Selected right appointment"
        }
    }
#endif

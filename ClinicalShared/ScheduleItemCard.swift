import SwiftUI

struct ScheduleItemCard: View {
    let item: TimelineItem

    var body: some View {
        switch item {
        case .appointment(let appointment): AppointmentCard(appt: appointment)
        case .unavailableTime(let block): UnavailableTimeCard(block: block)
        }
    }
}

import SwiftUI

struct ScheduleItemCard: View {
    let item: TimelineItem
    var isAdjusting = false

    var body: some View {
        switch item {
        case .appointment(let appointment):
            AppointmentCard(appt: appointment, isAdjusting: isAdjusting)
        case .unavailableTime(let block): UnavailableTimeCard(block: block)
        }
    }
}

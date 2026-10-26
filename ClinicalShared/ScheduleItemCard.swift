import SwiftUI

struct ScheduleItemCard: View {
    let item: TimelineItem
    var isAdjusting = false
    var isDeemphasized = false

    var body: some View {
        switch item {
        case .appointment(let appointment):
            AppointmentCard(
                appt: appointment, isAdjusting: isAdjusting, isDeemphasized: isDeemphasized)
        case .unavailableTime(let block):
            UnavailableTimeCard(block: block, isDeemphasized: isDeemphasized)
        }
    }
}

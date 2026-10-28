import SwiftUI

struct ScheduleItemCard: View {
    let item: TimelineItem
    var isDraft = false
    var isDeemphasized = false

    var body: some View {
        switch item {
        case .appointment(let appointment):
            AppointmentCard(
                appt: appointment, isDeemphasized: isDeemphasized)
        case .unavailableTime(let block):
            UnavailableTimeCard(
                block: block, isDraft: isDraft, isDeemphasized: isDeemphasized)
        }
    }
}

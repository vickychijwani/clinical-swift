import SwiftUI

struct ScheduleItemCard: View {
    let item: TimelineItem
    var isDraft = false
    var isDeemphasized = false
    var contentTrailingInset: CGFloat = 0
    var presentation: ScheduleCardPresentation? = nil

    var body: some View {
        switch item {
        case .appointment(let appointment):
            AppointmentCard(
                appt: appointment, isDeemphasized: isDeemphasized,
                contentTrailingInset: contentTrailingInset,
                presentation: presentation)
        case .unavailableTime(let block):
            UnavailableTimeCard(
                block: block, isDraft: isDraft, isDeemphasized: isDeemphasized,
                contentTrailingInset: contentTrailingInset,
                presentation: presentation)
        }
    }
}

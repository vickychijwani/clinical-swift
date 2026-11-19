import SwiftUI

struct ScheduleItemCard: View {
    let item: TimelineItem
    var isDraft = false
    var isDeemphasized = false
    var contentTrailingInset: CGFloat = 0
    var usesCompactTime = false
    var usesCompactStack = false

    var body: some View {
        switch item {
        case .appointment(let appointment):
            AppointmentCard(
                appt: appointment, isDeemphasized: isDeemphasized,
                contentTrailingInset: contentTrailingInset,
                usesCompactTime: usesCompactTime,
                usesCompactStack: usesCompactStack)
        case .unavailableTime(let block):
            UnavailableTimeCard(
                block: block, isDraft: isDraft, isDeemphasized: isDeemphasized,
                contentTrailingInset: contentTrailingInset,
                usesCompactTime: usesCompactTime,
                usesCompactStack: usesCompactStack)
        }
    }
}

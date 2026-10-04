import SwiftUI

struct WidgetScheduleContentView: View {
    let snapshot: WidgetScheduleSnapshot
    private let planner = WidgetLayoutPlanner()

    var body: some View {
        GeometryReader { geometry in
            let plan = planner.plan(
                sections: snapshot.sections,
                availableHeight: geometry.size.height
            )

            VStack(spacing: planner.configuration.sectionSpacing) {
                ForEach(plan.sections, id: \.sourceIndex) { plannedSection in
                    let isLast = plannedSection.sourceIndex == plan.sections.last?.sourceIndex
                    WidgetDateSectionView(
                        section: snapshot.sections[plannedSection.sourceIndex],
                        plan: plannedSection,
                        rowHeight: plan.rowHeight,
                        trailingSpace: isLast ? plan.trailingSpace : 0,
                        planner: planner
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct WidgetDateSectionView: View {
    let section: WidgetScheduleSection
    let plan: WidgetPlannedSection
    let rowHeight: CGFloat
    let trailingSpace: CGFloat
    let planner: WidgetLayoutPlanner

    var body: some View {
        ZStack(alignment: .topLeading) {
            WidgetSectionDestinationView(date: section.date)

            VStack(alignment: .leading, spacing: 0) {
                Text(
                    section.date,
                    format: .dateTime.weekday(.wide).day().month(.abbreviated)
                )
                .textCase(.uppercase)
                .font(.caption.bold())
                .foregroundStyle(section.isToday ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .frame(
                    maxWidth: .infinity,
                    minHeight: planner.configuration.headerHeight,
                    maxHeight: planner.configuration.headerHeight,
                    alignment: .leading
                )
                .allowsHitTesting(false)

                Color.clear
                    .frame(height: planner.configuration.headerToRowsSpacing)
                    .allowsHitTesting(false)

                VStack(spacing: planner.configuration.rowSpacing) {
                    ForEach(plan.rows.enumerated(), id: \.offset) { _, row in
                        WidgetScheduleRowView(
                            row: row,
                            section: section,
                            rowHeight: rowHeight
                        )
                    }
                }
            }
        }
        .frame(
            height: planner.height(for: plan, rowHeight: rowHeight) + trailingSpace,
            alignment: .top
        )
    }

}

private struct WidgetSectionDestinationView: View {
    let date: Date
    @Environment(\.calendar) private var calendar

    var body: some View {
        let day = ScheduleDay(date: date, calendar: calendar)
        if let destination = ClinicalURL.schedule(day).url {
            Link(destination: destination) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct WidgetScheduleRowView: View {
    let row: WidgetPlannedRow
    let section: WidgetScheduleSection
    let rowHeight: CGFloat
    @Environment(\.calendar) private var calendar

    var body: some View {
        switch row {
        case .item(let index):
            if section.items.indices.contains(index) {
                let item = section.items[index]
                if let destination = item.widgetURL(using: calendar) {
                    Link(destination: destination) {
                        WidgetItemCard(item: item)
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                            .contentShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
                            .clipShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
                    }
                    .buttonStyle(.plain)
                }
            }

        case .empty:
            WidgetScheduleEmptyRowView(section: section, rowHeight: rowHeight)

        case .overflow(let hiddenCount):
            Text(section.overflowText(hiddenCount: hiddenCount))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                .allowsHitTesting(false)
        }
    }
}

private struct WidgetItemCard: View {
    let item: TimelineItem

    var body: some View {
        ScheduleItemCard(item: item)
            .overlay(alignment: .leading) {
                stripeColor.frame(width: 4)
            }
            .clipShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
    }

    private var stripeColor: Color {
        switch item {
        case .appointment: .accentColor
        case .unavailableTime: Color("UnavailableTimeBorder")
        }
    }
}

private struct WidgetScheduleEmptyRowView: View {
    let section: WidgetScheduleSection
    let rowHeight: CGFloat
    @Environment(\.calendar) private var calendar

    var body: some View {
        let message =
            if calendar.component(.weekday, from: section.date) == 1 {
                "Vacation day 🌻"
            } else if section.isToday {
                "No more appointments today"
            } else {
                "No appointments"
            }

        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .allowsHitTesting(false)
    }
}

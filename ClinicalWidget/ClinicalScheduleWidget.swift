import SwiftUI
import WidgetKit

nonisolated enum ClinicalScheduleEntryContent: Sendable {
    case schedule(WidgetScheduleSnapshot)
    case unavailable
}

nonisolated struct ClinicalScheduleEntry: TimelineEntry, Sendable {
    let date: Date
    let content: ClinicalScheduleEntryContent
}

nonisolated struct ClinicalScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClinicalScheduleEntry {
        sampleEntry(at: .now, appointmentCount: 5)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (ClinicalScheduleEntry) -> Void
    ) {
        if context.isPreview {
            completion(sampleEntry(at: .now, appointmentCount: 5))
        } else {
            completion(liveEntry(at: .now))
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<ClinicalScheduleEntry>) -> Void
    ) {
        let entry = liveEntry(at: .now)
        let nextRefresh =
            switch entry.content {
            case .schedule(let snapshot):
                snapshot.nextRefreshDate(using: .autoupdatingCurrent)
            case .unavailable:
                Calendar.autoupdatingCurrent.date(
                    byAdding: .minute,
                    value: 30,
                    to: entry.date
                ) ?? entry.date.addingTimeInterval(30 * 60)
            }
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func liveEntry(at date: Date) -> ClinicalScheduleEntry {
        do {
            let databaseURL = try ClinicalSharedDatabase.databaseURL()
            let repository = WidgetScheduleRepository(databaseURL: databaseURL)
            guard let snapshot = try repository.snapshot(at: date) else {
                return ClinicalScheduleEntry(date: date, content: .unavailable)
            }
            return ClinicalScheduleEntry(date: date, content: .schedule(snapshot))
        } catch {
            return ClinicalScheduleEntry(date: date, content: .unavailable)
        }
    }

    fileprivate func sampleEntry(
        at date: Date,
        appointmentCount: Int
    ) -> ClinicalScheduleEntry {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: date)
        let names = [
            "Aarav Mehta",
            "Mira Shah",
            PatientDisplayName.unknown,
            "Ishaan Patel",
            "Anaya Desai",
            "Vivaan Kapoor",
        ]
        let appointments: [Appointment] = (0..<appointmentCount).compactMap { index in
            guard
                let start = calendar.date(
                    byAdding: .minute,
                    value: 10 * 60 + index * 75,
                    to: today
                )
            else {
                return nil
            }
            return Appointment(
                id: UUID(),
                patientName: names[index % names.count],
                start: start,
                durationMinutes: 45,
                status: index == 0 ? .completed : .scheduled
            )
        }

        let sections = (0..<3).compactMap { offset -> WidgetScheduleSection? in
            guard let sectionDate = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }
            return WidgetScheduleSection(
                date: sectionDate,
                isToday: offset == 0,
                appointments: offset == 0 ? appointments : []
            )
        }

        return ClinicalScheduleEntry(
            date: date,
            content: .schedule(
                WidgetScheduleSnapshot(generatedAt: date, sections: sections)
            )
        )
    }
}

struct ClinicalScheduleWidgetView: View {
    let entry: ClinicalScheduleEntry

    var body: some View {
        switch entry.content {
        case .schedule(let snapshot):
            WidgetScheduleContentView(snapshot: snapshot)
        case .unavailable:
            WidgetUnavailableView(date: entry.date)
        }
    }
}

private struct WidgetScheduleContentView: View {
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

    var body: some View {
        switch row {
        case .appointment(let index):
            if section.appointments.indices.contains(index) {
                let appointment = section.appointments[index]
                if let destination = ClinicalURL.appointment(appointment.id).url {
                    Link(destination: destination) {
                        AppointmentCard(appt: appointment)
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                            .overlay(alignment: .leading) {
                                Color.accentColor.frame(width: 4)
                            }
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

        case .empty:
            WidgetScheduleEmptyRowView(section: section, rowHeight: rowHeight)

        case .overflow(let hiddenCount):
            Text(
                hiddenCount == 1
                    ? "1 more appointment"
                    : "\(hiddenCount) more appointments"
            )
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .allowsHitTesting(false)
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

private struct WidgetUnavailableView: View {
    let date: Date
    @Environment(\.calendar) private var calendar

    var body: some View {
        let day = ScheduleDay(date: date, calendar: calendar)
        ZStack {
            if let destination = ClinicalURL.schedule(day).url {
                Link(destination: destination) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading) {
                Text(
                    date,
                    format: .dateTime.weekday(.wide).day().month(.abbreviated)
                )
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)

                Text("Open Clinical to load appointments")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}

@main
struct ClinicalScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ClinicalWidgetConstants.scheduleKind,
            provider: ClinicalScheduleProvider()
        ) { entry in
            ClinicalScheduleWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color("AppBackground")
                }
        }
        .configurationDisplayName("Upcoming Appointments")
        .description("See today's remaining appointments and the next two dates.")
        .supportedFamilies([.systemLarge])
    }
}

#Preview(
    "Dense", as: .systemLarge,
    widget: {
        ClinicalScheduleWidget()
    },
    timeline: {
        ClinicalScheduleProvider().sampleEntry(at: .now, appointmentCount: 8)
    })

#Preview(
    "Sparse", as: .systemLarge,
    widget: {
        ClinicalScheduleWidget()
    },
    timeline: {
        ClinicalScheduleProvider().sampleEntry(at: .now, appointmentCount: 2)
    })

#Preview(
    "Unavailable", as: .systemLarge,
    widget: {
        ClinicalScheduleWidget()
    },
    timeline: {
        ClinicalScheduleEntry(date: .now, content: .unavailable)
    })

import ClinicalModels
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
        appointmentCount: Int,
        blockCount: Int = 1
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
                items: offset == 0
                    ? appointments.map(TimelineItem.appointment)
                        + (0..<blockCount).map { index in
                            .unavailableTime(
                                UnavailableTime(
                                    label: index == 0 ? "Travel" : nil,
                                    start: today.addingTimeInterval(
                                        Double(11 * 60 + index * 60) * 60),
                                    durationMinutes: 60
                                ))
                        } : []
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

                Text("Open Clinical to load the schedule")
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
        .configurationDisplayName("Upcoming Schedule")
        .description("See appointments and unavailable time for today and the next two dates.")
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

#Preview(
    "Blocks only", as: .systemLarge,
    widget: {
        ClinicalScheduleWidget()
    },
    timeline: {
        ClinicalScheduleProvider().sampleEntry(at: .now, appointmentCount: 0, blockCount: 3)
    })

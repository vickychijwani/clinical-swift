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
            let now = Date.now
            var entries: [TelemetryEntry] = []
            let entry = liveEntry(at: now, source: "snapshot", entries: &entries)
            completion(entry)
            flushWidgetTelemetry(entries, at: now)
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<ClinicalScheduleEntry>) -> Void
    ) {
        let now = Date.now
        var entries: [TelemetryEntry] = []
        let entry = liveEntry(at: now, source: "timeline", entries: &entries)
        let nextRefresh =
            switch entry.content {
            case .schedule(let snapshot):
                snapshot.nextRefreshDate(using: ClinicDate.calendar)
            case .unavailable:
                ClinicDate.calendar.date(
                    byAdding: .minute,
                    value: 30,
                    to: entry.date
                ) ?? entry.date.addingTimeInterval(30 * 60)
            }
        // Hand the timeline to WidgetKit before writing the telemetry segment so disk I/O stays off the refresh path.
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        flushWidgetTelemetry(entries, at: now)
    }

    private func liveEntry(
        at date: Date,
        source: String,
        entries: inout [TelemetryEntry]
    ) -> ClinicalScheduleEntry {
        let start = ContinuousClock.now
        do {
            let databaseURL = try ClinicalSharedDatabase.databaseURL()
            let repository = WidgetScheduleRepository(databaseURL: databaseURL)
            guard let snapshot = try repository.snapshot(at: date) else {
                entries.append(
                    TelemetryEntry(
                        kind: .event,
                        level: .info,
                        category: .widget,
                        name: "widget_snapshot_unavailable",
                        status: "missing_database",
                        source: source
                    ))
                return ClinicalScheduleEntry(date: date, content: .unavailable)
            }
            let elapsed = start.duration(to: ContinuousClock.now)
            let durationMS = Int(
                (Double(elapsed.components.seconds) * 1000.0
                    + Double(elapsed.components.attoseconds) / 1e15).rounded())
            let itemCount = snapshot.sections.reduce(0) { $0 + $1.items.count }
            entries.append(
                TelemetryEntry(
                    kind: .event,
                    level: .info,
                    category: .widget,
                    name: "widget_snapshot_loaded",
                    durationMS: durationMS,
                    count: itemCount,
                    status: "loaded",
                    source: source
                ))
            return ClinicalScheduleEntry(date: date, content: .schedule(snapshot))
        } catch {
            entries.append(
                TelemetryEntry(
                    kind: .log,
                    level: .error,
                    category: .widget,
                    name: "widget_snapshot_failed",
                    message: "Widget schedule read failed",
                    error: error,
                    source: source
                ))
            return ClinicalScheduleEntry(date: date, content: .unavailable)
        }
    }

    fileprivate func sampleEntry(
        at date: Date,
        appointmentCount: Int,
        blockCount: Int = 1
    ) -> ClinicalScheduleEntry {
        let calendar = ClinicDate.calendar
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

        let appointmentItems = appointments.map(TimelineItem.appointment)
        // Samples show a named block first, then the default label for unnamed blocks.
        let blockItems: [TimelineItem] = (0..<blockCount).map { index in
            let block = UnavailableTime(
                label: index == 0 ? "Travel" : nil,
                start: today.addingTimeInterval(Double(11 * 60 + index * 60) * 60),
                durationMinutes: 60
            )
            return .unavailableTime(block)
        }
        let todayItems = appointmentItems + blockItems

        let sections = (0..<3).compactMap { offset -> WidgetScheduleSection? in
            guard let sectionDate = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }
            return WidgetScheduleSection(
                date: sectionDate,
                isToday: offset == 0,
                items: offset == 0 ? todayItems : []
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

    var body: some View {
        let day = ScheduleDay(date: date, calendar: ClinicDate.calendar)
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
                    format: ClinicDate.formatStyle.weekday(.wide).day().month(.abbreviated)
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

struct ClinicalScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ClinicalWidgetConstants.scheduleKind,
            provider: ClinicalScheduleProvider()
        ) { entry in
            ClinicalScheduleWidgetView(entry: entry)
                .environment(\.timeZone, ClinicDate.timeZone)
                .environment(\.calendar, ClinicDate.calendar)
                .environment(\.locale, ClinicDate.locale)
                .containerBackground(for: .widget) {
                    Color("AppCanvas")
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

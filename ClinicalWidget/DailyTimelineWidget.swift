import ClinicalModels
import SwiftUI
import WidgetKit

nonisolated enum DailyTimelineEntryContent: Sendable {
    case day(WidgetDaySnapshot)
    case unavailable
}

nonisolated struct DailyTimelineEntry: TimelineEntry, Sendable {
    let date: Date
    let content: DailyTimelineEntryContent
}

nonisolated struct DailyTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyTimelineEntry {
        sampleEntry(at: sampleReferenceTime(on: .now))
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (DailyTimelineEntry) -> Void
    ) {
        if context.isPreview {
            completion(sampleEntry(at: sampleReferenceTime(on: .now)))
            return
        }

        let now = Date.now
        let selection = DailyTimelineWidgetState.live.selection(at: now)
        var entries: [TelemetryEntry] = []
        let entry = loadEntry(
            for: selection.day,
            at: now,
            source: "daily_timeline_snapshot",
            entries: &entries
        )
        flushWidgetTelemetry(entries, at: now)
        completion(entry)
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<DailyTimelineEntry>) -> Void
    ) {
        let now = Date.now
        let selection = DailyTimelineWidgetState.live.selection(at: now)
        var telemetryEntries: [TelemetryEntry] = []

        if let resetAt = selection.resetAt {
            let selectedEntry = loadEntry(
                for: selection.day,
                at: now,
                source: "daily_timeline",
                entries: &telemetryEntries
            )
            let resetDay = ScheduleDay(date: resetAt, calendar: ClinicDate.calendar)
            let resetEntry = loadEntry(
                for: resetDay,
                at: resetAt,
                source: "daily_timeline_reset",
                entries: &telemetryEntries
            )
            flushWidgetTelemetry(telemetryEntries, at: now)
            switch resetEntry.content {
            case .day(let resetSnapshot):
                let schedule = DailyTimelineSchedule.resetEntryDates(at: now, resetAt: resetAt)
                let entries =
                    [selectedEntry]
                    + schedule.resetEntryDates.map { date in
                        DailyTimelineEntry(date: date, content: .day(resetSnapshot))
                    }
                completion(Timeline(entries: entries, policy: .after(schedule.reloadDate)))
            case .unavailable:
                completion(
                    Timeline(entries: [selectedEntry, resetEntry], policy: .after(resetAt))
                )
            }
            return
        }

        let currentEntry = loadEntry(
            for: selection.day,
            at: now,
            source: "daily_timeline",
            entries: &telemetryEntries
        )
        flushWidgetTelemetry(telemetryEntries, at: now)

        switch currentEntry.content {
        case .day(let snapshot):
            let schedule = DailyTimelineSchedule.todayEntryDates(from: now)
            let timelineEntries = schedule.entryDates.map { date in
                DailyTimelineEntry(date: date, content: .day(snapshot))
            }
            completion(Timeline(entries: timelineEntries, policy: .after(schedule.reloadDate)))

        case .unavailable:
            let retryDate =
                ClinicDate.calendar.date(byAdding: .minute, value: 30, to: now)
                ?? now.addingTimeInterval(30 * 60)
            completion(Timeline(entries: [currentEntry], policy: .after(retryDate)))
        }
    }

    private func loadEntry(
        for day: ScheduleDay,
        at date: Date,
        source: String,
        entries: inout [TelemetryEntry]
    ) -> DailyTimelineEntry {
        let start = ContinuousClock.now
        do {
            let databaseURL = try ClinicalSharedDatabase.databaseURL()
            let repository = WidgetScheduleRepository(databaseURL: databaseURL)
            guard let snapshot = try repository.daySnapshot(for: day, at: date) else {
                entries.append(
                    TelemetryEntry(
                        kind: .event,
                        level: .info,
                        category: .widget,
                        name: "widget_snapshot_unavailable",
                        status: "missing_database",
                        source: source
                    ))
                return DailyTimelineEntry(date: date, content: .unavailable)
            }
            let elapsed = start.duration(to: ContinuousClock.now)
            let durationMS = Int(
                (Double(elapsed.components.seconds) * 1000.0
                    + Double(elapsed.components.attoseconds) / 1e15).rounded())
            entries.append(
                TelemetryEntry(
                    kind: .event,
                    level: .info,
                    category: .widget,
                    name: "widget_snapshot_loaded",
                    durationMS: durationMS,
                    count: snapshot.items.count,
                    status: "loaded",
                    source: source
                ))
            return DailyTimelineEntry(date: date, content: .day(snapshot))
        } catch {
            entries.append(
                TelemetryEntry(
                    kind: .log,
                    level: .error,
                    category: .widget,
                    name: "widget_snapshot_failed",
                    message: "Daily timeline widget read failed",
                    error: error,
                    source: source
                ))
            return DailyTimelineEntry(date: date, content: .unavailable)
        }
    }

    private func flushWidgetTelemetry(_ entries: [TelemetryEntry], at date: Date) {
        guard !entries.isEmpty,
            let directory = TelemetrySpool.defaultDirectory()
        else { return }
        // Widget runs collect records in memory and write one immutable segment atomically.
        let settings = TelemetrySettingsStore()
        let builder = TelemetryRecordBuilder(process: .widget, settings: settings)
        let records = entries.map { builder.makeRecord(from: $0, now: date) }
        let spool = TelemetrySpool(directory: directory)
        spool.writeWidgetSegment(records, now: date)
    }

    private func sampleReferenceTime(on date: Date) -> Date {
        TimeOfDay(11, 20).on(date: ClinicDate.day(date), using: ClinicDate.calendar)
    }

    fileprivate func sampleEntry(
        at date: Date,
        includeBreakItems: Bool = false,
        isToday: Bool = true
    ) -> DailyTimelineEntry {
        let dayStart = ClinicDate.day(date)
        let day = ScheduleDay(date: dayStart, calendar: ClinicDate.calendar)
        let calendar = ClinicDate.calendar

        var items: [TimelineItem] = [
            .appointment(
                Appointment(
                    patientName: "Aarav Mehta",
                    start: TimeOfDay(10, 0).on(date: dayStart, using: calendar),
                    durationMinutes: 45,
                    status: .completed
                )),
            .appointment(
                Appointment(
                    patientName: "Mira Shah",
                    start: TimeOfDay(11, 0).on(date: dayStart, using: calendar),
                    durationMinutes: 30,
                    status: .scheduled
                )),
            .appointment(
                Appointment(
                    patientName: "Kabir Malhotra",
                    start: TimeOfDay(11, 15).on(date: dayStart, using: calendar),
                    durationMinutes: 30,
                    status: .scheduled
                )),
            .appointment(
                Appointment(
                    patientName: "Anaya Desai",
                    start: TimeOfDay(12, 0).on(date: dayStart, using: calendar),
                    durationMinutes: 15,
                    status: .scheduled
                )),
            .unavailableTime(
                UnavailableTime(
                    label: "Lab review",
                    start: TimeOfDay(16, 30).on(date: dayStart, using: calendar),
                    durationMinutes: 45
                )),
            .appointment(
                Appointment(
                    patientName: "Ishaan Patel",
                    start: TimeOfDay(17, 30).on(date: dayStart, using: calendar),
                    durationMinutes: 60,
                    status: .scheduled
                )),
            .appointment(
                Appointment(
                    patientName: "Priya Narayanan",
                    start: TimeOfDay(19, 0).on(date: dayStart, using: calendar),
                    durationMinutes: 45,
                    status: .scheduled
                )),
        ]

        if includeBreakItems {
            items.append(
                .appointment(
                    Appointment(
                        patientName: "Vivaan Kapoor",
                        start: TimeOfDay(14, 0).on(date: dayStart, using: calendar),
                        durationMinutes: 15,
                        status: .scheduled
                    )))
            items.append(
                .appointment(
                    Appointment(
                        patientName: "Riya Verma",
                        start: TimeOfDay(14, 30).on(date: dayStart, using: calendar),
                        durationMinutes: 45,
                        status: .scheduled
                    )))
        }

        let snapshot = WidgetDaySnapshot(
            day: day,
            date: dayStart,
            isToday: isToday,
            items: items,
            generatedAt: date,
            calendar: calendar
        )
        return DailyTimelineEntry(date: date, content: .day(snapshot))
    }
}

private struct DailyTimelineWidgetView: View {
    let entry: DailyTimelineEntry

    var body: some View {
        switch entry.content {
        case .day(let snapshot):
            WidgetDailyTimelineContentView(snapshot: snapshot, entryDate: entry.date)
        case .unavailable:
            DailyTimelineUnavailableView(date: entry.date)
        }
    }
}

private struct DailyTimelineUnavailableView: View {
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
                .textCase(.uppercase)
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)

                Text("Open Clinical to load the schedule")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}

struct DailyTimelineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ClinicalWidgetConstants.dailyTimelineKind,
            provider: DailyTimelineProvider()
        ) { entry in
            DailyTimelineWidgetView(entry: entry)
                .environment(\.timeZone, ClinicDate.timeZone)
                .environment(\.calendar, ClinicDate.calendar)
                .environment(\.locale, ClinicDate.locale)
                .containerBackground(for: .widget) {
                    Color("AppCanvas")
                }
        }
        .configurationDisplayName("Daily Timeline")
        .description("See a full day's schedule in timeline form with quick day navigation.")
        .supportedFamilies([.systemExtraLargePortrait])
        .contentMarginsDisabled()
    }
}

#Preview(
    "Normal Day", as: .systemExtraLargePortrait,
    widget: {
        DailyTimelineWidget()
    },
    timeline: {
        DailyTimelineProvider().sampleEntry(
            at: TimeOfDay(11, 20).on(date: ClinicDate.today, using: ClinicDate.calendar)
        )
    })

#Preview(
    "Break Expanded", as: .systemExtraLargePortrait,
    widget: {
        DailyTimelineWidget()
    },
    timeline: {
        DailyTimelineProvider().sampleEntry(
            at: TimeOfDay(14, 10).on(date: ClinicDate.today, using: ClinicDate.calendar),
            includeBreakItems: true
        )
    })

#Preview(
    "Another Day", as: .systemExtraLargePortrait,
    widget: {
        DailyTimelineWidget()
    },
    timeline: {
        DailyTimelineProvider().sampleEntry(
            at: TimeOfDay(11, 20).on(
                date: ClinicDate.today.date(byAddingDays: 1, using: ClinicDate.calendar),
                using: ClinicDate.calendar
            ),
            isToday: false
        )
    })

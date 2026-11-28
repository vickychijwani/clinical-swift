import ClinicalModels
import SwiftUI
import Synchronization
import WidgetKit

/// Tracks in-extension ContinuousClock timestamps across an interactive widget button tap
/// (`perform()` -> `getTimeline()` -> `completion()` -> final SwiftUI view layout pass).
nonisolated enum DailyTimelineTapMetrics {
    struct PendingTap: Sendable {
        let id: UUID
        let action: String
        let startedAt: ContinuousClock.Instant
    }

    private struct ActiveRender: Sendable {
        let id: UUID
        let action: String
        let startedAt: ContinuousClock.Instant
        let totalEntries: Int
        var renderedEntries: Int
    }

    private struct State: Sendable {
        var pendingTap: PendingTap?
        var activeRender: ActiveRender?
    }

    private static let state = Mutex<State>(State())

    static func recordIntentStart(action: String) {
        state.withLock { state in
            state.pendingTap = PendingTap(id: UUID(), action: action, startedAt: .now)
        }
    }

    static func consumePendingTap() -> PendingTap? {
        state.withLock { state in
            let tap = state.pendingTap
            state.pendingTap = nil
            return tap
        }
    }

    static func beginRenderTracking(for tap: PendingTap, entryCount: Int) {
        guard entryCount > 0 else { return }
        state.withLock { state in
            state.activeRender = ActiveRender(
                id: tap.id,
                action: tap.action,
                startedAt: tap.startedAt,
                totalEntries: entryCount,
                renderedEntries: 0
            )
        }
    }

    /// Marks one archived widget entry's SwiftUI body as evaluated and dispatches the telemetry
    /// write asynchronously off the view-construction path once the final entry completes.
    static func recordEntryBodyEvaluated(renderID: UUID?) {
        guard let renderID else { return }
        let completed: (action: String, totalEntries: Int, durationMS: Int)? = state.withLock {
            state in
            guard var active = state.activeRender, active.id == renderID else { return nil }
            active.renderedEntries += 1
            if active.renderedEntries >= active.totalEntries {
                state.activeRender = nil
                return (
                    active.action,
                    active.totalEntries,
                    milliseconds(from: active.startedAt, to: .now)
                )
            }
            state.activeRender = active
            return nil
        }
        guard let completed else { return }
        let entry = TelemetryEntry(
            kind: .event,
            level: .info,
            category: .widget,
            name: "widget_tap_body_evaluated",
            durationMS: completed.durationMS,
            count: completed.totalEntries,
            status: "body_evaluated",
            source: "daily_timeline",
            action: completed.action
        )
        let now = Date.now
        Task.detached(priority: .utility) {
            flushWidgetTelemetry([entry], at: now)
        }
    }

    static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Int {
        let elapsed = start.duration(to: end)
        return Int(
            (Double(elapsed.components.seconds) * 1000.0
                + Double(elapsed.components.attoseconds) / 1e15).rounded()
        )
    }
}

nonisolated enum DailyTimelineEntryContent: Sendable {
    case day(WidgetDaySnapshot)
    case unavailable
}

nonisolated struct DailyTimelineEntry: TimelineEntry, Sendable {
    let date: Date
    let displayDate: Date
    let content: DailyTimelineEntryContent
    let tapRenderID: UUID?

    init(
        date: Date,
        displayDate: Date? = nil,
        content: DailyTimelineEntryContent,
        tapRenderID: UUID? = nil
    ) {
        self.date = date
        self.displayDate = displayDate ?? date
        self.content = content
        self.tapRenderID = tapRenderID
    }
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

        let realNow = Date.now
        #if DEBUG
            let simulatedNow = DailyTimelineWidgetState.live.effectiveNow(from: realNow)
        #else
            let simulatedNow = realNow
        #endif
        let selection = DailyTimelineWidgetState.live.selection(at: simulatedNow)
        var entries: [TelemetryEntry] = []
        let snapshot = loadSnapshot(
            for: selection.day,
            at: simulatedNow,
            source: "daily_timeline_snapshot",
            entries: &entries
        )
        let entry = DailyTimelineEntry(
            date: realNow,
            displayDate: simulatedNow,
            content: snapshot.map(DailyTimelineEntryContent.day) ?? .unavailable
        )
        completion(entry)
        flushWidgetTelemetry(entries, at: realNow)
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<DailyTimelineEntry>) -> Void
    ) {
        let timelineStart = ContinuousClock.now
        let pendingTap = DailyTimelineTapMetrics.consumePendingTap()
        let realNow = Date.now
        #if DEBUG
            let simulatedNow = DailyTimelineWidgetState.live.effectiveNow(from: realNow)
        #else
            let simulatedNow = realNow
        #endif
        let selection = DailyTimelineWidgetState.live.selection(at: simulatedNow)
        let preferFastToday = DailyTimelineWidgetState.live.consumeFastTodayPending()
        var telemetryEntries: [TelemetryEntry] = []

        if let pendingTap {
            telemetryEntries.append(
                TelemetryEntry(
                    kind: .event,
                    level: .info,
                    category: .widget,
                    name: "widget_intent_dispatch",
                    durationMS: DailyTimelineTapMetrics.milliseconds(
                        from: pendingTap.startedAt,
                        to: timelineStart
                    ),
                    status: "dispatched",
                    source: "daily_timeline",
                    action: pendingTap.action
                ))
        }

        let plan = DailyTimelineSchedule.plan(
            at: simulatedNow,
            selection: selection,
            preferFastToday: preferFastToday,
            loadDay: { day, date in
                loadSnapshot(
                    for: day,
                    at: date,
                    source: "daily_timeline",
                    entries: &telemetryEntries
                )
            }
        )
        .shifted(to: realNow, from: simulatedNow)

        let tapRenderID = pendingTap?.id
        if let pendingTap {
            DailyTimelineTapMetrics.beginRenderTracking(
                for: pendingTap,
                entryCount: plan.entries.count
            )
            telemetryEntries.append(
                TelemetryEntry(
                    kind: .event,
                    level: .info,
                    category: .widget,
                    name: "widget_tap_completed",
                    durationMS: DailyTimelineTapMetrics.milliseconds(
                        from: pendingTap.startedAt,
                        to: .now
                    ),
                    count: plan.entries.count,
                    status: "completed",
                    source: "daily_timeline",
                    action: pendingTap.action
                ))
        }

        let entries = plan.entries.map { entry in
            DailyTimelineEntry(
                date: entry.date,
                displayDate: entry.displayDate,
                content: entry.snapshot.map(DailyTimelineEntryContent.day) ?? .unavailable,
                tapRenderID: tapRenderID
            )
        }
        // Hand the timeline to WidgetKit before writing the telemetry segment so disk I/O stays off the tap path.
        completion(Timeline(entries: entries, policy: .after(plan.reloadDate)))
        flushWidgetTelemetry(telemetryEntries, at: realNow)
    }

    private func loadSnapshot(
        for day: ScheduleDay,
        at date: Date,
        source: String,
        entries: inout [TelemetryEntry]
    ) -> WidgetDaySnapshot? {
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
                return nil
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
            return snapshot
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
            return nil
        }
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
            WidgetDailyTimelineContentView(
                snapshot: snapshot,
                entryDate: entry.displayDate,
                tapRenderID: entry.tapRenderID
            )
        case .unavailable:
            DailyTimelineUnavailableView(date: entry.displayDate)
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

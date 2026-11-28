import AppIntents
import Foundation

// Keep these intents in ClinicalWidget so iOS runs them directly in the widget extension
// without waking the main app, and rely on WidgetKit's automatic post-intent reload so
// each tap triggers one reload instead of two.
struct StepDailyTimelineDayIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Change Daily Timeline Day"
    nonisolated static let isDiscoverable = false

    @Parameter(title: "Day Offset")
    var delta: Int

    init() {
        self.delta = 0
    }

    init(delta: Int) {
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        DailyTimelineTapMetrics.recordIntentStart(action: delta >= 0 ? "next" : "prev")
        let now: Date
        #if DEBUG
            now = DailyTimelineWidgetState.live.effectiveNow(from: .now)
        #else
            now = .now
        #endif
        DailyTimelineWidgetState.live.step(byDays: delta, at: now)
        return .result()
    }
}

struct ResetDailyTimelineToTodayIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Return Daily Timeline to Today"
    nonisolated static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        DailyTimelineTapMetrics.recordIntentStart(action: "today")
        DailyTimelineWidgetState.live.resetToToday()
        return .result()
    }
}

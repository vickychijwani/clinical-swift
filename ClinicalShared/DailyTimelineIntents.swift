import AppIntents
import Foundation
import WidgetKit

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
        DailyTimelineWidgetState.live.step(byDays: delta, at: .now)
        WidgetCenter.shared.reloadTimelines(ofKind: ClinicalWidgetConstants.dailyTimelineKind)
        return .result()
    }
}

struct ResetDailyTimelineToTodayIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Return Daily Timeline to Today"
    nonisolated static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        DailyTimelineWidgetState.live.resetToToday()
        WidgetCenter.shared.reloadTimelines(ofKind: ClinicalWidgetConstants.dailyTimelineKind)
        return .result()
    }
}

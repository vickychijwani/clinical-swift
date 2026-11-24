// This file exists because the schedule widget and timeline invalidator aren't in the same target
nonisolated enum ClinicalWidgetConstants {
    static let scheduleKind = "in.bitehaus.clinical.schedule"
    static let dailyTimelineKind = "in.bitehaus.clinical.daily-timeline"
    static let allKinds = [scheduleKind, dailyTimelineKind]
}

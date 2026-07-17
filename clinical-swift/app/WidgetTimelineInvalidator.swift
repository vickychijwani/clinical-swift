import GRDB
import OSLog
import WidgetKit

@MainActor
final class WidgetTimelineInvalidator {
    private let observation: AnyDatabaseCancellable

    init(database: any DatabaseWriter) {
        // This is independent of GRDB's suspension notifications: those manage the writer's locks,
        // while this observation turns relevant committed changes into WidgetKit timeline reloads.
        observation = DatabaseRegionObservation(
            tracking: Table("appointments"),
            Table("patients")
        )
        .start(
            in: database,
            onError: { error in
                widgetLogger.error("Widget database observation failed: \(error)")
            },
            onChange: { _ in
                WidgetCenter.shared.reloadTimelines(
                    ofKind: ClinicalWidgetConstants.scheduleKind
                )
            }
        )

        WidgetCenter.shared.reloadTimelines(ofKind: ClinicalWidgetConstants.scheduleKind)
    }
}

nonisolated private let widgetLogger = Logger(
    subsystem: "in.bitehaus.clinical",
    category: "Widget"
)

import ClinicalModels
import Dependencies
import GRDB
import WidgetKit

@MainActor
final class WidgetTimelineInvalidator {
    private let observation: AnyDatabaseCancellable

    init(
        database: any DatabaseWriter,
        reload: @escaping @Sendable () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: ClinicalWidgetConstants.scheduleKind)
        }
    ) {
        @Dependency(\.telemetry) var telemetry
        // This is independent of GRDB's suspension notifications: those manage the writer's locks,
        // while this observation turns relevant committed changes into WidgetKit timeline reloads.
        observation = DatabaseRegionObservation(
            tracking: Table("appointments"),
            Table("patients"),
            Table("unavailableTimes")
        )
        .start(
            in: database,
            onError: { error in
                telemetry.log(
                    .error,
                    category: .widget,
                    name: "widget_observation_failed",
                    message: "Widget database observation failed",
                    error: error
                )
            },
            onChange: { _ in
                telemetry.event(category: .widget, name: "widget_timeline_invalidated")
                reload()
            }
        )

        reload()
    }
}

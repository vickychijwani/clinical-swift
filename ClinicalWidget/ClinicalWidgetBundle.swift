import SwiftUI
import WidgetKit

@main
struct ClinicalWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClinicalScheduleWidget()
        DailyTimelineWidget()
    }
}

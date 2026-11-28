import ClinicalModels
import Foundation
import SwiftUI
import WidgetKit

@main
struct ClinicalWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClinicalScheduleWidget()
        DailyTimelineWidget()
    }
}

nonisolated func flushWidgetTelemetry(_ entries: [TelemetryEntry], at date: Date) {
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

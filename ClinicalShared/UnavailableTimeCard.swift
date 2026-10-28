import ClinicalModels
import SwiftUI

struct UnavailableTimeCard: View {
    @Environment(\.appPalette) private var palette
    let block: UnavailableTime
    var isDraft = false
    var isDeemphasized = false

    var body: some View {
        ScheduleCard(
            start: block.start,
            label: block.displayLabel,
            appearance: .init(
                systemImage: "nosign",
                background: isDraft ? .draft : .color(palette[.unavailable]),
                border: isDraft ? palette[.activeBorder] : palette[.unavailableBorder],
                borderStyle: StrokeStyle(lineWidth: 2),
                timeColor: palette[.unavailableTime],
                labelColor: palette[.unavailableLabel]
            ),
            isDeemphasized: isDeemphasized
        )
    }
}

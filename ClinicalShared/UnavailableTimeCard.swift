import ClinicalModels
import SwiftUI

struct UnavailableTimeCard: View {
    @Environment(\.appPalette) private var palette
    let block: UnavailableTime
    var isAdjusting = false
    var isDeemphasized = false

    var body: some View {
        ScheduleCard(
            start: block.start,
            label: block.displayLabel,
            appearance: .init(
                systemImage: "nosign",
                background: isAdjusting ? .active : .color(palette[.unavailable]),
                border: isAdjusting ? palette[.activeBorder] : palette[.unavailableBorder],
                borderStyle: StrokeStyle(lineWidth: 2),
                timeColor: palette[.unavailableTime],
                labelColor: palette[.unavailableLabel]
            ),
            isDeemphasized: isDeemphasized
        )
    }
}

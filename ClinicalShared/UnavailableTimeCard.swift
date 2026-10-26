import ClinicalModels
import SwiftUI

struct UnavailableTimeCard: View {
    let block: UnavailableTime
    var isAdjusting = false
    var isDeemphasized = false

    var body: some View {
        ScheduleCard(
            start: block.start,
            label: block.displayLabel,
            appearance: .init(
                systemImage: "nosign",
                background: isAdjusting ? .active : .color(Color("UnavailableTimeBackground")),
                border: isAdjusting ? .accentColor.opacity(0.7) : Color("UnavailableTimeBorder"),
                borderStyle: StrokeStyle(lineWidth: 2),
                timeColor: Color("UnavailableTimeTime"),
                labelColor: Color("UnavailableTimeLabel")
            ),
            isDeemphasized: isDeemphasized
        )
    }
}

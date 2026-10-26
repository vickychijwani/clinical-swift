import ClinicalModels
import SwiftUI

struct UnavailableTimeCard: View {
    let block: UnavailableTime
    var isDeemphasized = false

    var body: some View {
        ScheduleCard(
            start: block.start,
            label: block.displayLabel,
            appearance: .init(
                systemImage: "nosign",
                background: .color(Color("UnavailableTimeBackground")),
                border: Color("UnavailableTimeBorder"),
                borderStyle: StrokeStyle(lineWidth: 2),
                timeColor: Color("UnavailableTimeTime"),
                labelColor: Color("UnavailableTimeLabel")
            ),
            isDeemphasized: isDeemphasized
        )
    }
}

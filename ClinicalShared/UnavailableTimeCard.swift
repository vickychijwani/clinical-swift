import ClinicalModels
import SwiftUI

struct UnavailableTimeCard: View {
    let block: UnavailableTime
    var isDraft = false
    var isDeemphasized = false

    var body: some View {
        ScheduleCard(
            start: block.start,
            label: block.displayLabel,
            appearance: .init(
                systemImage: "nosign",
                background: isDraft ? .draft : .color(Color("UnavailableTimeBackground")),
                border: isDraft ? .accentColor.opacity(0.7) : Color("UnavailableTimeBorder"),
                borderStyle: StrokeStyle(lineWidth: 2),
                timeColor: Color("UnavailableTimeTime"),
                labelColor: Color("UnavailableTimeLabel")
            ),
            isDeemphasized: isDeemphasized
        )
    }
}

import SwiftUI

struct UnavailableTimeCard: View {
    let block: UnavailableTime

    var body: some View {
        ScheduleCard(
            start: block.start,
            label: block.displayLabel,
            appearance: .init(
                systemImage: "nosign",
                background: Color("UnavailableTimeBackground"),
                border: Color("UnavailableTimeBorder"),
                borderStyle: StrokeStyle(lineWidth: 2),
                timeColor: Color("UnavailableTimeTime"),
                labelColor: Color("UnavailableTimeLabel")
            )
        )
    }
}

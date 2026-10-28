import ClinicalModels
import Dependencies
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import clinical_swift

@MainActor
struct ScheduleRenderingTests {
    @Test func renderMixedScheduleAndWidgetExamples() throws {
        try withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            let day = try Date("2026-10-05T00:00:00Z", strategy: .iso8601)
            let start = TimeOfDay(11, 0).on(date: day)
            let travel = UnavailableTime(label: "Travel", start: start, durationMinutes: 60)
            let appointment = Appointment(
                patientName: "Patient Name", start: start, durationMinutes: 60, status: .scheduled)
            let third = UnavailableTime(
                label: "Long label that must stay inside the card", start: start,
                durationMinutes: 45)
            let breakBlock = UnavailableTime(
                start: Bitehaus.break.start.on(date: day), durationMinutes: 15)
            let items: [TimelineItem] = [
                .appointment(appointment), .unavailableTime(travel), .unavailableTime(third),
                .unavailableTime(breakBlock),
            ]
            let directory = URL.documentsDirectory.appending(path: "UnavailableTimePreviews")
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try render(
                "timeline", directory: directory,
                content:
                    Timeline(
                        items: items, scale: TimelineScale(items: items), showsNowMarker: false
                    )
                    .frame(width: 390)
                    .background(Color("AppBackground"))
            )
            try render(
                "cards", directory: directory,
                content:
                    VStack {
                        UnavailableTimeCard(block: travel).frame(height: 60)
                        UnavailableTimeCard(block: travel, isDraft: true).frame(height: 60)
                        UnavailableTimeCard(block: third).frame(height: 24)
                        UnavailableTimeCard(block: breakBlock).frame(height: 15)
                        HStack(spacing: 0) {
                            AppointmentCard(appt: appointment)
                            UnavailableTimeCard(block: travel)
                            UnavailableTimeCard(block: third)
                        }.frame(height: 60)
                        ForEach([60, 40, 24, 15], id: \.self) { height in
                            HStack(spacing: 0) {
                                ForEach(
                                    [Appointment.Status.draft, .scheduled, .completed, .cancelled],
                                    id: \.self
                                ) { status in
                                    AppointmentCard(
                                        appt: Appointment(
                                            patientName:
                                                "Long patient name that must stay inside the card",
                                            start: start, durationMinutes: 60, status: status
                                        )
                                    )
                                }
                            }.frame(height: CGFloat(height))
                        }
                    }.padding().frame(width: 390).background(Color("AppBackground"))
            )
            let scenarios: [(String, [TimelineItem])] = [
                ("widget-dense", Array(repeating: items, count: 3).flatMap { $0 }),
                (
                    "widget-sparse",
                    [TimelineItem.appointment(appointment), .unavailableTime(travel)]
                ),
                (
                    "widget-blocks",
                    [
                        .unavailableTime(travel), .unavailableTime(third),
                        .unavailableTime(breakBlock),
                    ]
                ),
            ]
            for (name, widgetItems) in scenarios {
                let sections: [WidgetScheduleSection] = (0..<3).map { offset in
                    let sectionDate = day.addingTimeInterval(Double(offset) * 86400)
                    return WidgetScheduleSection(
                        date: sectionDate,
                        isToday: offset == 0, items: offset == 0 ? widgetItems : []
                    )
                }
                try render(
                    name, directory: directory,
                    content:
                        WidgetScheduleContentView(
                            snapshot: WidgetScheduleSnapshot(generatedAt: day, sections: sections)
                        )
                        .environment(\.calendar, Calendar.autoupdatingCurrent)
                        .padding().frame(width: 364, height: 376)
                        .background(Color("AppBackground"))
                )
            }
        }
    }

    private func render<Content: View>(_ name: String, directory: URL, content: Content) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let url = directory.appending(path: "\(name).png")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

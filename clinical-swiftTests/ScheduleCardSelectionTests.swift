import ClinicalModels
import CoreGraphics
import Dependencies
import Foundation
import SwiftUI
import Testing

@testable import clinical_swift

@MainActor
struct ScheduleCardSelectionTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func selectedCardDrawsGraphiteInnerBorderOnNativeSurface(scheme: ColorScheme) throws {
        let resting = try renderAppointmentCard(
            status: .scheduled,
            isSelected: false,
            scheme: scheme,
            isDisabled: false
        )
        let selectedEnabled = try renderAppointmentCard(
            status: .scheduled,
            isSelected: true,
            scheme: scheme,
            isDisabled: false
        )
        let selectedDisabled = try renderAppointmentCard(
            status: .scheduled,
            isSelected: true,
            scheme: scheme,
            isDisabled: true
        )

        #expect(selectedEnabled == selectedDisabled)

        // Interior surface stays native without tint or elevation.
        let interior = pixelOffset(x: 170, y: 46, width: 200)
        #expect(
            Array(selectedDisabled[interior..<interior + 4])
                == Array(resting[interior..<interior + 4])
        )

        // Top border contrasts against the native border: darker in light mode, brighter in dark mode.
        let topBorder = pixelOffset(x: 100, y: 0, width: 200)
        if scheme == .light {
            #expect(selectedDisabled[topBorder] < resting[topBorder])
        } else {
            #expect(selectedDisabled[topBorder] > resting[topBorder])
        }
    }

    @Test func selectedCompletedCardUsesFullContentOpacityOnGreenSurface() throws {
        let resting = try renderAppointmentCard(
            status: .completed,
            isSelected: false,
            scheme: .light,
            isDisabled: false
        )
        let selected = try renderAppointmentCard(
            status: .completed,
            isSelected: true,
            scheme: .light,
            isDisabled: true
        )

        // Green surface stays native.
        let interior = pixelOffset(x: 170, y: 46, width: 200)
        #expect(Array(selected[interior..<interior + 4]) == Array(resting[interior..<interior + 4]))

        // Graphite border replaces the soft green completed border.
        let topBorder = pixelOffset(x: 100, y: 0, width: 200)
        #expect(selected[topBorder] < resting[topBorder])

        // Full content opacity renders darker label ink than the resting 0.6 opacity.
        let restingDarkest = darkestRedChannel(
            in: resting, xRange: 8..<80, yRange: 20..<48, width: 200)
        let selectedDarkest = darkestRedChannel(
            in: selected, xRange: 8..<80, yRange: 20..<48, width: 200)
        #expect(selectedDarkest < restingDarkest)
    }

    @Test func selectedBackCardKeepsNaturalOverlapZOrderWhileDraftRisesAbove() throws {
        let backID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let frontID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
        let day = try Date("2026-11-20T00:00:00Z", strategy: .iso8601)
        let backStart = day.setTime(10, 0)
        let frontStart = day.setTime(10, 15)
        let items: [TimelineItem] = [
            .appointment(
                Appointment(
                    id: backID, patientName: "Back", start: backStart, durationMinutes: 60,
                    status: .scheduled)
            ),
            .appointment(
                Appointment(
                    id: frontID, patientName: "Front", start: frontStart, durationMinutes: 45,
                    status: .scheduled)
            ),
        ]

        let width = 390
        let scale = TimelineScale(items: items)
        let tuning = ScheduleCardTuning()
        let layouts = TimelineLayoutEngine(
            availableWidth: CGFloat(width),
            scale: scale,
            overlap: tuning.overlap
        ).layout(items: items)

        let backLayout = try #require(layouts.first { $0.id == .appointment(backID) })
        let frontLayout = try #require(layouts.first { $0.id == .appointment(frontID) })
        let overlap = backLayout.rect.intersection(frontLayout.rect)
        #expect(!overlap.isEmpty)
        #expect(frontLayout.zIndex > backLayout.zIndex)

        // Selection keeps natural overlap order; only drafts rise above front cards.
        #expect(
            Timeline.itemZIndex(for: backLayout, isDraft: false, itemCount: layouts.count)
                < Timeline.itemZIndex(for: frontLayout, isDraft: false, itemCount: layouts.count)
        )
        #expect(
            Timeline.itemZIndex(for: backLayout, isDraft: true, itemCount: layouts.count)
                > Timeline.itemZIndex(for: frontLayout, isDraft: false, itemCount: layouts.count)
        )

        let totalHeight = Int(
            (scale.totalHeight + Timeline.metrics.verticalPadding * 2).rounded(.up))
        let resting = try renderTimeline(
            items: items, scale: scale, tuning: tuning, selectedAppointmentID: nil,
            date: day, width: width, height: totalHeight
        )
        let selected = try renderTimeline(
            items: items, scale: scale, tuning: tuning, selectedAppointmentID: backID,
            date: day, width: width, height: totalHeight
        )
        let padY = Timeline.metrics.verticalPadding

        // Uncovered top border of the selected back card gets the darker graphite outline.
        let exposedBackBorder = pixelOffset(
            x: Int(backLayout.rect.midX),
            y: Int(padY + backLayout.rect.minY),
            width: width
        )
        #expect(selected[exposedBackBorder] < resting[exposedBackBorder])

        // Overlap area stays covered by the unselected front card (back card's right border is hidden).
        let coveredBackRightEdge = pixelOffset(
            x: Int(overlap.maxX - 1),
            y: Int(padY + overlap.midY),
            width: width
        )
        #expect(
            Array(selected[coveredBackRightEdge..<coveredBackRightEdge + 4])
                == Array(resting[coveredBackRightEdge..<coveredBackRightEdge + 4])
        )
    }

    @Test func selectedAppointmentIDFollowsActiveDetailsRouteAndScheduleState() throws {
        let start = try Date("2026-11-20T00:00:00Z", strategy: .iso8601).setTime(10, 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let router = withDependencies {
            $0.calendar = calendar
            $0.date.now = start
        } operation: {
            Router()
        }
        let patient = Patient(id: UUID(), name: "Priya", phone: nil, dob: nil, gender: nil)
        let appointment = Appointment(
            id: UUID(),
            patientName: "Priya",
            start: start,
            durationMinutes: 45,
            status: .scheduled
        )
        let details = AppointmentDetails(appointment: appointment, patient: patient)

        #expect(ScheduleView.selectedAppointmentID(for: router, hasEditor: false) == nil)

        // Active on appointment details.
        router.presentDetails(.appointment(appointment.id))
        #expect(ScheduleView.selectedAppointmentID(for: router, hasEditor: false) == appointment.id)

        // Cleared while schedule editor is active.
        #expect(ScheduleView.selectedAppointmentID(for: router, hasEditor: true) == nil)

        // Cleared on another tab.
        router.selectedTab = .patients
        #expect(ScheduleView.selectedAppointmentID(for: router, hasEditor: false) == nil)
        router.selectedTab = .schedule

        // Active during appointment completion inside the details flow.
        let presentationID = try #require(router.detailsPresentation?.id)
        let visitID = UUID()
        router.beginAppointmentCompletion(details, visitID: visitID, presentationID: presentationID)
        #expect(ScheduleView.selectedAppointmentID(for: router, hasEditor: false) == appointment.id)

        // Cleared on patient details route.
        router.presentDetails(.patient(patient.id))
        #expect(ScheduleView.selectedAppointmentID(for: router, hasEditor: false) == nil)
    }

    private func pixelOffset(x: Int, y: Int, width: Int) -> Int {
        (y * width + x) * 4
    }

    private func darkestRedChannel(
        in pixels: [UInt8],
        xRange: Range<Int>,
        yRange: Range<Int>,
        width: Int
    ) -> UInt8 {
        var darkest: UInt8 = 255
        for y in yRange {
            for x in xRange {
                darkest = min(darkest, pixels[pixelOffset(x: x, y: y, width: width)])
            }
        }
        return darkest
    }

    private func renderTimeline(
        items: [TimelineItem],
        scale: TimelineScale,
        tuning: ScheduleCardTuning,
        selectedAppointmentID: Appointment.ID?,
        date: Date,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        try withDependencies {
            $0.calendar = ClinicDate.calendar
            $0.date.now = date
        } operation: {
            let view = Timeline(
                items: items,
                scale: scale,
                showsNowMarker: false,
                selectedAppointmentID: selectedAppointmentID,
                date: date
            )
            .frame(width: CGFloat(width), height: CGFloat(height))
            .environment(\.scheduleCardTuning, tuning)
            .environment(\.colorScheme, .light)

            return try renderPixels(view, width: width, height: height)
        }
    }

    private func renderAppointmentCard(
        status: Appointment.Status,
        isSelected: Bool,
        scheme: ColorScheme,
        isDisabled: Bool
    ) throws -> [UInt8] {
        let start = try Date("2026-11-20T00:00:00Z", strategy: .iso8601).setTime(10, 0)
        let appointment = Appointment(
            patientName: "Priya",
            start: start,
            durationMinutes: 60,
            status: status
        )
        let view = AppointmentCard(
            appt: appointment,
            isSelected: isSelected,
            presentation: ScheduleCardPresentation(layout: .stacked)
        )
        .frame(width: 200, height: 60)
        .disabled(isDisabled)
        .environment(\.colorScheme, scheme)

        return try renderPixels(view, width: 200, height: 60)
    }

    private func renderPixels<V: View>(_ view: V, width: Int, height: Int) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }
}

import ClinicalModels
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import clinical_swift

@MainActor
struct TimelineOverlapRenderingTests {
    @Test func breakCrossingCompactStackMatchesMeasuredVariantWithoutClipping() throws {
        let backID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let frontID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let items = [
            appointment(
                id: backID, name: "Kabir Malhotra", startHour: 12, startMinute: 20, duration: 60),
            appointment(
                id: frontID, name: "Priya Narayanan", startHour: 12, startMinute: 20, duration: 60),
        ]
        let scale = TimelineScale(items: items)
        let layouts = TimelineLayoutEngine(
            availableWidth: 402,
            scale: scale,
            overlap: .init(mode: .textAware, separation: .halo, stripWidth: 18, haloWidth: 2)
        ).layout(items: items)
        let back = try #require(layouts.first { $0.id == .appointment(backID) })
        #expect(back.presentation.layout == .compactStacked)
        #expect(back.contentTrailingInset > 0)

        let cardSize = back.rect.size
        let fencedCompact = try renderCard(
            item: back.item,
            size: cardSize,
            contentTrailingInset: back.contentTrailingInset,
            presentation: back.presentation
        )
        let unfencedCompact = try renderCard(
            item: back.item,
            size: cardSize,
            contentTrailingInset: 0,
            presentation: back.presentation
        )
        let regularStacked = try renderCard(
            item: back.item,
            size: cardSize,
            contentTrailingInset: back.contentTrailingInset,
            presentation: ScheduleCardPresentation(
                layout: .stacked, usesCompactTime: back.presentation.usesCompactTime)
        )

        #expect(fencedCompact == unfencedCompact)
        #expect(fencedCompact != regularStacked)
    }

    @Test func touchingShortOverlapGroupsDoNotClipPrecedingGroupText() throws {
        let firstBackID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let firstFrontID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let secondBackID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let secondFrontID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        let firstGroup = [
            appointment(id: firstBackID, name: "Ana", startHour: 9, startMinute: 0, duration: 15),
            appointment(id: firstFrontID, name: "Raj", startHour: 9, startMinute: 0, duration: 15),
        ]
        let secondGroup = [
            appointment(id: secondBackID, name: "Mia", startHour: 9, startMinute: 15, duration: 15),
            appointment(
                id: secondFrontID, name: "Kabir Malhotra", startHour: 9, startMinute: 15,
                duration: 15),
        ]
        let allItems = firstGroup + secondGroup
        let scale = TimelineScale(items: allItems)
        let width: CGFloat = 402
        var haloTuning = ScheduleCardTuning()
        haloTuning.overlap.separation = .halo
        var flatTuning = ScheduleCardTuning()
        flatTuning.overlap.separation = .flat
        let layouts = TimelineLayoutEngine(
            availableWidth: width, scale: scale, overlap: haloTuning.overlap
        ).layout(items: allItems)
        #expect(layouts.first { $0.id == .appointment(firstFrontID) }?.isOverlappingFront == true)
        #expect(layouts.first { $0.id == .appointment(secondFrontID) }?.isOverlappingFront == true)
        // Render only the top 60 pt of the timeline covering 9:00–10:00 at 2x scale.
        let renderHeight: CGFloat = 60
        let pixelScale = 2

        let firstGroupOnly = try renderTimeline(
            items: firstGroup, scale: scale, width: width, height: renderHeight,
            pixelScale: pixelScale, tuning: haloTuning)
        let withSecondGroup = try renderTimeline(
            items: allItems, scale: scale, width: width, height: renderHeight,
            pixelScale: pixelScale, tuning: haloTuning)
        let withSecondGroupFlat = try renderTimeline(
            items: allItems, scale: scale, width: width, height: renderHeight,
            pixelScale: pixelScale, tuning: flatTuning)

        let bytesPerRow = Int(width) * pixelScale * 4
        let firstGroupEndRow = Int(Timeline.metrics.verticalPadding + 15) * pixelScale
        let firstGroupSlice = 0..<(firstGroupEndRow * bytesPerRow)
        #expect(
            Array(firstGroupOnly[firstGroupSlice]) == Array(withSecondGroup[firstGroupSlice]))

        // Confirm the second group still renders its horizontal halo separation.
        let secondGroupEndRow = Int(Timeline.metrics.verticalPadding + 30) * pixelScale
        let secondGroupSlice = (firstGroupEndRow * bytesPerRow)..<(secondGroupEndRow * bytesPerRow)
        #expect(
            Array(withSecondGroup[secondGroupSlice])
                != Array(withSecondGroupFlat[secondGroupSlice]))
    }

    private func renderCard(
        item: TimelineItem,
        size: CGSize,
        contentTrailingInset: CGFloat,
        presentation: ScheduleCardPresentation
    ) throws -> [UInt8] {
        let pixelWidth = Int(ceil(size.width)) * 2
        let pixelHeight = Int(ceil(size.height)) * 2
        let view = ScheduleItemCard(
            item: item,
            contentTrailingInset: contentTrailingInset,
            presentation: presentation
        )
        .frame(width: size.width, height: size.height)
        .background(AppColor.canvas)
        return try renderPixels(view, pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: 2)
    }

    private func renderTimeline(
        items: [TimelineItem],
        scale: TimelineScale,
        width: CGFloat,
        height: CGFloat,
        pixelScale: Int,
        tuning: ScheduleCardTuning
    ) throws -> [UInt8] {
        let view = Timeline(items: items, scale: scale, showsNowMarker: false)
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .background(AppColor.canvas)
            .environment(\.scheduleCardTuning, tuning)
        return try renderPixels(
            view,
            pixelWidth: Int(width) * pixelScale,
            pixelHeight: Int(height) * pixelScale,
            scale: CGFloat(pixelScale)
        )
    }

    private func renderPixels<Content: View>(
        _ content: Content,
        pixelWidth: Int,
        pixelHeight: Int,
        scale: CGFloat
    ) throws -> [UInt8] {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: pixelWidth * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        return pixels
    }

    private func appointment(
        id: UUID,
        name: String,
        startHour: Int,
        startMinute: Int,
        duration: Int
    ) -> TimelineItem {
        .appointment(
            Appointment(
                id: id,
                patientName: name,
                start: Date(timeIntervalSinceReferenceDate: 804_600_000)
                    .setTime(startHour, startMinute),
                durationMinutes: duration,
                status: .scheduled
            )
        )
    }
}

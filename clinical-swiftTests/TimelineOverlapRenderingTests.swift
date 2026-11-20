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
            overlap: .init(mode: .textAware, stripWidth: 18)
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

    @Test func overlapShadowKeepsTranslucentFillUnchangedAndDrawsShadowOutside() throws {
        var shadowTuning = ScheduleCardTuning()
        // A stronger shadow makes an interior leak clear even with a translucent surface.
        shadowTuning.surfaceOpacity = 0.55
        shadowTuning.overlap.separation = .shadow
        shadowTuning.overlap.shadowOpacity = 0.8
        shadowTuning.overlap.shadowRadius = 4

        var flatTuning = shadowTuning
        flatTuning.overlap.separation = .flat

        let shadowed = try renderOverlapSeparation(isActive: true, tuning: shadowTuning)
        let flat = try renderOverlapSeparation(isActive: true, tuning: flatTuning)
        let inactive = try renderOverlapSeparation(isActive: false, tuning: shadowTuning)

        let centerPixel = (50 * 200 + 100) * 4
        #expect(Array(shadowed[centerPixel..<centerPixel + 4]) == Array(flat[centerPixel..<centerPixel + 4]))
        let outsideBelowPixel = (78 * 200 + 100) * 4
        #expect(shadowed[outsideBelowPixel] < flat[outsideBelowPixel])
        #expect(inactive == flat)
    }

    private func renderOverlapSeparation(
        isActive: Bool,
        tuning: ScheduleCardTuning
    ) throws -> [UInt8] {
        let view = Color.white.opacity(tuning.surfaceOpacity)
            .frame(width: 120, height: 48)
            .clipShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
            .modifier(TimelineCardOverlapSeparation(isActive: isActive))
            .environment(\.scheduleCardTuning, tuning)
            .frame(width: 200, height: 100)
            .background(.gray)
        return try renderPixels(view, pixelWidth: 200, pixelHeight: 100, scale: 1)
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

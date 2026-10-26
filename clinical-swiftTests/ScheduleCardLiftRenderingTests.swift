import CoreGraphics
import SwiftUI
import Testing

@testable import clinical_swift

@MainActor
struct ScheduleCardLiftRenderingTests {
    @Test func liftKeepsTranslucentFillUnchangedAndDrawsShadowOutside() throws {
        var tuning = ScheduleCardTuning()
        // A stronger shadow makes an interior leak clear even with a translucent surface.
        tuning.surfaceOpacity = 0.55
        tuning.lift.shadowOpacity = 0.8
        let resting = try render(isPressed: false, tuning: tuning)
        let pressed = try render(isPressed: true, tuning: tuning)

        #expect(
            Array(resting[centerPixel..<centerPixel + 4])
                == Array(pressed[centerPixel..<centerPixel + 4]))
        let outsideRows = [20, 80]
        #expect(
            outsideRows.contains { y in pressed[(y * 200 + 100) * 4] < resting[(y * 200 + 100) * 4]
            })
    }

    private var centerPixel: Int { (50 * 200 + 100) * 4 }

    private func render(isPressed: Bool, tuning: ScheduleCardTuning) throws -> [UInt8] {
        let renderer = ImageRenderer(
            content: Color.white.opacity(tuning.surfaceOpacity)
                .frame(width: 120, height: 48)
                .clipShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
                .modifier(ScheduleCardLift(isPressed: isPressed))
                .environment(\.scheduleCardTuning, tuning)
                .frame(width: 200, height: 100)
                .background(.gray))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: 200 * 100 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress, width: 200, height: 100,
                    bitsPerComponent: 8, bytesPerRow: 200 * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        return pixels
    }
}

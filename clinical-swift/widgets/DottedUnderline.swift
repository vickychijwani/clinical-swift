import Foundation
import SwiftUI

extension View {
    func dottedUnderline() -> some View {
        modifier(DottedUnderline(color: .foreground, spacing: 0))
    }
}

private struct DottedUnderline: ViewModifier {
    var color: ForegroundStyle
    var spacing: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                Line()
                    .stroke(
                        .foreground,
                        style: StrokeStyle(
                            lineWidth: 1,
                            lineCap: .round,
                            dash: [0, 3]
                        )
                    )
                    .frame(height: 1)
                    .offset(y: spacing)
            }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

import CoreGraphics
import Foundation

/// Exact 2D geometric verifier enforcing content visibility and continuous time-edge visibility.
nonisolated enum TimelineLayoutValidator {
    enum Violation: Equatable, CustomStringConvertible, Sendable {
        case outOfBounds(TimelineItem.ID)
        case nonPositiveWidth(TimelineItem.ID)
        case contentObscured(covered: TimelineItem.ID, by: TimelineItem.ID)
        case timeEdgeObscured(covered: TimelineItem.ID, by: TimelineItem.ID)
        case contentFencedOut(TimelineItem.ID)

        var description: String {
            switch self {
            case .outOfBounds(let id):
                "Card \(id.sortKey) extends outside timeline bounds"
            case .nonPositiveWidth(let id):
                "Card \(id.sortKey) has non-positive width"
            case .contentObscured(let covered, let by):
                "Card \(covered.sortKey) content is obscured by \(by.sortKey)"
            case .timeEdgeObscured(let covered, let by):
                "Card \(covered.sortKey) continuous time-edge strip is obscured by \(by.sortKey)"
            case .contentFencedOut(let id):
                "Card \(id.sortKey) has no remaining content width after trailing inset"
            }
        }
    }

    private static let epsilon: CGFloat = 0.01

    static func validate(
        entries: [ValidatedLayoutEntry],
        bounds: HorizontalSpan,
        stripWidth: CGFloat
    ) -> [Violation] {
        let stripWidth = max(stripWidth, 0)
        let sorted = entries.sorted { $0.layoutInfo.zIndex < $1.layoutInfo.zIndex }
        var violations: [Violation] = []

        for index in sorted.indices {
            let lower = sorted[index]
            let lowerRect = lower.layoutInfo.rect

            if lowerRect.width <= epsilon {
                violations.append(.nonPositiveWidth(lower.layoutInfo.id))
                continue
            }
            if lowerRect.minX < bounds.min - epsilon || lowerRect.maxX > bounds.max + epsilon {
                violations.append(.outOfBounds(lower.layoutInfo.id))
            }
            if lowerRect.width - lower.layoutInfo.contentTrailingInset <= epsilon {
                violations.append(.contentFencedOut(lower.layoutInfo.id))
            }

            let requiredStrip = min(stripWidth, lowerRect.width)
            let leftStrip = CGRect(
                x: lowerRect.minX,
                y: lowerRect.minY,
                width: requiredStrip,
                height: lowerRect.height
            )

            for upperIndex in (index + 1)..<sorted.count {
                let upper = sorted[upperIndex]
                guard upper.layoutInfo.zIndex > lower.layoutInfo.zIndex else { continue }

                let upperRect = upper.layoutInfo.rect
                if intersects(lower.contentRect, upperRect) {
                    violations.append(
                        .contentObscured(
                            covered: lower.layoutInfo.id,
                            by: upper.layoutInfo.id
                        )
                    )
                }

                if intersects(leftStrip, upperRect) {
                    violations.append(
                        .timeEdgeObscured(
                            covered: lower.layoutInfo.id,
                            by: upper.layoutInfo.id
                        )
                    )
                }
            }
        }

        return violations
    }

    private static func intersects(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = lhs.intersection(rhs)
        return !overlap.isNull && overlap.width > epsilon && overlap.height > epsilon
    }
}

nonisolated struct HorizontalSpan: Equatable, Sendable {
    let min: CGFloat
    let max: CGFloat

    var width: CGFloat { Swift.max(max - min, 0) }
}

struct ValidatedLayoutEntry {
    let layoutInfo: TimelineItemLayoutInfo
    let contentRect: CGRect
}

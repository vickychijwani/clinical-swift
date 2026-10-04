import CoreGraphics

nonisolated struct WidgetLayoutConfiguration: Equatable, Sendable {
    let headerHeight: CGFloat
    let headerToRowsSpacing: CGFloat
    let rowSpacing: CGFloat
    let sectionSpacing: CGFloat
    let minimumRowHeight: CGFloat
    let standardRowHeight: CGFloat
    let maximumRowHeight: CGFloat

    static let standard = Self(
        headerHeight: 20,
        headerToRowsSpacing: 8,
        rowSpacing: 8,
        sectionSpacing: 12,
        minimumRowHeight: 24,
        standardRowHeight: 26,
        maximumRowHeight: 28
    )
}

nonisolated enum WidgetPlannedRow: Equatable, Sendable {
    case item(Int)
    case empty
    case overflow(hiddenCount: Int)
}

nonisolated struct WidgetPlannedSection: Equatable, Sendable {
    let sourceIndex: Int
    let rows: [WidgetPlannedRow]
}

nonisolated struct WidgetLayoutPlan: Equatable, Sendable {
    let sections: [WidgetPlannedSection]
    let rowHeight: CGFloat
    let contentHeight: CGFloat
    let trailingSpace: CGFloat
}

nonisolated struct WidgetLayoutPlanner: Sendable {
    let configuration: WidgetLayoutConfiguration

    init(configuration: WidgetLayoutConfiguration = .standard) {
        self.configuration = configuration
    }

    func plan(
        sections: [WidgetScheduleSection],
        availableHeight: CGFloat
    ) -> WidgetLayoutPlan {
        let sectionLimit = min(sections.count, 3)
        guard sectionLimit > 0, availableHeight > 0 else {
            return WidgetLayoutPlan(
                sections: [],
                rowHeight: configuration.standardRowHeight,
                contentHeight: 0,
                trailingSpace: max(availableHeight, 0)
            )
        }

        for sectionCount in stride(from: sectionLimit, through: 1, by: -1) {
            let leadingSections = (0..<(sectionCount - 1)).map { index in
                WidgetPlannedSection(
                    sourceIndex: index,
                    rows: completeRows(for: sections[index])
                )
            }
            let lastIndex = sectionCount - 1

            for lastRows in lastSectionRowOptions(for: sections[lastIndex]) {
                let plannedSections =
                    leadingSections + [
                        WidgetPlannedSection(sourceIndex: lastIndex, rows: lastRows)
                    ]
                let rowCount = plannedSections.reduce(0) { $0 + $1.rows.count }
                guard rowCount > 0 else { continue }

                let fixedHeight = fixedHeight(for: plannedSections)
                let availableRowHeight = (availableHeight - fixedHeight) / CGFloat(rowCount)
                guard availableRowHeight >= configuration.minimumRowHeight else { continue }

                let rowHeight = min(availableRowHeight, configuration.maximumRowHeight)
                let contentHeight = fixedHeight + CGFloat(rowCount) * rowHeight
                return WidgetLayoutPlan(
                    sections: plannedSections,
                    rowHeight: rowHeight,
                    contentHeight: contentHeight,
                    trailingSpace: max(availableHeight - contentHeight, 0)
                )
            }
        }

        let fallback = WidgetPlannedSection(
            sourceIndex: 0,
            rows: sections[0].items.isEmpty
                ? [.empty] : [.overflow(hiddenCount: sections[0].items.count)]
        )
        let contentHeight = min(
            availableHeight,
            configuration.headerHeight
                + configuration.headerToRowsSpacing
                + configuration.minimumRowHeight
        )
        return WidgetLayoutPlan(
            sections: [fallback],
            rowHeight: max(
                contentHeight - configuration.headerHeight
                    - configuration.headerToRowsSpacing,
                0
            ),
            contentHeight: contentHeight,
            trailingSpace: max(availableHeight - contentHeight, 0)
        )
    }

    func height(for section: WidgetPlannedSection, rowHeight: CGFloat) -> CGFloat {
        configuration.headerHeight
            + configuration.headerToRowsSpacing
            + CGFloat(section.rows.count) * rowHeight
            + CGFloat(max(section.rows.count - 1, 0)) * configuration.rowSpacing
    }

    private func completeRows(for section: WidgetScheduleSection) -> [WidgetPlannedRow] {
        guard !section.items.isEmpty else { return [.empty] }
        return section.items.indices.map(WidgetPlannedRow.item)
    }

    private func lastSectionRowOptions(
        for section: WidgetScheduleSection
    ) -> [[WidgetPlannedRow]] {
        guard !section.items.isEmpty else { return [[.empty]] }

        return stride(
            from: section.items.count,
            through: 0,
            by: -1
        ).map { visibleCount in
            let visibleRows = (0..<visibleCount).map(WidgetPlannedRow.item)
            guard visibleCount < section.items.count else { return visibleRows }
            return visibleRows + [
                .overflow(hiddenCount: section.items.count - visibleCount)
            ]
        }
    }

    private func fixedHeight(for sections: [WidgetPlannedSection]) -> CGFloat {
        let rowSpacing = sections.reduce(CGFloat.zero) { result, section in
            result + CGFloat(max(section.rows.count - 1, 0)) * configuration.rowSpacing
        }
        return CGFloat(sections.count)
            * (configuration.headerHeight + configuration.headerToRowsSpacing)
            + CGFloat(max(sections.count - 1, 0)) * configuration.sectionSpacing
            + rowSpacing
    }
}

import SwiftUI

struct ScheduleEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .styleSectionTitle()

            content
        }
    }
}

struct ScheduleTimeSection: View {
    @Binding var start: Date

    var body: some View {
        ScheduleEditorSection(title: "Start Time") {
            DatePicker(
                "Start time",
                selection: $start,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
    }
}

struct ScheduleDurationSection: View {
    nonisolated static let options = [15, 30, 45, 60, 90, 120]
    @Binding var durationMinutes: Minutes

    var body: some View {
        ScheduleEditorSection(title: "Duration") {
            Picker("Duration", selection: $durationMinutes) {
                ForEach(ScheduleDurationSection.options, id: \.self) { minutes in
                    Text(durationLabel(for: minutes))
                        .tag(minutes)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func durationLabel(for minutes: Minutes) -> String {
        switch minutes {
        case 60:
            "1h"
        case 90:
            "1.5h"
        case 120:
            "2h"
        default:
            "\(minutes)m"
        }
    }
}

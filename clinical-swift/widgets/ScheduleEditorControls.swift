import ClinicalModels
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

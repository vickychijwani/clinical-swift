import SQLiteData
import SwiftUI

struct PatientDetailsView: View {
    @FetchOne private var row: PatientListRow?

    init(id: Patient.ID) {
        _row = FetchOne(patientDetailsQuery(id: id))
    }

    var body: some View {
        Group {
            if let details = row?.item {
                ViewPatientView(details: details)
            } else {
                ContentUnavailableView(
                    "Patient Unavailable",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("This patient no longer exists.")
                )
            }
        }
        .navigationTitle("Patient Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    NavigationStack {
        PatientDetailsView(id: samplePatients[0].id)
    }
}

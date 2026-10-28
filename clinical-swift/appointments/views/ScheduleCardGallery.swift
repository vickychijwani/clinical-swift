#if DEBUG
    import ClinicalModels
    import ClinicalPersistence
    import Dependencies
    import SQLiteData
    import SwiftUI

    #Preview("Schedule cards · Light") {
        ScheduleCardGallery()
            .preferredColorScheme(.light)
    }

    #Preview("Schedule cards · Dark") {
        ScheduleCardGallery()
            .preferredColorScheme(.dark)
    }

    #Preview("Appointment draft") {
        ScheduleCardGallery(state: .appointmentDraft)
    }

    #Preview("Unavailable time draft") {
        ScheduleCardGallery(state: .unavailableTimeDraft)
    }

    /// Use the live canvas to select, drag, and resize cards in the real Schedule page.
    private struct ScheduleCardGallery: View {
        enum Mode {
            case overview, appointmentDraft, unavailableTimeDraft
        }

        @State private var router: Router
        private let backup: BackupCoordinator

        init(state: Mode = .overview) {
            // Force preview storage so this gallery cannot open the clinic database.
            let database = try! prepareDependencies {
                $0.context = .preview
                let database = try appDatabase()
                $0.defaultDatabase = database
                return database
            }
            let date = Date.now
            let patients = [
                Patient(name: "Completed · Anjali Desai", createdDate: date),
                Patient(name: "Scheduled · Priya Narayanan", createdDate: date),
                Patient(name: "Overlap · Kabir Malhotra", createdDate: date),
                Patient(name: "Short · Meera Subramanian", createdDate: date),
            ]
            let appointments = [
                Appointment(
                    patientName: patients[0].displayName, start: date.setTime(9, 0),
                    durationMinutes: 60, status: .completed),
                Appointment(
                    patientName: patients[1].displayName, start: date.setTime(10, 0),
                    durationMinutes: 60, status: .scheduled),
                Appointment(
                    patientName: patients[2].displayName, start: date.setTime(10, 30),
                    durationMinutes: 45, status: .scheduled),
                Appointment(
                    patientName: patients[3].displayName, start: date.setTime(11, 15),
                    durationMinutes: 15, status: .scheduled),
            ]
            let blocks = [
                UnavailableTime(
                    label: "Unavailable · Travel", start: date.setTime(11, 30),
                    durationMinutes: 60),
                UnavailableTime(start: date.setTime(12, 30), durationMinutes: 30),
            ]
            try! database.write { db in
                for patient in patients {
                    try PatientRecord.insert { PatientRecord(patient) }.execute(db)
                }
                for (patient, appointment) in zip(patients, appointments) {
                    let record = try AppointmentRecord.persisted(
                        id: appointment.id, patientID: patient.id, start: appointment.start,
                        durationMinutes: appointment.durationMinutes, status: appointment.status,
                        createdAt: date, updatedAt: date)
                    try AppointmentRecord.insert { record }.execute(db)
                }
                for block in blocks {
                    try UnavailableTimeRecord.insert {
                        UnavailableTimeRecord(
                            id: block.id, label: block.label, start: block.start,
                            durationMinutes: block.durationMinutes, createdAt: date, updatedAt: date
                        )
                    }.execute(db)
                }
                // Preview records must not create pending work for the device calendar.
                try AppointmentCalendarSyncRecord.delete().execute(db)
                try UnavailableTimeCalendarSyncRecord.delete().execute(db)
            }

            let router = Router()
            router.selectScheduleDate(date)
            switch state {
            case .overview:
                break
            case .appointmentDraft:
                router.requestAppointmentEdit(
                    AppointmentDetails(appointment: appointments[1], patient: patients[1]))
            case .unavailableTimeDraft:
                router.requestUnavailableTimeEdit(blocks[0])
            }
            _router = State(initialValue: router)
            backup = BackupCoordinator(
                database: database,
                store: BackupStateStore(
                    directory: .temporaryDirectory.appending(path: UUID().uuidString)))
        }

        var body: some View {
            // Keep the real navigation, toolbar, date strip, tabs, and editing behavior.
            ContentView(router: router)
                .environment(backup)
        }
    }
#endif

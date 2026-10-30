import ClinicalModels
import ClinicalPersistence
import Foundation
import GRDB
import OSLog
import SQLiteData

func appDatabase(seedSamples: Bool = false, recoverySafe: Bool = false) throws -> any DatabaseWriter
{
    @Dependency(\.context) var context
    var configuration = clinicalDatabaseConfiguration()

    #if DEBUG
        configuration.prepareDatabase { db in
            db.trace(options: .profile) {
                switch context {
                case .live:
                    databaseLogger.debug("\($0.expandedDescription)")
                case .preview:
                    print("\($0.expandedDescription)")
                case .test:
                    break
                }
            }
        }
    #endif

    let database: any DatabaseWriter
    if context == .live {
        database = try ClinicalSharedDatabase.openWriter(
            at: ClinicalSharedDatabase.databaseURL(),
            configuration: configuration,
            setup: { try databaseMigrator(allowDebugErasure: !recoverySafe).migrate($0) }
        )
    } else {
        database = try defaultDatabase(configuration: configuration)
        try migrateDatabase(database)
    }
    databaseLogger.debug("open '\(database.path)'")

    #if DEBUG
        if seedSamples, !recoverySafe, context != .test {
            try database.seedSampleDataIfNeeded()
        }
    #endif

    return database
}

nonisolated private let databaseLogger = Logger(
    subsystem: "in.bitehaus.clinical-swift",
    category: "Database"
)

#if DEBUG
    extension DatabaseWriter {
        func seedSampleDataIfNeeded() throws {
            try write { db in
                let patientCount = try PatientRecord.count().fetchOne(db) ?? 0
                guard patientCount == 0 else {
                    return
                }

                var patients = samplePatients
                for appointment in sampleAppointments
                where !patients.contains(where: { $0.name == appointment.patientName }) {
                    patients.append(
                        Patient(
                            name: appointment.patientName,
                            createdDate: appointment.start
                        ))
                }

                for patient in patients {
                    try PatientRecord.insert { PatientRecord(patient) }
                        .execute(db)
                }

                let patientIDsByName = Dictionary(
                    uniqueKeysWithValues: patients.compactMap { patient in
                        patient.name.map { ($0, patient.id) }
                    }
                )

                let block = UnavailableTimeRecord(
                    id: UUID(), label: "Travel", start: Date.now.setTime(11, 0),
                    durationMinutes: 60, createdAt: .now, updatedAt: .now
                )
                try UnavailableTimeRecord.insert { block }.execute(db)
                try UnavailableTimeCalendarSyncRecord
                    .where { $0.unavailableTimeID.eq(block.id) }
                    .delete().execute(db)

                for appointment in sampleAppointments {
                    guard let patientID = patientIDsByName[appointment.patientName] else {
                        continue
                    }
                    let record = try AppointmentRecord.persisted(
                        id: appointment.id,
                        patientID: patientID,
                        start: appointment.start,
                        durationMinutes: appointment.durationMinutes,
                        status: appointment.status,
                        createdAt: appointment.start,
                        updatedAt: appointment.start
                    )
                    try AppointmentRecord.insert {
                        record
                    }
                    .execute(db)

                    // Debug seed rows demonstrate the UI; they are not clinic appointments and
                    // must never be exported into the device owner's Bitehaus Debug calendar.
                    try AppointmentCalendarSyncRecord
                        .where { $0.appointmentID.eq(appointment.id) }
                        .delete()
                        .execute(db)
                }
            }
            try seedSamplePaymentsIfNeeded()
        }
    }
#endif

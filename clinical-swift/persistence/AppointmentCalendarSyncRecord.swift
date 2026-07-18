import Foundation
import SQLiteData

/// Device-local linkage and durable pending work for the one-way EventKit integration.
/// This table must not participate in any future cross-device database sync.
@Table("appointmentCalendarSync")
nonisolated struct AppointmentCalendarSyncRecord: Equatable, Sendable {
    @Column(primaryKey: true)
    let appointmentID: Appointment.ID
    var eventIdentifier: String?
    var eventStart: Date?
    var needsSync: Bool
    var revision: Int
    var createdAt: Date
    var updatedAt: Date
}

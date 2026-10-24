import ClinicalModels
import Foundation
import SQLiteData

/// Device-local linkage and durable pending work for the one-way EventKit integration.
/// This table must not participate in any future cross-device database sync.
@Table("appointmentCalendarSync")
public nonisolated struct AppointmentCalendarSyncRecord: Equatable, Sendable {
    @Column(primaryKey: true)
    public let appointmentID: Appointment.ID
    public var eventIdentifier: String?
    public var eventStart: Date?
    public var needsSync: Bool
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date
}

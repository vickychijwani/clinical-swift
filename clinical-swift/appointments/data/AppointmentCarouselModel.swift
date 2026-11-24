import ClinicalModels
import ClinicalPersistence
import CoreGraphics
import Dependencies
import Foundation
import SQLiteData

/// Pure geometry and gesture rules for the 3-item horizontal appointment card carousel.
nonisolated enum AppointmentCarouselMotion {
    /// Horizontal space on each side of the centered card inside the unscaled tray width.
    static let horizontalInset: CGFloat = 24
    /// Gap between adjacent cards in unscaled tray coordinates.
    static let itemGap: CGFloat = 12
    static let commitDistanceFraction: CGFloat = 0.30
    static let commitPredictedFraction: CGFloat = 0.45
    static let rubberBandCoefficient: CGFloat = 0.55
    static let boundaryLimitFraction: CGFloat = 0.28
    static let singleDragOverflowLimitFraction: CGFloat = 0.15

    static func cardWidth(in containerWidth: CGFloat) -> CGFloat {
        max(0, containerWidth - 2 * horizontalInset)
    }

    static func step(in containerWidth: CGFloat, scale: CGFloat) -> CGFloat {
        (cardWidth(in: containerWidth) + itemGap) * scale
    }

    /// Keep at most 3 items mounted (`previous`, `current`, `next`).
    static func windowIndices(around index: Int, count: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let clamped = min(max(index, 0), count - 1)
        let lower = max(0, clamped - 1)
        let upper = min(count, clamped + 2)
        return lower..<upper
    }

    /// Standard iOS-style asymptotic rubber-band damping.
    static func rubberBand(offset: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0, offset != 0 else { return 0 }
        let distance = abs(offset)
        let damped =
            (rubberBandCoefficient * distance * limit)
            / (limit + rubberBandCoefficient * distance)
        return offset < 0 ? -damped : damped
    }

    /// Resolves the track scroll position during a drag from `anchorIndex`.
    /// Applies rubber-band resistance past the first/last appointment and beyond one full step
    /// so the 3-item window never exposes an unrendered slot mid-drag.
    static func dragPosition(
        anchorIndex: Int,
        translation: CGFloat,
        count: Int,
        step: CGFloat
    ) -> CGFloat {
        guard count > 0, step > 0 else { return 0 }
        let clampedAnchor = min(max(anchorIndex, 0), count - 1)
        let boundedTranslation: CGFloat
        if abs(translation) > step {
            let sign: CGFloat = translation < 0 ? -1 : 1
            let excess = abs(translation) - step
            boundedTranslation =
                sign * (step + rubberBand(offset: excess, limit: step * singleDragOverflowLimitFraction))
        } else {
            boundedTranslation = translation
        }

        let anchorPosition = CGFloat(clampedAnchor) * step
        let raw = anchorPosition - boundedTranslation
        let maxPosition = CGFloat(max(count - 1, 0)) * step

        if raw < 0 {
            return rubberBand(offset: raw, limit: step * boundaryLimitFraction)
        }
        if raw > maxPosition {
            return maxPosition + rubberBand(offset: raw - maxPosition, limit: step * boundaryLimitFraction)
        }
        return raw
    }

    /// Chooses the settled appointment index on finger release (at most one step per swipe).
    static func targetIndex(
        currentIndex: Int,
        count: Int,
        step: CGFloat,
        translation: CGFloat,
        predictedTranslation: CGFloat
    ) -> Int {
        guard count > 1, step > 0 else { return max(0, min(currentIndex, count - 1)) }
        let clamped = min(max(currentIndex, 0), count - 1)

        if translation < 0, clamped + 1 < count {
            let commitsByDistance = -translation > step * commitDistanceFraction
            let commitsByVelocity =
                predictedTranslation < 0 && -predictedTranslation > step * commitPredictedFraction
            if commitsByDistance || commitsByVelocity {
                return clamped + 1
            }
        } else if translation > 0, clamped > 0 {
            let commitsByDistance = translation > step * commitDistanceFraction
            let commitsByVelocity =
                predictedTranslation > 0 && predictedTranslation > step * commitPredictedFraction
            if commitsByDistance || commitsByVelocity {
                return clamped - 1
            }
        }
        return clamped
    }
}

/// Orders a day's navigable appointments to match visual timeline order:
/// top-to-bottom by start time, then left-to-right as laid out by `TimelineLayoutEngine`.
enum AppointmentCarouselOrder {
    private static let xTieTolerance: CGFloat = 0.001

    static func orderedAppointments(
        appointments: [AppointmentDetails],
        unavailableTimes: [UnavailableTime],
        availableWidth: CGFloat,
        overlap: ScheduleCardTuning.Overlap
    ) -> [AppointmentDetails] {
        let eligible = appointments.filter {
            $0.appointment.status == .scheduled || $0.appointment.status == .completed
        }
        guard eligible.count > 1 else { return eligible }

        let timelineItems =
            eligible.map { TimelineItem.appointment($0.appointment) }
            + unavailableTimes.map(TimelineItem.unavailableTime)
        let scale = TimelineScale(items: timelineItems)
        let engine = TimelineLayoutEngine(
            availableWidth: max(availableWidth, 320),
            scale: scale,
            overlap: overlap,
            assertOnFallback: false
        )
        let layouts = engine.layout(items: timelineItems)

        var xByAppointmentID: [Appointment.ID: CGFloat] = [:]
        xByAppointmentID.reserveCapacity(eligible.count)
        for info in layouts {
            if case .appointment(let appointment) = info.item {
                xByAppointmentID[appointment.id] = info.rect.minX
            }
        }

        return eligible.sorted { lhs, rhs in
            if lhs.appointment.start != rhs.appointment.start {
                return lhs.appointment.start < rhs.appointment.start
            }
            let lhsX = xByAppointmentID[lhs.id] ?? .greatestFiniteMagnitude
            let rhsX = xByAppointmentID[rhs.id] ?? .greatestFiniteMagnitude
            if abs(lhsX - rhsX) > xTieTolerance {
                return lhsX < rhsX
            }
            if lhs.appointment.durationMinutes != rhs.appointment.durationMinutes {
                return lhs.appointment.durationMinutes > rhs.appointment.durationMinutes
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

@MainActor @Observable
final class AppointmentDayCarouselModel {
    @ObservationIgnored @Dependency(\.appointmentStatusClient) private var statusClient
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.telemetry) private var telemetry
    @ObservationIgnored @FetchOne private var initialRow: AppointmentPatientSelection?
    @ObservationIgnored @FetchAll(AppointmentPatientSelection.none) private var dayAppointmentRows
    @ObservationIgnored @FetchAll(UnavailableTimeRecord.none) private var dayUnavailableTimeRows
    @ObservationIgnored private var cachedOrderKey: OrderCacheKey?
    @ObservationIgnored private var cachedOrderedAppointments: [AppointmentDetails] = []

    private(set) var currentAppointmentID: Appointment.ID
    private(set) var loadedDay: Date?
    private(set) var hasResolvedInitialDetails = false
    private(set) var isUpdatingStatus = false
    private(set) var errorMessage: String?

    init(initialAppointmentID: Appointment.ID, initialScheduleDate: Date) {
        self.currentAppointmentID = initialAppointmentID
        let day = ClinicDate.day(initialScheduleDate)
        self.loadedDay = day
        _initialRow = FetchOne(appointmentDetailsQuery(id: initialAppointmentID))
        _dayAppointmentRows = FetchAll(querySchedule(selectedDate: day))
        _dayUnavailableTimeRows = FetchAll(
            unavailableTimesQuery(centeredOn: day, dayRadius: 1)
        )
    }

    var initialDetails: AppointmentDetails? {
        initialRow?.details
    }

    func orderedAppointments(
        availableWidth: CGFloat,
        overlap: ScheduleCardTuning.Overlap
    ) -> [AppointmentDetails] {
        guard let loadedDay else { return [] }
        let dayAppointments = dayAppointmentRows.compactMap(\.details).filter {
            $0.appointment.start.isSameDayAs(loadedDay)
        }
        let dayUnavailable = dayUnavailableTimeRows.map(\.unavailableTime).filter {
            $0.start.isSameDayAs(loadedDay)
        }
        let key = OrderCacheKey(
            loadedDay: loadedDay,
            availableWidth: availableWidth,
            overlap: overlap,
            appointments: dayAppointments.map(AppointmentCacheKey.init),
            unavailableTimes: dayUnavailable
        )
        // Avoid running TimelineLayoutEngine (and text measurement) on every drag frame.
        if cachedOrderKey == key {
            return cachedOrderedAppointments
        }
        let ordered = AppointmentCarouselOrder.orderedAppointments(
            appointments: dayAppointments,
            unavailableTimes: dayUnavailable,
            availableWidth: availableWidth,
            overlap: overlap
        )
        cachedOrderKey = key
        cachedOrderedAppointments = ordered
        return ordered
    }

    func activeDetails(in ordered: [AppointmentDetails]) -> AppointmentDetails? {
        if let match = ordered.first(where: { $0.id == currentAppointmentID }) {
            return match
        }
        if let initial = initialRow?.details, initial.id == currentAppointmentID {
            return initial
        }
        return nil
    }

    func select(appointmentID: Appointment.ID) {
        guard currentAppointmentID != appointmentID else { return }
        currentAppointmentID = appointmentID
        errorMessage = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func loadInitial() async {
        _ = try? await $initialRow.load(appointmentDetailsQuery(id: currentAppointmentID))
        if let start = initialRow?.details?.appointment.start {
            await loadDayIfNeeded(start)
        } else if let loadedDay {
            await reloadDay(loadedDay)
        }
        guard !Task.isCancelled else { return }
        hasResolvedInitialDetails = true
    }

    func loadDayIfNeeded(_ date: Date) async {
        let day = ClinicDate.day(date)
        guard loadedDay?.isSameDayAs(day) != true else { return }
        await reloadDay(day)
    }

    private func reloadDay(_ day: Date) async {
        loadedDay = day
        _ = try? await $dayAppointmentRows.load(querySchedule(selectedDate: day))
        _ = try? await $dayUnavailableTimeRows.load(
            unavailableTimesQuery(centeredOn: day, dayRadius: 1)
        )
    }

    func updateStatus(
        for appointmentID: Appointment.ID,
        to requestedStatus: Appointment.Status
    ) async -> Bool {
        guard !isUpdatingStatus else { return false }

        errorMessage = nil
        isUpdatingStatus = true
        defer { isUpdatingStatus = false }

        do {
            _ = try await statusClient.updateStatus(appointmentID, requestedStatus, now)
            telemetry.event(
                category: .appointment,
                name: "appointment_status_updated",
                recordID: appointmentID.uuidString.lowercased(),
                status: requestedStatus.rawValue
            )
            return true
        } catch let error as AppointmentStatusUpdateError {
            telemetry.log(
                .error,
                category: .appointment,
                name: "appointment_status_update_failed",
                message: "Appointment status update rejected",
                error: error,
                recordID: appointmentID.uuidString.lowercased(),
                status: requestedStatus.rawValue
            )
            await handleStatusUpdateError(error, appointmentID: appointmentID)
            return false
        } catch {
            telemetry.log(
                .error,
                category: .appointment,
                name: "appointment_status_update_failed",
                message: "Appointment status update failed",
                error: error,
                recordID: appointmentID.uuidString.lowercased(),
                status: requestedStatus.rawValue
            )
            errorMessage = "The appointment could not be updated."
            return false
        }
    }

    private func handleStatusUpdateError(
        _ error: AppointmentStatusUpdateError,
        appointmentID: Appointment.ID
    ) async {
        if let loadedDay {
            await reloadDay(loadedDay)
        }
        if initialRow?.id == appointmentID {
            _ = try? await $initialRow.load(appointmentDetailsQuery(id: appointmentID))
        }
        switch error {
        case .transition(.invalidTransition(let currentStatus, _)):
            switch currentStatus {
            case .completed:
                errorMessage = "This appointment was already completed."
            case .cancelled:
                errorMessage = "This appointment was already cancelled."
            case .draft, .scheduled:
                errorMessage = "This appointment was already updated."
            }

        case .unavailable:
            errorMessage = "This appointment is no longer available."

        case .invalidStoredStatus, .transition(.transientStatus):
            errorMessage = "The appointment could not be updated."
        }
    }

    private struct OrderCacheKey: Equatable {
        let loadedDay: Date
        let availableWidth: CGFloat
        let overlap: ScheduleCardTuning.Overlap
        let appointments: [AppointmentCacheKey]
        let unavailableTimes: [UnavailableTime]
    }

    private struct AppointmentCacheKey: Equatable {
        let id: Appointment.ID
        let start: Date
        let durationMinutes: Int
        let status: Appointment.Status
        let patientID: Patient.ID
        let patientName: String?
        let patientPhone: String?
        let patientDOB: Date?
        let patientGender: Gender?

        init(_ details: AppointmentDetails) {
            id = details.appointment.id
            start = details.appointment.start
            durationMinutes = details.appointment.durationMinutes
            status = details.appointment.status
            patientID = details.patient.id
            patientName = details.patient.name
            patientPhone = details.patient.phone
            patientDOB = details.patient.dob
            patientGender = details.patient.gender
        }
    }
}

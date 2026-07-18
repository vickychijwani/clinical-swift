import EventKit
import Foundation

nonisolated struct AppointmentCalendarEventPayload: Equatable, Sendable {
    let appointmentID: Appointment.ID
    let title: String
    let start: Date
    let end: Date
    let notes: String
    let url: URL
}

nonisolated struct AppointmentCalendarEventLink: Equatable, Sendable {
    let eventIdentifier: String?
    let eventStart: Date?
}

nonisolated struct AppointmentCalendarClient: Sendable {
    var requestFullAccess: @MainActor @Sendable () async throws -> Bool
    var resolveTargetCalendar: @MainActor @Sendable () async -> Bool
    var replaceEvent:
        @MainActor @Sendable (
            _ existingLink: AppointmentCalendarEventLink,
            _ payload: AppointmentCalendarEventPayload
        ) async throws -> AppointmentCalendarEventLink
    var deleteEvent:
        @MainActor @Sendable (
            _ existingLink: AppointmentCalendarEventLink,
            _ appointmentID: Appointment.ID,
            _ fallbackStart: Date?
        ) async throws -> Void
}

extension AppointmentCalendarClient {
    nonisolated static func live() -> Self {
        let adapter = AppointmentEventKitAdapter()
        return Self(
            requestFullAccess: {
                try await adapter.requestFullAccess()
            },
            resolveTargetCalendar: {
                await adapter.resolveTargetCalendar()
            },
            replaceEvent: { link, payload in
                try await adapter.replaceEvent(link: link, payload: payload)
            },
            deleteEvent: { link, appointmentID, fallbackStart in
                try await adapter.deleteEvent(
                    link: link,
                    appointmentID: appointmentID,
                    fallbackStart: fallbackStart
                )
            }
        )
    }
}

private actor AppointmentEventKitAdapter {
    private nonisolated static let targetCalendarTitle = "Bitehaus Debug"
    private nonisolated static let recoverySearchRadius: TimeInterval = 24 * 60 * 60

    private let eventStore = EKEventStore()
    private var targetCalendar: EKCalendar?

    func requestFullAccess() async throws -> Bool {
        let granted = try await eventStore.requestFullAccessToEvents()
        if !granted {
            targetCalendar = nil
        }
        return granted
    }

    func resolveTargetCalendar() -> Bool {
        eventStore.refreshSourcesIfNecessary()
        targetCalendar = eventStore.calendars(for: .event).first {
            $0.title == Self.targetCalendarTitle && $0.allowsContentModifications
        }
        return targetCalendar != nil
    }

    func replaceEvent(
        link: AppointmentCalendarEventLink,
        payload: AppointmentCalendarEventPayload
    ) throws -> AppointmentCalendarEventLink {
        guard let targetCalendar else {
            throw AppointmentCalendarClientError.targetCalendarUnavailable
        }

        let managedEvents = managedEvents(
            eventIdentifier: link.eventIdentifier,
            markerURL: payload.url,
            fallbackStarts: [link.eventStart, payload.start].compactMap { $0 },
            targetCalendar: targetCalendar
        )

        if let matchingEvent = managedEvents.first(where: {
            matches($0, payload: payload, targetCalendar: targetCalendar)
        }) {
            for duplicate in managedEvents
            where duplicate.calendarItemIdentifier != matchingEvent.calendarItemIdentifier {
                try eventStore.remove(duplicate, span: .thisEvent)
            }
            return AppointmentCalendarEventLink(
                eventIdentifier: matchingEvent.eventIdentifier,
                eventStart: payload.start
            )
        }

        for event in managedEvents {
            try eventStore.remove(event, span: .thisEvent)
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = targetCalendar
        event.title = payload.title
        event.startDate = payload.start
        event.endDate = payload.end
        event.isAllDay = false
        event.timeZone = .autoupdatingCurrent
        event.notes = payload.notes
        event.url = payload.url
        try eventStore.save(event, span: .thisEvent)

        guard let eventIdentifier = event.eventIdentifier else {
            throw AppointmentCalendarClientError.missingSavedEventIdentifier
        }
        return AppointmentCalendarEventLink(
            eventIdentifier: eventIdentifier,
            eventStart: payload.start
        )
    }

    func deleteEvent(
        link: AppointmentCalendarEventLink,
        appointmentID: Appointment.ID,
        fallbackStart: Date?
    ) throws {
        guard let targetCalendar else {
            throw AppointmentCalendarClientError.targetCalendarUnavailable
        }
        guard let markerURL = ClinicalURL.appointment(appointmentID).url else {
            throw AppointmentCalendarClientError.invalidMarkerURL
        }

        let managedEvents = managedEvents(
            eventIdentifier: link.eventIdentifier,
            markerURL: markerURL,
            fallbackStarts: [link.eventStart, fallbackStart].compactMap { $0 },
            targetCalendar: targetCalendar
        )
        for event in managedEvents {
            try eventStore.remove(event, span: .thisEvent)
        }
    }

    private func managedEvents(
        eventIdentifier: String?,
        markerURL: URL,
        fallbackStarts: [Date],
        targetCalendar: EKCalendar
    ) -> [EKEvent] {
        var eventsByIdentifier: [String: EKEvent] = [:]

        if let eventIdentifier,
            let event = eventStore.event(withIdentifier: eventIdentifier)
        {
            eventsByIdentifier[event.calendarItemIdentifier] = event
        }

        for start in Set(fallbackStarts) {
            let predicate = eventStore.predicateForEvents(
                withStart: start.addingTimeInterval(-Self.recoverySearchRadius),
                end: start.addingTimeInterval(Self.recoverySearchRadius),
                calendars: [targetCalendar]
            )
            for event in eventStore.events(matching: predicate) where event.url == markerURL {
                eventsByIdentifier[event.calendarItemIdentifier] = event
            }
        }

        return Array(eventsByIdentifier.values)
    }

    private func matches(
        _ event: EKEvent,
        payload: AppointmentCalendarEventPayload,
        targetCalendar: EKCalendar
    ) -> Bool {
        event.calendar.calendarIdentifier == targetCalendar.calendarIdentifier
            && event.title == payload.title
            && event.startDate.isApproximatelyEqual(to: payload.start)
            && event.endDate.isApproximatelyEqual(to: payload.end)
            && event.notes == payload.notes
            && event.url == payload.url
    }
}

nonisolated private enum AppointmentCalendarClientError: Error, Sendable {
    case targetCalendarUnavailable
    case missingSavedEventIdentifier
    case invalidMarkerURL
}

nonisolated extension Date {
    fileprivate func isApproximatelyEqual(to other: Date) -> Bool {
        abs(timeIntervalSince(other)) < 1
    }
}

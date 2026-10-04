import EventKit
import Foundation

nonisolated struct CalendarEventPayload: Equatable, Sendable {
    let title: String
    let start: Date
    let end: Date
    let notes: String
    let url: URL

    func matchesEvent(
        title: String?, start: Date?, end: Date?, notes: String?, url: URL?
    ) -> Bool {
        title == self.title
            && start?.isApproximatelyEqual(to: self.start) == true
            && end?.isApproximatelyEqual(to: self.end) == true
            // Accept absent notes when the payload has empty notes.
            && (notes ?? "") == self.notes
            && url == self.url
    }
}

nonisolated struct CalendarEventLink: Equatable, Sendable {
    let eventIdentifier: String?
    let eventStart: Date?
}

nonisolated struct CalendarClient: Sendable {
    var requestFullAccess: @MainActor @Sendable () async throws -> Bool
    var resolveTargetCalendar: @MainActor @Sendable () async -> Bool
    var replaceEvent:
        @MainActor @Sendable (
            _ existingLink: CalendarEventLink,
            _ payload: CalendarEventPayload
        ) async throws -> CalendarEventLink
    var deleteEvent:
        @MainActor @Sendable (
            _ existingLink: CalendarEventLink,
            _ markerURL: URL,
            _ fallbackStart: Date?
        ) async throws -> Void
}

extension CalendarClient {
    nonisolated static func live() -> Self {
        let adapter = EventKitAdapter()
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
            deleteEvent: { link, markerURL, fallbackStart in
                try await adapter.deleteEvent(
                    link: link,
                    markerURL: markerURL,
                    fallbackStart: fallbackStart
                )
            }
        )
    }
}

private actor EventKitAdapter {
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
        link: CalendarEventLink,
        payload: CalendarEventPayload
    ) throws -> CalendarEventLink {
        guard let targetCalendar else {
            throw CalendarClientError.targetCalendarUnavailable
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
            return CalendarEventLink(
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
            throw CalendarClientError.missingSavedEventIdentifier
        }
        return CalendarEventLink(
            eventIdentifier: eventIdentifier,
            eventStart: payload.start
        )
    }

    func deleteEvent(
        link: CalendarEventLink,
        markerURL: URL,
        fallbackStart: Date?
    ) throws {
        guard let targetCalendar else {
            throw CalendarClientError.targetCalendarUnavailable
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
        payload: CalendarEventPayload,
        targetCalendar: EKCalendar
    ) -> Bool {
        event.calendar.calendarIdentifier == targetCalendar.calendarIdentifier
            && payload.matchesEvent(
                title: event.title, start: event.startDate, end: event.endDate,
                notes: event.notes, url: event.url
            )
    }
}

nonisolated private enum CalendarClientError: Error, Sendable {
    case targetCalendarUnavailable
    case missingSavedEventIdentifier
    case invalidMarkerURL
}

nonisolated extension Date {
    fileprivate func isApproximatelyEqual(to other: Date) -> Bool {
        abs(timeIntervalSince(other)) < 1
    }
}

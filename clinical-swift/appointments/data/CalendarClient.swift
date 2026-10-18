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
    var recoveryCutoff: Date? = nil
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
    private var recoveryIndexes: [Date: RecoveryEventIndex] = [:]

    func requestFullAccess() async throws -> Bool {
        let granted = try await eventStore.requestFullAccessToEvents()
        if !granted {
            targetCalendar = nil
        }
        return granted
    }

    func resolveTargetCalendar() -> Bool {
        recoveryIndexes.removeAll()
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

        let managedEvents = try managedEvents(
            eventIdentifier: link.eventIdentifier,
            markerURL: payload.url,
            fallbackStarts: [link.eventStart, payload.start].compactMap { $0 },
            targetCalendar: targetCalendar, recoveryCutoff: link.recoveryCutoff
        )

        if let matchingEvent = managedEvents.first(where: {
            matches($0, payload: payload, targetCalendar: targetCalendar)
        }) {
            for duplicate in managedEvents
            where duplicate.calendarItemIdentifier != matchingEvent.calendarItemIdentifier {
                try eventStore.remove(duplicate, span: .thisEvent)
            }
            updateRecoveryIndexes(removing: managedEvents, adding: matchingEvent)
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
        updateRecoveryIndexes(removing: managedEvents, adding: event)

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
        let managedEvents = try managedEvents(
            eventIdentifier: link.eventIdentifier,
            markerURL: markerURL,
            fallbackStarts: [link.eventStart, fallbackStart].compactMap { $0 },
            targetCalendar: targetCalendar, recoveryCutoff: link.recoveryCutoff
        )
        for event in managedEvents {
            try eventStore.remove(event, span: .thisEvent)
        }
        updateRecoveryIndexes(removing: managedEvents, adding: nil)
    }

    private func managedEvents(
        eventIdentifier: String?,
        markerURL: URL,
        fallbackStarts: [Date],
        targetCalendar: EKCalendar,
        recoveryCutoff: Date?
    ) throws -> [EKEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarClientError.accessUnavailable
        }
        var eventsByIdentifier: [String: EKEvent] = [:]

        if let eventIdentifier,
            let event = eventStore.event(withIdentifier: eventIdentifier),
            event.url == markerURL,
            event.calendar.calendarIdentifier == targetCalendar.calendarIdentifier,
            recoveryCutoff.map({ event.endDate >= $0 }) != false
        {
            eventsByIdentifier[event.calendarItemIdentifier] = event
        }

        if let cutoff = recoveryCutoff {
            // EventKit limits each query to four years. Share one index across recovered rows.
            let horizon = CalendarRecoveryWindow.horizon(knownStarts: fallbackStarts, now: .now)
            var index = recoveryIndexes[cutoff] ?? RecoveryEventIndex(end: cutoff)
            while index.end < horizon {
                let end = CalendarRecoveryWindow.queryEnd(from: index.end, through: horizon)
                let predicate = eventStore.predicateForEvents(
                    withStart: index.end, end: end, calendars: [targetCalendar])
                for event in eventStore.events(matching: predicate) {
                    if let url = event.url, event.endDate >= cutoff {
                        index.events[url, default: [:]][event.calendarItemIdentifier] = event
                    }
                }
                index.end = end
            }
            recoveryIndexes[cutoff] = index
            for event in index.events[markerURL]?.values ?? [String: EKEvent]().values {
                eventsByIdentifier[event.calendarItemIdentifier] = event
            }
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                throw CalendarClientError.accessUnavailable
            }
            return Array(eventsByIdentifier.values)
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

        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarClientError.accessUnavailable
        }
        return Array(eventsByIdentifier.values)
    }

    private struct RecoveryEventIndex {
        var end: Date
        var events: [URL: [String: EKEvent]] = [:]
    }

    private func updateRecoveryIndexes(removing events: [EKEvent], adding event: EKEvent?) {
        for cutoff in Array(recoveryIndexes.keys) {
            guard var index = recoveryIndexes[cutoff] else { continue }
            for removed in events {
                if let url = removed.url {
                    index.events[url]?[removed.calendarItemIdentifier] = nil
                }
            }
            if let event, let url = event.url, event.endDate >= cutoff, event.startDate < index.end
            {
                index.events[url, default: [:]][event.calendarItemIdentifier] = event
            }
            recoveryIndexes[cutoff] = index
        }
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
    case accessUnavailable
}

nonisolated extension Date {
    fileprivate func isApproximatelyEqual(to other: Date) -> Bool {
        abs(timeIntervalSince(other)) < 1
    }
}

nonisolated enum CalendarRecoveryWindow {
    static func horizon(knownStarts: [Date], now: Date) -> Date {
        max(knownStarts.max() ?? now, now.addingTimeInterval(10 * 366 * 86_400))
            .addingTimeInterval(86_400)
    }

    static func queryEnd(from start: Date, through horizon: Date) -> Date {
        min(start.addingTimeInterval(3 * 365 * 86_400), horizon)
    }
}

import ClinicalModels
import Dependencies
import Foundation

enum AppTab: Hashable {
    case schedule
    case patients
    case payments
}

enum Route: Hashable {
    case patient(_ id: UUID)
    case appointment(_ id: UUID)
    case appointmentCompletion(_ visitID: UUID)
}

@MainActor @Observable
final class Router {
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.telemetry) private var telemetry

    let toast: ToastStore

    // Schedule is the home screen.
    var selectedTab: AppTab = .schedule {
        didSet {
            if oldValue != selectedTab {
                unavailableTimeNavigationRequest = nil
                navigationErrorMessage = nil
                telemetry.event(
                    category: .navigation,
                    name: "tab_selected",
                    route: selectedTab.telemetryName
                )
            }
        }
    }
    // Schedule selection lives here so every entry point (UI, URL, widget, or App Intent) changes
    // the same date that is visible behind appointment details.
    private(set) var selectedScheduleDate: Date

    // Invariant: the app has exactly one app-root presentation intent. Independent optional sheet
    // state can make multiple hosts present at once or resurrect an older flow after interruption.
    private(set) var activePresentation: AppPresentation?
    private(set) var unavailableTimeNavigationRequest: UnavailableTimeNavigationRequest?
    var navigationErrorMessage: String?

    private(set) var patientSearchRequest: PatientSearchRequest?

    // Keep only the newest replacement while the visible tray exits. Track whether a dismissal
    // callback is expected so an action replaced before appearing can activate immediately.
    private var replacementPresentation: AppPresentation?
    private var presentedPresentationID: UUID?
    private var dismissingPresentationID: UUID?

    init(selectedScheduleDate: Date = .now, toast: ToastStore? = nil) {
        self.selectedScheduleDate = ClinicDate.day(selectedScheduleDate)
        self.toast = toast ?? ToastStore()
    }

    var detailsPresentation: DetailsPresentation? {
        guard case .details(let presentation) = activePresentation else { return nil }
        return presentation
    }

    // All schedule editors use the router's single active presentation and one sheet host.
    var scheduleEditorRequest: ScheduleEditorRequest? {
        guard case .scheduleEditor(let request) = activePresentation else { return nil }
        return request
    }

    func requestScheduleCreation(on date: Date? = nil) {
        selectedTab = .schedule
        if let date {
            selectedScheduleDate = ClinicDate.day(date)
        }
        requestPresentation(.scheduleEditor(.create()))
    }

    func requestUnavailableTimeEdit(_ block: UnavailableTime) {
        selectedTab = .schedule
        selectedScheduleDate = ClinicDate.day(block.start)
        requestPresentation(.scheduleEditor(.editUnavailableTime(block)))
    }

    func finishScheduleEditor(_ presentationID: UUID, date: Date) {
        guard activePresentation?.id == presentationID else { return }
        selectedScheduleDate = ClinicDate.day(date)
        discardActivePresentation()
    }

    var appointmentMessageRequest: AppointmentMessageRequest? {
        guard case .appointmentMessage(let request) = activePresentation else { return nil }
        return request
    }

    var patientEditRequest: PatientEditRequest? {
        guard case .patientEdit(let request) = activePresentation else { return nil }
        return request
    }

    var settingsRequest: SettingsRequest? {
        guard case .settings(let request) = activePresentation else { return nil }
        return request
    }

    func requestSettings() {
        // Settings must not discard an editor or replace another active sheet.
        guard activePresentation == nil, dismissingPresentationID == nil else { return }
        requestPresentation(.settings(SettingsRequest()))
    }

    func presentDetails(_ root: Route) {
        toast.dismiss()
        unavailableTimeNavigationRequest = nil
        navigationErrorMessage = nil
        if let detailsPresentation, dismissingPresentationID == nil {
            // A new selection behind the visible details sheet replaces its content in place. Keep
            // the session ID stable so SwiftUI does not perform an unnecessary sheet handoff.
            detailsPresentation.replaceRoot(with: root)
            telemetry.event(
                category: .navigation,
                name: "presentation_replaced",
                recordID: root.telemetryRecordID,
                route: root.telemetryName
            )
        } else {
            requestPresentation(.details(DetailsPresentation(root: root)))
        }
    }

    func pushDetails(_ route: Route) {
        detailsPresentation?.push(route)
    }

    func pushDetails(_ route: Route, presentationID: UUID, visitID: UUID) {
        guard let presentation = detailsPresentation, presentation.id == presentationID,
            presentation.visitID == visitID
        else { return }
        pushDetails(route)
    }

    func setDetailsPath(_ path: [Route], presentationID: DetailsPresentation.ID) {
        // NavigationStack can write its path back after a sheet has been replaced. The session ID
        // prevents that stale write from mutating the new details flow.
        guard let detailsPresentation, detailsPresentation.id == presentationID else { return }
        guard !detailsPresentation.isSavingCompletion else { return }
        detailsPresentation.setPath(path)
    }

    func beginAppointmentCompletion(
        _ details: AppointmentDetails, visitID: UUID, presentationID: UUID
    ) {
        guard let presentation = detailsPresentation,
            isCurrentDetailsRoute(
                .appointment(details.appointment.id), presentationID: presentationID),
            details.appointment.status == .scheduled, !presentation.isSavingCompletion
        else { return }
        if presentation.completionDrafts[visitID] == nil {
            presentation.completionDrafts[visitID] = AppointmentCompletionModel(
                id: visitID, details: details, originPath: presentation.path)
        }
        presentation.push(.appointmentCompletion(visitID))
    }

    func finishAppointmentCompletion(_ model: AppointmentCompletionModel, presentationID: UUID) {
        // A sheet ID can survive root replacement. The draft identity also proves visit ownership.
        guard let presentation = detailsPresentation, presentation.id == presentationID,
            presentation.currentRoute == .appointmentCompletion(model.id),
            presentation.completionDrafts[model.id] === model,
            Array(presentation.path.dropLast()) == model.originPath
        else { return }
        selectedTab = .schedule
        discardActivePresentation()
        let patient = model.patient
        toast.show(
            message: "Completed",
            actionTitle: "Book follow-up",
            duration: .seconds(6)
        ) { [weak self] in
            self?.requestFollowUpBooking(for: patient)
        }
    }

    func dismissDetails() {
        guard detailsPresentation != nil else { return }
        discardActivePresentation()
    }

    func dismissDetails(presentationID: UUID) {
        dismissDetailsIfMatching(presentationID: presentationID, visitID: nil)
    }

    func dismissDetails(presentationID: UUID, visitID: UUID) {
        dismissDetailsIfMatching(presentationID: presentationID, visitID: visitID)
    }

    private func dismissDetailsIfMatching(presentationID: UUID, visitID: UUID?) {
        // A sheet ID survives in-place root replacement, so async callers check visitID too.
        guard let presentation = detailsPresentation,
            presentation.id == presentationID,
            visitID == nil || presentation.visitID == visitID,
            !presentation.isSavingCompletion
        else { return }
        discardActivePresentation()
    }

    func dismissPresentation() {
        discardActivePresentation()
    }

    func selectScheduleDate(_ date: Date) {
        unavailableTimeNavigationRequest = nil
        navigationErrorMessage = nil
        let normalizedDate = ClinicDate.day(date)
        guard !normalizedDate.isSameDayAs(selectedScheduleDate) else { return }

        selectedScheduleDate = normalizedDate
        // Invariant: appointment details for date X must never remain over schedule date Y. A
        // direct date selection is a new navigation action, so discard the complete details flow.
        if detailsPresentation != nil {
            discardActivePresentation()
        }
    }

    func alignSchedule(
        with appointmentDate: Date,
        appointmentID: Appointment.ID,
        presentationID: DetailsPresentation.ID
    ) {
        // Appointment records resolve asynchronously. Require both the sheet session and its
        // current route to match so a late result cannot change the tab or date after navigation.
        guard
            isCurrentDetailsRoute(
                .appointment(appointmentID),
                presentationID: presentationID
            )
        else { return }

        selectedTab = .schedule
        selectedScheduleDate = ClinicDate.day(appointmentDate)
    }

    func scheduleIsAligned(
        with appointmentDate: Date,
        appointmentID: Appointment.ID,
        presentationID: DetailsPresentation.ID
    ) -> Bool {
        guard
            selectedTab == .schedule,
            isCurrentDetailsRoute(
                .appointment(appointmentID),
                presentationID: presentationID
            )
        else { return false }

        return appointmentDate.isSameDayAs(selectedScheduleDate)
    }

    func isCurrentDetailsRoute(
        _ route: Route,
        presentationID: DetailsPresentation.ID
    ) -> Bool {
        guard let detailsPresentation, detailsPresentation.id == presentationID else {
            return false
        }
        return detailsPresentation.currentRoute == route
    }

    func requestAppointmentEdit(_ details: AppointmentDetails) {
        selectedTab = .schedule
        selectedScheduleDate = ClinicDate.day(details.appointment.start)
        requestPresentation(.scheduleEditor(.editAppointment(details)))
    }

    func requestAppointmentBooking(for patient: Patient, on date: Date? = nil) {
        selectedTab = .schedule
        if let date {
            selectedScheduleDate = ClinicDate.day(date)
        }
        requestPresentation(.scheduleEditor(.bookAppointment(patient)))
    }

    func requestFollowUpBooking(for patient: Patient) {
        let targetDate = Bitehaus.nextBusinessDay(after: now, using: ClinicDate.calendar)
        requestAppointmentBooking(for: patient, on: targetDate)
    }

    func requestAppointmentMessage(id: Appointment.ID, date: Date) {
        selectedTab = .schedule
        selectedScheduleDate = ClinicDate.day(date)
        requestPresentation(
            .appointmentMessage(
                AppointmentMessageRequest(appointmentID: id)
            )
        )
    }

    func requestAppointmentMessage(_ details: AppointmentDetails) {
        requestAppointmentMessage(id: details.appointment.id, date: details.appointment.start)
    }

    func requestPatientEdit(_ patient: Patient) {
        requestPresentation(.patientEdit(PatientEditRequest(patient: patient)))
    }

    func requestPatientCreation() {
        requestPresentation(.patientEdit(PatientEditRequest(patient: nil)))
    }

    func presentationDidAppear(_ presentationID: UUID) {
        // Only a sheet that actually appeared will later send onDismiss. This distinction lets an
        // action supersede an unpresented request without waiting for a callback that will not come.
        guard activePresentation?.id == presentationID else { return }
        presentedPresentationID = presentationID
    }

    func presentationDidDismiss(_ presentationID: UUID) {
        guard
            presentedPresentationID == presentationID
                || dismissingPresentationID == presentationID
        else { return }
        presentedPresentationID = nil
        // onDismiss either completes a router-driven handoff or reports that the user dismissed
        // the active sheet. Preserve a queued replacement only in the former case.
        if dismissingPresentationID != nil {
            self.dismissingPresentationID = nil
        } else if case .scheduleEditor = activePresentation {
            // Closing schedule-editor fields keeps the timeline draft active until finished or replaced.
        } else {
            activePresentation = nil
        }

        telemetry.event(
            category: .navigation,
            name: "presentation_dismissed",
            recordID: presentationID.uuidString.lowercased()
        )
        activateReplacementIfPossible()
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let clinicalURL = ClinicalURL(url) else {
            telemetry.log(
                .warning,
                category: .navigation,
                name: "url_rejected",
                message: "Unsupported clinical URL",
                source: "url"
            )
            return false
        }

        telemetry.event(
            category: .navigation,
            name: "url_opened",
            recordID: clinicalURL.telemetryRecordID,
            source: "url",
            route: clinicalURL.telemetryName
        )

        switch clinicalURL {
        case .bookAppointment(let day):
            requestScheduleCreation(on: day?.date(using: ClinicDate.calendar))
        case .appointment(let id):
            openAppointment(id: id)
        case .schedule(let day):
            openExternalSchedule(day)
        case .unavailableTime(let id):
            openUnavailableTime(id)
        }
        return true
    }

    func openUnavailableTime(_ id: UUID) {
        selectedTab = .schedule
        discardAllPresentations()
        patientSearchRequest = nil
        navigationErrorMessage = nil
        unavailableTimeNavigationRequest = UnavailableTimeNavigationRequest(blockID: id)
    }

    func failUnavailableTimeNavigation(
        _ request: UnavailableTimeNavigationRequest, error: any Error
    ) {
        telemetry.log(
            .error,
            category: .navigation,
            name: "unavailable_time_navigation_failed",
            message: "Unavailable time could not be loaded",
            error: error,
            recordID: request.blockID.uuidString.lowercased()
        )
        guard unavailableTimeNavigationRequest?.id == request.id else { return }
        unavailableTimeNavigationRequest = nil
        navigationErrorMessage = "The unavailable time could not be loaded."
    }

    func completeUnavailableTimeNavigation(
        _ request: UnavailableTimeNavigationRequest, block: UnavailableTime?
    ) {
        guard unavailableTimeNavigationRequest?.id == request.id else { return }
        unavailableTimeNavigationRequest = nil
        guard let block, block.id == request.blockID else {
            navigationErrorMessage = "This unavailable time no longer exists."
            return
        }
        selectedTab = .schedule
        selectedScheduleDate = ClinicDate.day(block.start)
    }

    func openAppointment(id: Appointment.ID) {
        selectedTab = .schedule
        // ID-only entry points do not know the appointment date yet. AppointmentDetailsView keeps
        // neutral content visible until the resolved record aligns the router-owned schedule date.
        presentDetails(.appointment(id))
    }

    func openExternalDetails(_ route: Route) {
        switch route {
        case .patient:
            selectedTab = .patients
            presentDetails(route)
        case .appointment(let id):
            openAppointment(id: id)
        case .appointmentCompletion:
            break
        }
    }

    func openExternalPatientSearch(phoneNumbers: Set<String>) {
        let normalizedPhoneNumbers = Set(phoneNumbers.compactMap(PhoneNumber.normalizedE164))
        guard !normalizedPhoneNumbers.isEmpty else { return }

        selectedTab = .patients
        discardAllPresentations()
        patientSearchRequest = PatientSearchRequest(phoneNumbers: normalizedPhoneNumbers)
    }

    func openExternalSchedule(_ day: ScheduleDay) {
        guard let date = day.date(using: ClinicDate.calendar) else { return }

        selectedTab = .schedule
        discardAllPresentations()
        patientSearchRequest = nil
        selectedScheduleDate = date
    }

    func consumePatientSearchRequest(_ requestID: PatientSearchRequest.ID) {
        guard patientSearchRequest?.id == requestID else { return }
        patientSearchRequest = nil
    }

    private func requestPresentation(_ presentation: AppPresentation) {
        toast.dismiss()
        unavailableTimeNavigationRequest = nil
        navigationErrorMessage = nil
        // App-root actions are latest-wins interruptions. Do not queue multiple sheets or restore
        // the interrupted presentation after the replacement ends; its transient state is stale.
        let isReplacement = activePresentation != nil || dismissingPresentationID != nil
        telemetry.event(
            category: .navigation,
            name: isReplacement ? "presentation_replaced" : "presentation_opened",
            recordID: presentation.telemetryRecordID,
            route: presentation.telemetryName
        )
        patientSearchRequest = nil
        replacementPresentation = presentation

        guard dismissingPresentationID == nil else { return }

        if let activePresentation {
            self.activePresentation = nil
            if presentedPresentationID == activePresentation.id {
                dismissingPresentationID = activePresentation.id
            } else {
                activateReplacementIfPossible()
            }
        } else {
            activateReplacementIfPossible()
        }
    }

    private func discardActivePresentation() {
        guard dismissingPresentationID == nil, let activePresentation else { return }

        replacementPresentation = nil
        self.activePresentation = nil
        if presentedPresentationID == activePresentation.id {
            dismissingPresentationID = activePresentation.id
        } else {
            activateReplacementIfPossible()
        }
    }

    private func discardAllPresentations() {
        unavailableTimeNavigationRequest = nil
        navigationErrorMessage = nil
        // External non-sheet destinations supersede both the visible sheet and any replacement
        // already waiting for its dismissal to complete.
        replacementPresentation = nil
        discardActivePresentation()
    }

    private func activateReplacementIfPossible() {
        guard
            activePresentation == nil,
            dismissingPresentationID == nil,
            let replacementPresentation
        else { return }

        self.replacementPresentation = nil
        activePresentation = replacementPresentation
    }
}

/// The mutually exclusive app-root flows. Sheet hosts expose individual cases as computed values,
/// but this enum remains the sole source of presentation truth.
enum AppPresentation {
    case settings(SettingsRequest)
    case details(DetailsPresentation)
    case scheduleEditor(ScheduleEditorRequest)
    case appointmentMessage(AppointmentMessageRequest)
    case patientEdit(PatientEditRequest)

    nonisolated var id: UUID {
        switch self {
        case .settings(let request):
            request.id
        case .details(let presentation):
            presentation.id
        case .scheduleEditor(let request):
            request.id
        case .appointmentMessage(let request):
            request.id
        case .patientEdit(let request):
            request.id
        }
    }
}

nonisolated struct SettingsRequest: Identifiable, Sendable {
    let id = UUID()
}

@MainActor @Observable
final class DetailsPresentation: Identifiable {
    /// Stable identity for one details-sheet session. Its root may be replaced in place, while
    /// asynchronous route work and NavigationStack write-backs use this ID to reject stale events
    /// from a sheet session that has already been discarded.
    nonisolated let id: UUID
    private(set) var root: Route

    // Keep mutation router-owned so every NavigationStack write-back can be checked against `id`.
    private(set) var path: [Route]
    private(set) var visitID = UUID()
    var completionDrafts: [UUID: AppointmentCompletionModel] = [:]

    var isSavingCompletion: Bool { completionDrafts.values.contains { $0.isSaving } }
    var hasUnsavedCompletion: Bool { completionDrafts.values.contains { $0.hasUnsavedChanges } }
    var showsCompletion: Bool {
        if case .appointmentCompletion = currentRoute { return true }
        return false
    }

    var currentRoute: Route {
        path.last ?? root
    }

    init(
        id: UUID = UUID(),
        root: Route,
        path: [Route] = []
    ) {
        self.id = id
        self.root = root
        self.path = path
    }

    fileprivate func replaceRoot(with route: Route) {
        visitID = UUID()
        completionDrafts.removeAll()
        root = route
        path.removeAll()
    }

    fileprivate func push(_ route: Route) {
        path.append(route)
    }

    fileprivate func setPath(_ path: [Route]) {
        self.path = path
        completionDrafts = completionDrafts.filter { _, draft in
            path.starts(with: draft.originPath)
        }
    }
}

nonisolated struct ScheduleEditorRequest: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case create
        case bookAppointment(Patient)
        case editAppointment(AppointmentDetails)
        case editUnavailableTime(UnavailableTime)
    }

    let id: UUID
    let kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    static func create() -> Self {
        Self(kind: .create)
    }

    static func bookAppointment(_ patient: Patient) -> Self {
        Self(kind: .bookAppointment(patient))
    }

    static func editAppointment(_ details: AppointmentDetails) -> Self {
        Self(kind: .editAppointment(details))
    }

    static func editUnavailableTime(_ block: UnavailableTime) -> Self {
        Self(kind: .editUnavailableTime(block))
    }

    var needsBookingAvailability: Bool {
        switch kind {
        case .create, .bookAppointment: true
        case .editAppointment, .editUnavailableTime: false
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct AppointmentMessageRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let appointmentID: Appointment.ID

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct PatientEditRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let patient: Patient?

    var patientID: Patient.ID? {
        patient?.id
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct PatientSearchRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let phoneNumbers: Set<String>

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct UnavailableTimeNavigationRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let blockID: UUID
}

extension AppTab {
    fileprivate var telemetryName: String {
        switch self {
        case .schedule: "schedule"
        case .patients: "patients"
        case .payments: "payments"
        }
    }
}

extension Route {
    fileprivate var telemetryName: String {
        switch self {
        case .patient: "patient_details"
        case .appointment: "appointment_details"
        case .appointmentCompletion: "appointment_completion"
        }
    }

    fileprivate var telemetryRecordID: String {
        switch self {
        case .patient(let id), .appointment(let id), .appointmentCompletion(let id):
            id.uuidString.lowercased()
        }
    }
}

extension ScheduleEditorRequest {
    fileprivate var telemetryName: String {
        switch kind {
        case .create: "schedule_creation"
        case .bookAppointment: "appointment_booking"
        case .editAppointment: "appointment_edit"
        case .editUnavailableTime: "unavailable_time_editor"
        }
    }

    fileprivate var telemetryRecordID: String? {
        switch kind {
        case .create: nil
        case .bookAppointment(let patient): patient.id.uuidString.lowercased()
        case .editAppointment(let details): details.appointment.id.uuidString.lowercased()
        case .editUnavailableTime(let block): block.id.uuidString.lowercased()
        }
    }
}

extension AppPresentation {
    fileprivate var telemetryName: String {
        switch self {
        case .settings: "settings"
        case .details(let presentation): presentation.root.telemetryName
        case .scheduleEditor(let request): request.telemetryName
        case .appointmentMessage: "appointment_message"
        case .patientEdit(let request): request.patient == nil ? "patient_create" : "patient_edit"
        }
    }

    fileprivate var telemetryRecordID: String? {
        switch self {
        case .settings: nil
        case .details(let presentation): presentation.root.telemetryRecordID
        case .scheduleEditor(let request): request.telemetryRecordID
        case .appointmentMessage(let request): request.appointmentID.uuidString.lowercased()
        case .patientEdit(let request): request.patientID?.uuidString.lowercased()
        }
    }
}

extension ClinicalURL {
    fileprivate var telemetryName: String {
        switch self {
        case .bookAppointment: "book_appointment"
        case .appointment: "appointment"
        case .schedule: "schedule"
        case .unavailableTime: "unavailable_time"
        }
    }

    fileprivate var telemetryRecordID: String? {
        switch self {
        case .bookAppointment, .schedule: nil
        case .appointment(let id), .unavailableTime(let id): id.uuidString.lowercased()
        }
    }
}

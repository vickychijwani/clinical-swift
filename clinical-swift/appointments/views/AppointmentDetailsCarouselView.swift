import ClinicalModels
import SwiftUI

/// Root appointment details flow supporting horizontal card swiping across the day's scheduled
/// and completed appointments inside one shared tray, with floating prev/next cards overflowing
/// the tray edges and Liquid Glass controls materializing/dematerializing on commit.
struct AppointmentRootCarouselFlow: View {
    @Environment(Router.self) private var router
    @Environment(\.scheduleCardTuning) private var cardTuning
    @Environment(\.traySurfaceMetrics) private var metrics

    @Bindable var presentation: DetailsPresentation
    let initialAppointmentID: Appointment.ID
    let requestDismiss: () -> Void

    @State private var carouselModel: AppointmentDayCarouselModel
    @State private var trackPosition: CGFloat = 0
    @State private var dragAxis: CarouselDragAxis?
    @State private var dragStartIndex: Int?
    @State private var dragOriginX: CGFloat = 0
    @State private var lastCommittedAppointmentID: Appointment.ID?
    @GestureState private var isGestureActive = false

    init(
        presentation: DetailsPresentation,
        initialAppointmentID: Appointment.ID,
        initialScheduleDate: Date,
        requestDismiss: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.initialAppointmentID = initialAppointmentID
        self.requestDismiss = requestDismiss
        _carouselModel = State(
            initialValue: AppointmentDayCarouselModel(
                initialAppointmentID: initialAppointmentID,
                initialScheduleDate: initialScheduleDate
            )
        )
    }

    var body: some View {
        let ordered = carouselModel.orderedAppointments(
            availableWidth: metrics.size.width,
            overlap: cardTuning.overlap
        )
        let activeDetails = carouselModel.activeDetails(in: ordered)
        let items: [AppointmentDetails] =
            if let activeDetails {
                ordered.contains(where: { $0.id == activeDetails.id }) ? ordered : [activeDetails]
            } else {
                []
            }
        let activeIndex =
            items.firstIndex(where: { $0.id == carouselModel.currentAppointmentID }) ?? 0
        let isReady = activeDetails.map(canRender) ?? false
        let isAtRoot = presentation.path.isEmpty
        let renderedLayout = TrayLayout.rendered(
            topEdge: metrics.topEdge, size: metrics.size,
            topInset: metrics.safeArea.top, bottomInset: metrics.safeArea.bottom)
        let step = AppointmentCarouselMotion.step(
            in: metrics.size.width, scale: renderedLayout.scale)
        let syncKey = TrackSyncKey(
            orderedIDs: items.map(\.id),
            activeID: carouselModel.currentAppointmentID,
            step: step
        )

        Group {
            if let activeDetails {
                if isReady {
                    AppointmentCardCarouselSurface(
                        items: items,
                        activeDetails: activeDetails,
                        activeIndex: activeIndex,
                        trackPosition: trackPosition,
                        step: step,
                        presentation: presentation,
                        pathBinding: pathBinding,
                        isUpdatingStatus: carouselModel.isUpdatingStatus,
                        metrics: metrics,
                        renderedScale: renderedLayout.scale,
                        onNavigate: navigate,
                        onComplete: { beginCompletion(for: activeDetails) },
                        onCancel: { await performCancel(for: activeDetails) },
                        onDismiss: requestDismiss,
                        carouselGesture: horizontalDragGesture(
                            items: items, activeIndex: activeIndex, step: step, enabled: isAtRoot)
                    )
                } else {
                    placeholderTray {
                        ProgressView()
                            .task(id: activeDetails.appointment.start) {
                                router.alignSchedule(
                                    with: activeDetails.appointment.start,
                                    appointmentID: activeDetails.appointment.id,
                                    presentationID: presentation.id
                                )
                                await carouselModel.loadDayIfNeeded(
                                    activeDetails.appointment.start
                                )
                            }
                    }
                }
            } else if carouselModel.hasResolvedInitialDetails {
                placeholderTray {
                    ContentUnavailableView(
                        "Appointment Unavailable",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("This appointment no longer exists.")
                    )
                }
            } else {
                placeholderTray {
                    ProgressView()
                }
            }
        }
        .trayOptions(
            size: DetailsFlowView.traySize(for: presentation),
            allowsInteractiveDismiss: !presentation.showsCompletion
                && !presentation.isSavingCompletion,
            showsIndicator: !presentation.showsCompletion,
            requestDismiss: requestDismiss
        )
        .alert(
            "Unable to update appointment",
            isPresented: Binding(
                get: { carouselModel.errorMessage != nil },
                set: { if !$0 { carouselModel.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                carouselModel.dismissError()
            }
        } message: {
            Text(carouselModel.errorMessage ?? "")
        }
        .task {
            await carouselModel.loadInitial()
        }
        .onChange(of: syncKey, initial: true) { oldValue, newValue in
            guard dragAxis == nil, newValue.step > 0 else { return }
            let index = items.firstIndex(where: { $0.id == newValue.activeID }) ?? 0
            let isInPlaceCommit =
                oldValue.orderedIDs == newValue.orderedIDs
                && oldValue.step == newValue.step
                && lastCommittedAppointmentID == newValue.activeID
            if isInPlaceCommit {
                lastCommittedAppointmentID = nil
                return
            }
            trackPosition = CGFloat(index) * newValue.step
        }
        .onChange(of: isGestureActive) { _, active in
            guard !active, dragAxis != nil else { return }
            // Reset cleanly if the system cancels the drag without invoking onEnded.
            dragAxis = nil
            dragStartIndex = nil
            dragOriginX = 0
            withAnimation(metrics.animates ? .spring(duration: 0.28, bounce: 0) : nil) {
                trackPosition = CGFloat(activeIndex) * step
            }
        }
    }

    private func placeholderTray<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: pathBinding) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.canvas)
                .navigationTitle("Appointment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if presentation.path.isEmpty {
                            Button("Close", systemImage: "xmark", action: requestDismiss)
                                .labelStyle(.iconOnly)
                                .disabled(presentation.isSavingCompletion)
                        }
                    }
                }
        }
        // The standalone navigation bar supplies ten points of top space. Add six to
        // match the native sheet's sixteen-point header without changing its controls.
        .padding(.top, 6)
        .safeAreaPadding(.bottom, metrics.bottomInset + metrics.keyboardHeight)
        .modifier(
            TrayFrame(
                topEdge: metrics.topEdge, size: metrics.size, safeArea: metrics.safeArea,
                showsIndicator: metrics.showsIndicator)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tray-surface")
    }

    private func horizontalDragGesture(
        items: [AppointmentDetails],
        activeIndex: Int,
        step: CGFloat,
        enabled: Bool
    ) -> some Gesture {
        // Low 5 pt slop starts tracking immediately while still allowing clean taps on buttons.
        DragGesture(minimumDistance: 5)
            .updating($isGestureActive) { _, active, _ in
                active = true
            }
            .onChanged { value in
                guard enabled, step > 0, !items.isEmpty else { return }
                if dragAxis == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    dragAxis = dx >= dy ? .horizontal : .vertical
                    if dragAxis == .horizontal {
                        dragStartIndex = activeIndex
                        // Subtract lock-in slop so motion starts smoothly from zero with no jump.
                        dragOriginX = value.translation.width
                    }
                }
                guard dragAxis == .horizontal else { return }
                let anchor = dragStartIndex ?? activeIndex
                let effectiveTranslation = value.translation.width - dragOriginX
                trackPosition = AppointmentCarouselMotion.dragPosition(
                    anchorIndex: anchor,
                    translation: effectiveTranslation,
                    count: items.count,
                    step: step
                )
            }
            .onEnded { value in
                let wasHorizontal = dragAxis == .horizontal
                let anchor = dragStartIndex ?? activeIndex
                let originX = dragOriginX
                dragAxis = nil
                dragStartIndex = nil
                dragOriginX = 0
                guard enabled, wasHorizontal, step > 0, !items.isEmpty else { return }

                let effectiveTranslation = value.translation.width - originX
                let effectivePredicted = value.predictedEndTranslation.width - originX
                let targetIndex = AppointmentCarouselMotion.targetIndex(
                    currentIndex: anchor,
                    count: items.count,
                    step: step,
                    translation: effectiveTranslation,
                    predictedTranslation: effectivePredicted
                )
                if targetIndex != anchor {
                    let targetID = items[targetIndex].id
                    lastCommittedAppointmentID = targetID
                    carouselModel.select(appointmentID: targetID)
                    router.selectCarouselAppointment(targetID, presentationID: presentation.id)
                }
                withAnimation(metrics.animates ? .spring(duration: 0.28, bounce: 0) : nil) {
                    trackPosition = CGFloat(targetIndex) * step
                }
            }
    }

    private var pathBinding: Binding<[Route]> {
        // Do not bind NavigationStack directly to the presentation's path. SwiftUI may write back
        // during dismissal, so the router must validate the sheet-session ID before mutating it.
        let visitID = presentation.visitID
        return Binding(
            get: { presentation.path },
            set: {
                guard presentation.visitID == visitID else { return }
                router.setDetailsPath($0, presentationID: presentation.id)
            }
        )
    }

    private func navigate(_ route: Route) {
        router.pushDetails(route, presentationID: presentation.id, visitID: presentation.visitID)
    }

    private func beginCompletion(for details: AppointmentDetails) {
        router.beginAppointmentCompletion(
            details, visitID: details.id, presentationID: presentation.id)
    }

    private func performCancel(for details: AppointmentDetails) async {
        let visitID = presentation.visitID
        if await carouselModel.updateStatus(for: details.id, to: .cancelled),
            router.isCurrentDetailsRoute(.appointment(details.id), presentationID: presentation.id)
        {
            router.dismissDetails(presentationID: presentation.id, visitID: visitID)
        }
    }

    private func canRender(_ details: AppointmentDetails) -> Bool {
        let appointmentID = details.appointment.id
        guard
            router.isCurrentDetailsRoute(
                .appointment(appointmentID),
                presentationID: presentation.id
            )
        else {
            // A covered route must keep its resolved content and navigation preferences mounted.
            return true
        }
        return router.scheduleIsAligned(
            with: details.appointment.start,
            appointmentID: appointmentID,
            presentationID: presentation.id
        )
    }

    private enum CarouselDragAxis {
        case horizontal
        case vertical
    }

    private struct TrackSyncKey: Equatable {
        let orderedIDs: [Appointment.ID]
        let activeID: Appointment.ID
        let step: CGFloat
    }
}

private struct AppointmentCardCarouselSurface<CarouselGesture: Gesture>: View {
    @Environment(Router.self) private var router

    let items: [AppointmentDetails]
    let activeDetails: AppointmentDetails
    let activeIndex: Int
    let trackPosition: CGFloat
    let step: CGFloat
    @Bindable var presentation: DetailsPresentation
    let pathBinding: Binding<[Route]>
    let isUpdatingStatus: Bool
    let metrics: TraySurfaceMetrics
    let renderedScale: CGFloat
    let onNavigate: @MainActor @Sendable (Route) -> Void
    let onComplete: @MainActor () -> Void
    let onCancel: @MainActor () async -> Void
    let onDismiss: () -> Void
    let carouselGesture: CarouselGesture

    private var showsScheduledActions: Bool {
        activeDetails.appointment.status == .scheduled
    }

    var body: some View {
        let cardWidth = AppointmentCarouselMotion.cardWidth(in: metrics.size.width)
        let isAtRoot = presentation.path.isEmpty
        let windowRange = AppointmentCarouselMotion.windowIndices(
            around: activeIndex, count: items.count)
        let windowEntries = windowRange.map { CarouselWindowEntry(index: $0, details: items[$0]) }

        NavigationStack(path: pathBinding) {
            VStack(spacing: 12) {
                // Keep a matching non-interactive card inside NavigationStack for exact slot
                // measurement and native push/pop transitions while the floating layer draws root.
                AppointmentDetailsCard(
                    appointment: activeDetails.appointment,
                    variant: .standard(
                        patient: activeDetails.patient,
                        onSelectPatient: nil
                    )
                )
                .frame(width: cardWidth)
                .opacity(isAtRoot ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .anchorPreference(key: CardSlotAnchorKey.self, value: .bounds) { $0 }

                AppointmentDetailsActionsView(
                    showsActions: showsScheduledActions,
                    isUpdating: isUpdatingStatus,
                    onComplete: onComplete,
                    onReschedule: {
                        router.requestAppointmentEdit(activeDetails)
                    },
                    onCancel: onCancel
                )
                .frame(width: cardWidth)
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppColor.canvas)
            .contentShape(.rect)
            // High priority cancels child button taps once a drag begins.
            .highPriorityGesture(
                carouselGesture,
                including: isAtRoot ? .all : .subviews
            )
            .navigationTitle("Appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isAtRoot {
                        Button("Close", systemImage: "xmark", action: onDismiss)
                            .labelStyle(.iconOnly)
                            .disabled(presentation.isSavingCompletion)
                    }
                }
                if showsScheduledActions {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            "Send Appointment Confirmation",
                            systemImage: "arrow.up.message"
                        ) {
                            router.requestAppointmentMessage(activeDetails)
                        }
                        .labelStyle(.iconOnly)
                        .glassEffectTransition(.materialize)
                    }
                }
            }
            .animation(.smooth(duration: 0.28), value: showsScheduledActions)
            .navigationDestination(for: Route.self) { route in
                DetailsRouteView(
                    route: route,
                    presentationID: presentation.id,
                    completionDrafts: presentation.completionDrafts,
                    onNavigate: onNavigate
                )
            }
        }
        // The standalone navigation bar supplies ten points of top space. Add six to
        // match the native sheet's sixteen-point header without changing its controls.
        .padding(.top, 6)
        .safeAreaPadding(.bottom, metrics.bottomInset + metrics.keyboardHeight)
        .modifier(
            TrayFrame(
                topEdge: metrics.topEdge, size: metrics.size, safeArea: metrics.safeArea,
                showsIndicator: metrics.showsIndicator)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tray-surface")
        // Render the 1-3 carousel cards outside TrayFrame's clipShape so prev/next cards
        // overflow the tray edges and float over the tray surface.
        .overlayPreferenceValue(CardSlotAnchorKey.self) { anchor in
            FloatingAppointmentCardTrack(
                anchor: anchor,
                isAtRoot: isAtRoot,
                windowEntries: windowEntries,
                activeID: activeDetails.id,
                cardWidth: cardWidth,
                renderedScale: renderedScale,
                containerWidth: metrics.size.width,
                step: step,
                trackPosition: trackPosition,
                onNavigate: onNavigate,
                carouselGesture: carouselGesture
            )
        }
    }
}

private struct FloatingAppointmentCardTrack<CarouselGesture: Gesture>: View {
    let anchor: Anchor<CGRect>?
    let isAtRoot: Bool
    let windowEntries: [CarouselWindowEntry]
    let activeID: Appointment.ID
    let cardWidth: CGFloat
    let renderedScale: CGFloat
    let containerWidth: CGFloat
    let step: CGFloat
    let trackPosition: CGFloat
    let onNavigate: @MainActor @Sendable (Route) -> Void
    let carouselGesture: CarouselGesture

    var body: some View {
        GeometryReader { proxy in
            if isAtRoot, let anchor {
                let slotRect = proxy[anchor]
                ZStack(alignment: .top) {
                    ForEach(windowEntries) { entry in
                        let isActive = entry.details.id == activeID
                        AppointmentDetailsCard(
                            appointment: entry.details.appointment,
                            variant: .standard(
                                patient: entry.details.patient,
                                onSelectPatient: selectAction(for: entry.details, isActive: isActive)
                            )
                        )
                        .frame(width: cardWidth)
                        .scaleEffect(renderedScale, anchor: .top)
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
                        .allowsHitTesting(isActive)
                        .accessibilityHidden(!isActive)
                        .offset(x: CGFloat(entry.index) * step)
                    }
                }
                .offset(x: -trackPosition)
                .frame(width: containerWidth, height: slotRect.height, alignment: .top)
                .contentShape(.rect)
                // High priority cancels child button taps (View Patient, Add contact) on swipe.
                .highPriorityGesture(carouselGesture)
                .offset(y: slotRect.minY)
            }
        }
    }

    private func selectAction(
        for details: AppointmentDetails,
        isActive: Bool
    ) -> AppointmentDetailsCard.Action? {
        guard isActive else { return nil }
        let patientID = details.patient.id
        return { onNavigate(.patient(patientID)) }
    }
}

private struct CardSlotAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

private struct CarouselWindowEntry: Identifiable {
    let index: Int
    let details: AppointmentDetails

    var id: Appointment.ID { details.id }
}

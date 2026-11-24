import SwiftUI

struct TrayHost<Item: Identifiable & Sendable, TrayContent: View>: ViewModifier
where Item.ID == UUID {
    @Binding var item: Item?
    let usesCustomSurface: (Item) -> Bool
    let didAppear: (UUID) -> Void
    let didDismiss: (UUID) -> Void
    @ViewBuilder let trayContent: (Item) -> TrayContent
    @State private var state = TrayState<Item>()

    func body(content: Content) -> some View {
        content
            .disabled(state.item != nil)
            .ignoresSafeArea(.keyboard, edges: state.item == nil ? [] : .bottom)
            .overlay {
                GeometryReader { keyboardContainer in
                    GeometryReader { container in
                        GeometryReader { geometry in
                            if let retained = state.item {
                                let surfaceID = state.surfaceID
                                TraySurface(
                                    item: retained, surfaceID: surfaceID,
                                    phase: state.phase,
                                    usesCustomSurface: usesCustomSurface(retained),
                                    content: trayContent,
                                    dismiss: TrayDismissAction(
                                        id: surfaceID,
                                        isCurrent: {
                                            item?.id == retained.id
                                                && state.surfaceID == surfaceID
                                                && state.phase != .exiting(surfaceID)
                                        },
                                        dismiss: { item = nil }),
                                    size: geometry.size, safeArea: container.safeAreaInsets,
                                    keyboardHeight: max(
                                        0,
                                        keyboardContainer.safeAreaInsets.bottom
                                            - container.safeAreaInsets.bottom),
                                    didEnter: { state.finishEntry(surfaceID) },
                                    didExit: {
                                        guard state.finishExit(surfaceID) else { return }
                                        didDismiss(retained.id)
                                        state.update(item, didAppear: didAppear)
                                    }
                                )
                                .id(surfaceID)
                            }
                        }
                        .ignoresSafeArea()
                    }
                    // Compare keyboard-safe and full containers without measuring live screen content.
                    // The tray grows under the keyboard while its lower edge stays in place.
                    .ignoresSafeArea(.keyboard)
                }
            }
            .onChange(of: item?.id, initial: true) {
                state.update(item, didAppear: didAppear)
            }
    }
}

extension View {
    func tray<Item: Identifiable & Sendable, Content: View>(
        item: Binding<Item?>,
        usesCustomSurface: @escaping (Item) -> Bool = { _ in false },
        didAppear: @escaping (UUID) -> Void = { _ in },
        didDismiss: @escaping (UUID) -> Void = { _ in },
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View where Item.ID == UUID {
        modifier(
            TrayHost(
                item: item, usesCustomSurface: usesCustomSurface,
                didAppear: didAppear, didDismiss: didDismiss,
                trayContent: content))
    }
}
private struct TraySurface<Item: Identifiable & Sendable, Content: View>: View
where Item.ID == UUID {
    let item: Item
    let surfaceID: UUID
    let phase: TrayState<Item>.Phase
    let usesCustomSurface: Bool
    @ViewBuilder let content: (Item) -> Content
    let dismiss: TrayDismissAction
    let size: CGSize
    let safeArea: EdgeInsets
    let keyboardHeight: CGFloat
    let didEnter: () -> Void
    let didExit: () -> Void

    @State private var isVisible = false
    @State private var dragOffset: CGFloat = 0
    @State private var headerDragLockedVertical: Bool?
    @State private var options: TrayOptions?

    private var animates: Bool {
        #if DEBUG
            // UIKit's animation switch does not stop SwiftUI tray motion during UI tests.
            !CommandLine.arguments.contains(where: { $0.hasPrefix("--ui-testing-") })
        #else
            true
        #endif
    }

    var body: some View {
        let layout = TrayLayout.resolve(
            sizing: options?.size ?? .full,
            size: size, topInset: safeArea.top, bottomInset: safeArea.bottom,
            keyboardHeight: keyboardHeight)
        let surfaceMetrics = TraySurfaceMetrics(
            topEdge: layout.topEdge, size: size, safeArea: safeArea,
            bottomInset: layout.bottomInset, keyboardHeight: keyboardHeight,
            showsIndicator: options?.showsIndicator ?? true,
            animates: animates)
        ZStack(alignment: .bottom) {
            Button {
                requestInteractiveDismiss()
            } label: {
                Color.black.opacity(isVisible ? 0.2 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tray")
            .accessibilityIdentifier("tray-outside")

            TraySurfaceBody(
                usesCustomSurface: usesCustomSurface,
                layout: layout,
                size: size,
                safeArea: safeArea,
                keyboardHeight: keyboardHeight,
                showsIndicator: options?.showsIndicator ?? true
            ) {
                content(item)
                    .trayOptions(size: .full)
                    .environment(\.trayDismiss, dismiss)
                    .environment(\.traySurfaceMetrics, surfaceMetrics)
                    .overlayPreferenceValue(TrayOptionsKey.self) { value in
                        Color.clear
                            .onAppear { options = value }
                            .onChange(of: value?.size) { options = value }
                            .onChange(of: value?.allowsInteractiveDismiss) { options = value }
                            .onChange(of: value?.showsIndicator) { options = value }
                            .onChange(of: value?.dismiss.id) { options = value }
                            .allowsHitTesting(false)
                    }
            }
            // Entry frames move. Expose content to automation once its frame is stable.
            .accessibilityHidden(phase != .visible(surfaceID))
            .offset(
                y: isVisible ? dragOffset : layout.height * layout.scale + layout.bottomMargin
            )
            .animation(
                animates && phase == .visible(surfaceID)
                    ? .spring(duration: 0.28, bounce: 0) : nil,
                value: options?.size
            )
            .allowsHitTesting(phase != .exiting(surfaceID))
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard value.startLocation.y < 70, canDismissInteractively
                        else { return }
                        if headerDragLockedVertical == nil {
                            let dx = abs(value.translation.width)
                            let dy = abs(value.translation.height)
                            guard max(dx, dy) >= 6 else { return }
                            headerDragLockedVertical = dy >= dx
                        }
                        guard headerDragLockedVertical == true else { return }
                        dragOffset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        let wasVertical = headerDragLockedVertical == true
                        headerDragLockedVertical = nil
                        guard value.startLocation.y < 70, wasVertical else {
                            if dragOffset != 0 {
                                withAnimation(animates ? .spring(duration: 0.24, bounce: 0) : nil) {
                                    dragOffset = 0
                                }
                            }
                            return
                        }
                        endDrag(value)
                    }
            )
        }
        .frame(width: size.width, height: size.height)
        .onAppear { enterIfReady() }
        .onChange(of: options?.size) { enterIfReady() }
        .onChange(of: phase, initial: true) {
            guard phase == .exiting(surfaceID) else { return }
            withAnimation(animates ? .easeIn(duration: 0.13) : nil, completionCriteria: .removed) {
                isVisible = false
                dragOffset = 0
            } completion: {
                didExit()
            }
        }
    }

    private func enterIfReady() {
        // Keep the surface offscreen until the feature supplies its size.
        guard !isVisible, phase == .entering(surfaceID),
            options != nil
        else { return }
        withAnimation(
            animates ? .spring(duration: 0.24, bounce: 0) : nil, completionCriteria: .removed
        ) {
            isVisible = true
        } completion: {
            didEnter()
        }
    }

    private var canDismissInteractively: Bool {
        dismiss.isCurrent() && (options?.dismiss.isCurrent() ?? false)
            && (options?.allowsInteractiveDismiss ?? false)
    }

    private func requestInteractiveDismiss() {
        guard canDismissInteractively else { return }
        if let options { options.requestDismiss() } else { dismiss() }
    }

    private func endDrag(_ value: DragGesture.Value) {
        if TrayDrag.shouldDismiss(
            translation: value.translation, predicted: value.predictedEndTranslation),
            canDismissInteractively
        {
            requestInteractiveDismiss()
        }
        withAnimation(animates ? .spring(duration: 0.24, bounce: 0) : nil) { dragOffset = 0 }
    }
}

private struct TraySurfaceBody<Content: View>: View {
    let usesCustomSurface: Bool
    let layout: TrayLayout
    let size: CGSize
    let safeArea: EdgeInsets
    let keyboardHeight: CGFloat
    let showsIndicator: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if usesCustomSurface {
            content()
        } else {
            content()
                // The standalone navigation bar supplies ten points of top space. Add six to
                // match the native sheet's sixteen-point header without changing its controls.
                .padding(.top, 6)
                .safeAreaPadding(.bottom, layout.bottomInset + keyboardHeight)
                .modifier(
                    TrayFrame(
                        topEdge: layout.topEdge, size: size, safeArea: safeArea,
                        showsIndicator: showsIndicator)
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("tray-surface")
        }
    }
}

struct TrayFrame: ViewModifier, Animatable {
    var topEdge: CGFloat
    let size: CGSize
    let safeArea: EdgeInsets
    let showsIndicator: Bool

    var animatableData: CGFloat {
        get { topEdge }
        set { topEdge = newValue }
    }

    func body(content: Content) -> some View {
        let layout = TrayLayout.rendered(
            topEdge: topEdge, size: size, topInset: safeArea.top, bottomInset: safeArea.bottom)
        content
            .frame(width: size.width, height: layout.height)
            .background(AppColor.canvas)
            .overlay(alignment: .top) { TrayHeader(showsIndicator: showsIndicator) }
            .clipShape(
                .rect(
                    topLeadingCorner: .fixed(38), topTrailingCorner: .fixed(38),
                    bottomLeadingCorner: .concentric(minimum: 38),
                    bottomTrailingCorner: .concentric(minimum: 38))
            )
            .scaleEffect(layout.scale, anchor: .bottom)
            .padding(.bottom, layout.bottomMargin)
    }
}

private struct TrayHeader: View {
    let showsIndicator: Bool

    var body: some View {
        Color.clear
            .frame(height: 16)
            .overlay {
                if showsIndicator {
                    Capsule()
                        .fill(.secondary.opacity(0.4))
                        .frame(width: 36, height: 5)
                }
            }
        // TODO: Add manual height resizing in a separate change.
    }
}

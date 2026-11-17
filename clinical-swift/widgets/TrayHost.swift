import SwiftUI

struct TrayHost<Item: Identifiable & Sendable, TrayContent: View>: ViewModifier
where Item.ID == UUID {
    @Binding var item: Item?
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
                                    phase: state.phase, content: trayContent,
                                    dismiss: TrayDismissAction(
                                        id: surfaceID,
                                        isCurrent: {
                                            item?.id == retained.id
                                                && state.surfaceID == surfaceID
                                                && state.phase != .exiting(surfaceID)
                                        },
                                        dismiss: { item = nil }),
                                    size: geometry.size, safeArea: container.safeAreaInsets,
                                    keyboardHeight: keyboardContainer.safeAreaInsets.bottom
                                        > container.safeAreaInsets.bottom
                                        ? keyboardContainer.safeAreaInsets.bottom : 0,
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
        didAppear: @escaping (UUID) -> Void = { _ in },
        didDismiss: @escaping (UUID) -> Void = { _ in },
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View where Item.ID == UUID {
        modifier(
            TrayHost(
                item: item, didAppear: didAppear, didDismiss: didDismiss,
                trayContent: content))
    }
}
private struct TraySurface<Item: Identifiable & Sendable, Content: View>: View
where Item.ID == UUID {
    let item: Item
    let surfaceID: UUID
    let phase: TrayState<Item>.Phase
    @ViewBuilder let content: (Item) -> Content
    let dismiss: TrayDismissAction
    let size: CGSize
    let safeArea: EdgeInsets
    let keyboardHeight: CGFloat
    let didEnter: () -> Void
    let didExit: () -> Void

    @State private var isVisible = false
    @State private var dragOffset: CGFloat = 0
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

            content(item)
                .environment(\.trayDismiss, dismiss)
                .overlayPreferenceValue(TrayOptionsKey.self) { value in
                    Color.clear
                        .onAppear { options = value }
                        .onChange(of: value?.size) { options = value }
                        .onChange(of: value?.allowsInteractiveDismiss) { options = value }
                        .onChange(of: value?.showsIndicator) { options = value }
                        .onChange(of: value?.dismiss.id) { options = value }
                        .allowsHitTesting(false)
                }
                // The standalone navigation bar supplies ten points of top space. Add six to
                // match the native sheet's sixteen-point header without changing its controls.
                .padding(.top, 6)
                .safeAreaPadding(.bottom, layout.bottomInset + keyboardHeight)
                .modifier(
                    TrayFrame(
                        topEdge: layout.topEdge, size: size, safeArea: safeArea,
                        showsIndicator: options?.showsIndicator ?? true)
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("tray-surface")
                // Entry frames move. Expose content to automation once its frame is stable.
                .accessibilityHidden(phase != .visible(surfaceID))
                .offset(
                    y: isVisible ? dragOffset : layout.height * layout.scale + layout.bottomMargin
                )
                .animation(
                    animates ? .spring(duration: 0.28, bounce: 0) : nil, value: options?.size
                )
                .allowsHitTesting(phase != .exiting(surfaceID))
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard value.startLocation.y < 70, canDismissInteractively
                            else { return }
                            dragOffset = max(0, value.translation.height)
                        }
                        .onEnded { value in
                            guard value.startLocation.y < 70 else { return }
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

private struct TrayFrame: ViewModifier, Animatable {
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

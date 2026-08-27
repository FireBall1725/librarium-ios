// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// A panel that slides in from one edge.
///
/// The web client puts saved views down the left of the page and the filters
/// down the right. A phone has no room for either permanently, but the
/// left-is-views, right-is-filters mapping is worth keeping: it is the same
/// spatial arrangement, and someone who uses both clients does not have to
/// learn a second one.
///
/// A sheet was the first attempt and a chip row before that. The chip row does
/// not survive twenty saved views, and a sheet gives no sense of which side a
/// thing lives on.
struct SideDrawer<Content: View>: View {
    enum Edge { case leading, trailing }

    let edge: Edge
    @Binding var isOpen: Bool
    @ViewBuilder let content: () -> Content

    /// How far a drag has taken the panel while it is being closed.
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack(alignment: edge == .leading ? .leading : .trailing) {
            if isOpen {
                // Nothing at all when closed, rather than a panel pushed off
                // the edge by an offset. An offset that fails to apply leaves
                // the whole panel sitting on the page, which is a worse failure
                // than a missing animation and is exactly what happened.
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)

                panel
                    .transition(.move(edge: edge == .leading ? .leading : .trailing))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isOpen)
    }

    @ViewBuilder
    private var panel: some View {
        content()
            // Wide enough to read a list in, narrow enough that the grid stays
            // visible behind it: the counts are about what is on screen, and
            // covering all of it makes them abstract.
            .containerRelativeFrame(.horizontal) { length, _ in
                min(300, length * 0.86)
            }
            .frame(maxHeight: .infinity)
            .background(Theme.Colors.appBackgroundEleva)
            .overlay(alignment: edge == .leading ? .trailing : .leading) {
                Rectangle()
                    .fill(Theme.Colors.appLine)
                    .frame(width: 0.5)
            }
            .offset(x: drag)
            .gesture(closeGesture)
            .ignoresSafeArea(edges: .bottom)
    }

    /// Drag the open panel back toward its own edge to close it.
    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let dx = value.translation.width
                drag = edge == .leading ? min(0, dx) : max(0, dx)
            }
            .onEnded { value in
                let dx = value.translation.width
                let velocity = value.predictedEndTranslation.width - dx
                let far = abs(dx) > 90
                let flicked = edge == .leading ? velocity < -120 : velocity > 120
                drag = 0
                if far || flicked { close() }
            }
    }

    private func close() {
        drag = 0
        isOpen = false
    }
}

/// The edge grab that opens a drawer.
///
/// Attached to the page rather than to the drawer, because a closed drawer has
/// no width to be grabbed. Restricted to a strip at the edge so a horizontal
/// flick in the middle of the grid is still just a flick.
struct DrawerEdgeGesture: ViewModifier {
    @Binding var openLeading: Bool
    @Binding var openTrailing: Bool
    /// Off inside a pushed screen, where a drag from the left edge is the
    /// system's back gesture and worth more than a drawer.
    var enabled = true

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard enabled else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    // Horizontal, and decisively so. A diagonal drag while
                    // scrolling a grid should scroll the grid.
                    guard abs(dx) > abs(dy) * 1.8 else { return }
                    if dx > 60 { openLeading = true }
                    if dx < -60 { openTrailing = true }
                }
        )
    }
}

extension View {
    func drawerEdges(leading: Binding<Bool>, trailing: Binding<Bool>, enabled: Bool = true) -> some View {
        modifier(DrawerEdgeGesture(openLeading: leading, openTrailing: trailing, enabled: enabled))
    }
}

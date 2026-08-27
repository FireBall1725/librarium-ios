// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Every filter the collection can be narrowed by, with what each would return.
///
/// The web client puts these in a rail down the side of the page. A rail is a
/// desk shape: it assumes a spare 260 points of width that a phone does not
/// have. The dimensions, their order, and their counts are the same; the
/// container is a sheet, and what is currently on shows as pills above the
/// grid so the filter stays legible without opening anything.
struct BrowseFilterSheet: View {
    @Binding var selection: BrowseSelection
    let facets: BookFacets
    /// Called on every change rather than on dismiss. The counts are only worth
    /// having if they move as the selection does, and that means a round trip
    /// per tap.
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(BrowseFacet.allCases) { facet in
                    let values = facets[facet]
                    if !values.isEmpty {
                        Section {
                            ForEach(values) { value in
                                row(facet, value)
                            }
                        } header: {
                            Label(facet.title, systemImage: facet.icon)
                                .font(Theme.Fonts.ui(12, weight: .semibold))
                                .foregroundStyle(Theme.Colors.appText3)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.appBackground)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        selection.clear()
                        onChange()
                    }
                    // Not hidden when nothing is on. A control that appears
                    // only once there is something to clear moves the other
                    // buttons under the reader's thumb as they tick things.
                    .disabled(selection.activeCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ facet: BrowseFacet, _ value: FacetValue) -> some View {
        let on = selection[facet].contains(value.value)
        Button {
            selection.toggle(facet, value.value)
            onChange()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.Colors.accent : Theme.Colors.appText3)
                    .font(.system(size: 17))
                Text(FacetLabels.label(facet, value))
                    .font(Theme.Fonts.ui(15))
                    .foregroundStyle(Theme.Colors.appText)
                Spacer(minLength: 8)
                Text("\(value.count)")
                    .font(Theme.Fonts.ui(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.appText3)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.Colors.appCard)
    }
}

// MARK: - Active filters

/// What is currently on, as pills under the search field.
///
/// Each one removes its own filter when tapped. Without this the only way to
/// tell a filtered grid from an empty shelf is to open the sheet and read it,
/// and "why can I only see nine books" is the question that produces.
struct ActiveFilterPills: View {
    @Binding var selection: BrowseSelection
    let facets: BookFacets
    let onChange: () -> Void

    var body: some View {
        let pills = active
        if !pills.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pills, id: \.id) { pill in
                        Button {
                            selection.toggle(pill.facet, pill.value)
                            onChange()
                        } label: {
                            HStack(spacing: 5) {
                                Text(pill.label)
                                    .font(Theme.Fonts.ui(13, weight: .medium))
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(Theme.Colors.accentStrong)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.Colors.accentSoft))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove filter \(pill.label)")
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private struct Pill: Identifiable {
        let facet: BrowseFacet
        let value: String
        let label: String
        var id: String { facet.rawValue + "/" + value }
    }

    /// Ownership at its default produces no pill. Everyone browsing their own
    /// shelf would carry an "On the shelf" chip they never asked for, and a
    /// pill that is always there stops meaning anything.
    private var active: [Pill] {
        var out: [Pill] = []
        for facet in BrowseFacet.allCases {
            let vals = selection[facet]
            if vals.isEmpty { continue }
            if facet == .ownership && vals == BrowseSelection.defaultOwnership { continue }
            let known = Dictionary(uniqueKeysWithValues: facets[facet].map { ($0.value, $0) })
            for value in vals.sorted() {
                // Falling back to the raw value matters: a filter can outlive
                // the count that named it, and a pill with no label is a filter
                // the reader cannot find or remove.
                let fv = known[value] ?? FacetValue(value: value, label: value, count: 0)
                out.append(Pill(facet: facet, value: value, label: FacetLabels.label(facet, fv)))
            }
        }
        return out
    }
}

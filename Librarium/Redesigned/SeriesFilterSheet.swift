// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// The same sheet as the books filter, narrowed to what a run can be narrowed
/// by. Kept as its own type rather than made generic: the two share a shape and
/// nothing else, and one dimension here has no server behind it at all.
/// The series filters, in a drawer on the right.
struct SeriesFilterPanel: View {
    @Binding var selection: SeriesSelection
    let facets: SeriesFacets
    let onChange: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Filter")
                    .font(Theme.Fonts.display(20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                Spacer()
                Button("Clear") {
                    selection.clear()
                    onChange()
                }
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(selection.activeCount == 0 ? Theme.Colors.appText3 : Theme.Colors.accent)
                .disabled(selection.activeCount == 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Colors.appText3)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            SeriesFilterSheet(
                selection: $selection, facets: facets,
                onChange: onChange, embedded: true
            )
        }
    }
}

struct SeriesFilterSheet: View {
    @Binding var selection: SeriesSelection
    let facets: SeriesFacets
    let onChange: () -> Void
    var embedded = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if embedded {
            list
        } else {
            NavigationStack {
                list
                    .navigationTitle("Filter")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Clear") {
                                selection.clear()
                                onChange()
                            }
                            .disabled(selection.activeCount == 0)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        Group {
            List {
                Section {
                    Button {
                        selection.incompleteOnly.toggle()
                        onChange()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selection.incompleteOnly ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.incompleteOnly ? Theme.Colors.accent : Theme.Colors.appText3)
                                .font(.system(size: 17))
                            Text("Only runs with gaps")
                                .font(Theme.Fonts.ui(15))
                                .foregroundStyle(Theme.Colors.appText)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.Colors.appCard)
                } header: {
                    Label("Missing volumes", systemImage: "questionmark.square.dashed")
                        .font(Theme.Fonts.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText3)
                } footer: {
                    // Said out loud because it is the one filter here the
                    // server does not compute, and it can only answer for runs
                    // whose length somebody knows.
                    Text("A run with no known length cannot be missing anything.")
                        .font(Theme.Fonts.ui(11))
                        .foregroundStyle(Theme.Colors.appText3)
                }

                ForEach(SeriesFacet.allCases) { facet in
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.appBackground)
        }
    }

    @ViewBuilder
    private func row(_ facet: SeriesFacet, _ value: FacetValue) -> some View {
        let on = selection[facet].contains(value.value)
        Button {
            selection.toggle(facet, value.value)
            onChange()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.Colors.accent : Theme.Colors.appText3)
                    .font(.system(size: 17))
                Text(SeriesFacetLabels.label(facet, value))
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

/// What is currently narrowing the list, as pills under the search field.
struct SeriesFilterPills: View {
    @Binding var selection: SeriesSelection
    let facets: SeriesFacets
    let onChange: () -> Void

    var body: some View {
        let pills = active
        if !pills.isEmpty || selection.incompleteOnly {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if selection.incompleteOnly {
                        pill("With gaps") {
                            selection.incompleteOnly = false
                            onChange()
                        }
                    }
                    ForEach(pills, id: \.id) { p in
                        pill(p.label) {
                            selection.toggle(p.facet, p.value)
                            onChange()
                        }
                    }
                }
                .padding(.horizontal, 22)
            }
        }
    }

    @ViewBuilder
    private func pill(_ label: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(label)
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
        .accessibilityLabel("Remove filter \(label)")
    }

    private struct Pill: Identifiable {
        let facet: SeriesFacet
        let value: String
        let label: String
        var id: String { facet.rawValue + "/" + value }
    }

    private var active: [Pill] {
        var out: [Pill] = []
        for facet in SeriesFacet.allCases {
            let known = Dictionary(uniqueKeysWithValues: facets[facet].map { ($0.value, $0) })
            for value in selection[facet].sorted() {
                let fv = known[value] ?? FacetValue(value: value, label: value, count: 0)
                out.append(Pill(facet: facet, value: value,
                                label: SeriesFacetLabels.label(facet, fv)))
            }
        }
        return out
    }
}

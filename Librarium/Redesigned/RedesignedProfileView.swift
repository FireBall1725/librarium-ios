// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Redesigned Profile — mockup card #8.
///
/// Profile head (avatar + name + admin badge) → reading stats strip →
/// Servers list (status + per-server library count, tap to switch primary,
/// "Add a server" row at the bottom) → App section (legacy account
/// management for advanced changes, sign out, version with redesign-flag
/// long-press toggle).
///
/// AI tuning + My reviews + a dedicated Change-password sheet from the
/// mockup are deferred — the legacy `ProfileView` Form covers password
/// changes, accessible via the "Manage primary server" row.
struct RedesignedProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RedesignFlag.key) private var redesignEnabled = false

    @State private var vm = RedesignedProfileViewModel()
    @State private var showAddServer = false
    @State private var manageAccount: ServerAccount?
    @State private var confirmRemove: ServerAccount?
    @State private var confirmSignOut = false
    @State private var redesignToastVisible = false

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileHead
                    if vm.stats != nil || vm.statsLoading {
                        profileStrip
                    }
                    serversSection
                    appSection
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) {
                if redesignToastVisible {
                    redesignToast
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            withAnimation { redesignToastVisible = false }
                        }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: redesignToastVisible)
        .task { await vm.load(appState: appState) }
        .refreshable { await vm.load(appState: appState) }
        .sheet(isPresented: $showAddServer) {
            NavigationStack {
                AddServerView(isFirstTime: false) {
                    Task { await vm.load(appState: appState) }
                }
            }
        }
        .sheet(item: $manageAccount) { account in
            NavigationStack {
                ProfileView(account: account)
            }
        }
        .confirmationDialog(
            "Remove server?",
            isPresented: Binding(
                get: { confirmRemove != nil },
                set: { if !$0 { confirmRemove = nil } }
            ),
            presenting: confirmRemove
        ) { account in
            Button("Remove \(account.name)", role: .destructive) {
                appState.removeAccount(id: account.id)
                Task { await vm.load(appState: appState) }
            }
        } message: { account in
            Text("This signs you out of \(account.name) and clears its cached libraries on this device. The server itself isn't affected.")
        }
        .confirmationDialog(
            "Sign out of all servers?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                appState.logout()
            }
        } message: {
            Text("Removes every server from this device. You'll need to add them again to use the app.")
        }
    }

    // MARK: - Profile head

    @ViewBuilder
    private var profileHead: some View {
        let primary = vm.primaryAccount(appState: appState)
        let displayName = primary?.user.displayName.isEmpty == false
            ? primary!.user.displayName
            : (primary?.user.username ?? "")
        let initial = String(displayName.prefix(1)).uppercased()

        HStack(alignment: .center, spacing: 14) {
            ZStack {
                LinearGradient(
                    colors: [Theme.Colors.accent, Color(hex: 0x5a64e8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Text(initial.isEmpty ? "?" : initial)
                    .font(Theme.Fonts.display(28, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName.isEmpty ? "Sign in to see your profile" : displayName)
                    .font(Theme.Fonts.heroTitle)
                    .foregroundStyle(Theme.Colors.appText)
                if primary?.user.isInstanceAdmin == true {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Colors.gold)
                        Text("Instance admin")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.gold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0xf3c971, opacity: 0.15), in: Capsule())
                }
            }
            Spacer()
            // Close button — Profile is presented as a sheet from the
            // Home tab's avatar; without an explicit dismiss, users
            // who don't notice the swipe-down handle are stuck.
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 20)
    }

    // MARK: - Profile strip (stats)

    @ViewBuilder
    private var profileStrip: some View {
        let stats = vm.stats
        HStack(spacing: 0) {
            stripCell(value: stats?.booksRead.formatted() ?? "—", label: "Read")
            stripDivider
            stripCell(value: stats?.booksReading.formatted() ?? "—", label: "Reading")
            stripDivider
            stripCell(value: vm.unreadCount.map { $0.formatted() } ?? "—", label: "Unread")
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.Colors.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.Colors.appLine, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func stripCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.Fonts.display(22, weight: .bold))
                .foregroundStyle(Theme.Colors.appText)
                .monospacedDigit()
            Text(label.uppercased())
                .font(Theme.Fonts.label(10))
                .tracking(1.2)
                .foregroundStyle(Theme.Colors.appText3)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var stripDivider: some View {
        Rectangle()
            .fill(Theme.Colors.appLine)
            .frame(width: 0.5, height: 28)
    }

    // MARK: - Servers section

    @ViewBuilder
    private var serversSection: some View {
        menuSection(title: "Servers") {
            VStack(spacing: 0) {
                ForEach(appState.accounts) { account in
                    serverRow(account: account)
                    if account.id != appState.accounts.last?.id {
                        Divider().background(Theme.Colors.appLine)
                    }
                }
                if !appState.accounts.isEmpty {
                    Divider().background(Theme.Colors.appLine)
                }
                addServerRow
            }
        }
    }

    @ViewBuilder
    private func serverRow(account: ServerAccount) -> some View {
        let isPrimary = appState.primaryAccountID == account.id
        let status = vm.status(for: account)

        Button {
            // Tap to make primary; long-press / swipe is for management.
            // Switching primary is the most common server action and the
            // cheapest to do with one hand.
            if !isPrimary {
                appState.setPrimaryAccount(id: account.id)
                Task { await vm.load(appState: appState) }
            } else {
                manageAccount = account
            }
        } label: {
            HStack(spacing: 12) {
                serverAvatar(name: account.name, primary: isPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(account.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Colors.appText)
                            .lineLimit(1)
                        if isPrimary {
                            Text("PRIMARY")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(Theme.Colors.accentStrong)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.accentSoft, in: Capsule())
                        }
                    }
                    HStack(spacing: 5) {
                        Circle().fill(status.dot).frame(width: 6, height: 6)
                        Text(status.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(status.dot)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let count = vm.libraryCount(for: account) {
                    Text(count == 1 ? "1 lib" : "\(count) libs")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Manage") { manageAccount = account }
                .tint(Theme.Colors.accent)
            Button("Remove", role: .destructive) { confirmRemove = account }
        }
    }

    @ViewBuilder
    private func serverAvatar(name: String, primary: Bool) -> some View {
        let initial = String(name.prefix(1)).uppercased()
        ZStack {
            if primary {
                LinearGradient(
                    colors: [Theme.Colors.accent, Color(hex: 0x5a64e8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [Color(hex: 0x4a3d28), Color(hex: 0x2a2218)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            Text(initial.isEmpty ? "?" : initial)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var addServerRow: some View {
        Button { showAddServer = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Color.white.opacity(0.06)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Add a server")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Spacer()
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - App section

    @ViewBuilder
    private var appSection: some View {
        menuSection(title: "App") {
            VStack(spacing: 0) {
                if let primary = vm.primaryAccount(appState: appState) {
                    appRow(
                        icon: "key.fill",
                        iconBg: Color(hex: 0x2a1d3a),
                        label: "Account & security",
                        right: AnyView(Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Colors.appText3))
                    ) {
                        manageAccount = primary
                    }
                    Divider().background(Theme.Colors.appLine)
                }
                appRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    iconBg: Color(hex: 0x3a1d1d),
                    label: "Sign out of all servers",
                    right: nil,
                    labelColor: Theme.Colors.bad
                ) {
                    confirmSignOut = true
                }
                Divider().background(Theme.Colors.appLine)
                versionRow
            }
        }
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func appRow(
        icon: String,
        iconBg: Color,
        label: String,
        right: AnyView?,
        labelColor: Color = Theme.Colors.appText,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    iconBg
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(labelColor == Theme.Colors.bad ? Theme.Colors.bad : Theme.Colors.appText)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(labelColor)
                Spacer()
                if let right { right }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Long-press the version row to toggle the redesign flag — same
    /// behaviour as the legacy ProfileView's "About" footer so the user
    /// can flip back without diving into Settings.
    @ViewBuilder
    private var versionRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Color(hex: 0x2a2a2c)
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText3)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("Version")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText)
            Spacer()
            Text(versionString)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
                .monospacedDigit()
        }
        .padding(14)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 1.0) {
            redesignEnabled.toggle()
            redesignToastVisible = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let marketing = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "\(marketing) (build \(build))"
    }

    @ViewBuilder
    private var redesignToast: some View {
        let label = redesignEnabled ? "Redesign preview ON" : "Redesign preview OFF"
        let icon = redesignEnabled ? "sparkles" : "circle.slash"
        Label(label, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Theme.Colors.appLine))
    }

    // MARK: - Menu section helper

    @ViewBuilder
    private func menuSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.Fonts.label(11))
                .tracking(1.4)
                .foregroundStyle(Theme.Colors.appText3)
                .padding(.horizontal, 22)
            content()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.Colors.appCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.Colors.appLine, lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 22)
        }
        .padding(.bottom, 14)
    }
}

// MARK: - View model

@Observable
final class RedesignedProfileViewModel {
    var stats: DashboardStats?
    var statsLoading = false
    /// Per-server URL → library count, populated lazily.
    var libraryCounts: [String: Int] = [:]

    func load(appState: AppState) async {
        statsLoading = true
        defer { statsLoading = false }

        // Stats from the primary server only — unread is derived from
        // total - read - reading.
        if let client = primaryClient(appState: appState) {
            if let s = try? await DashboardService(client: client).stats() {
                stats = s
            }
        }

        // Library counts per server in parallel. Best-effort; don't
        // disrupt rendering if a server is unreachable.
        await withTaskGroup(of: (String, Int?).self) { group in
            for account in appState.accounts {
                group.addTask {
                    let client = await appState.makeClient(serverURL: account.url)
                    let libs = try? await LibraryService(client: client).list()
                    return (account.url, libs?.count)
                }
            }
            for await (url, count) in group {
                if let count {
                    libraryCounts[url] = count
                }
            }
        }
    }

    func libraryCount(for account: ServerAccount) -> Int? {
        libraryCounts[account.url]
    }

    var unreadCount: Int? {
        guard let s = stats else { return nil }
        return max(0, s.totalBooks - s.booksRead - s.booksReading)
    }

    struct ServerStatus {
        let label: String
        let dot: Color
    }

    func status(for account: ServerAccount) -> ServerStatus {
        if account.needsReauth {
            return ServerStatus(label: "Sign in needed", dot: Theme.Colors.warn)
        }
        // Without an explicit per-server health check, treat any account
        // we have valid tokens for as "Connected". Refresh failures
        // bounce through `markNeedsReauth` and surface as the warning
        // case above; outright unreachable shows up via the libraries
        // grid banner instead.
        return ServerStatus(label: "Connected", dot: Theme.Colors.good)
    }

    func primaryAccount(appState: AppState) -> ServerAccount? {
        if let id = appState.primaryAccountID,
           let primary = appState.accounts.first(where: { $0.id == id }) {
            return primary
        }
        return appState.accounts.first
    }

    func primaryClient(appState: AppState) -> APIClient? {
        guard let account = primaryAccount(appState: appState) else { return nil }
        return appState.makeClient(serverURL: account.url)
    }
}

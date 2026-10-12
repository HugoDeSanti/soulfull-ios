//
//  ProfileView.swift
//  Soulfull Gatherings
//
//  The You tab: who you are, what you've practiced, and where you've been.
//
//  A member sees four numbers — current streak, best streak, classes taken,
//  minutes practiced (`PracticeStats` defines each) — then the digital
//  retreats they've joined and the in-person retreats they've been on. A guest
//  has none of that to show (every practice is behind the account gate), so
//  they're shown what an account would keep instead of a grid of zeros.
//

import SwiftUI
import PhotosUI

struct ProfileView: View {
    /// Switch to the Programs tab. A non-nil id opens that program.
    var onOpenProgram: (String?) -> Void = { _ in }
    /// Switch to Home and open the retreats stack.
    var onOpenRetreats: () -> Void = {}

    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var vm = ProfileViewModel()
    /// Only ever holds a dashboard for a member the team has linked to a guide.
    @State private var guide = GuideDashboardViewModel()
    @State private var showGuideDashboard = false
    /// Read inside `body` so the observation registers.
    private let history = PracticeProgressStore.shared

    @State private var showAccount = false
    @State private var accountMode: AccountViewModel.Mode = .createAccount
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    /// Sign-out forgets the device for push and opens a fresh guest session —
    /// a few round-trips, during which the button said nothing at all.
    @State private var isSigningOut = false
    @State private var deleteError: String?
    @State private var showPhotoOptions = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showBlocked = false
    @State private var showEditName = false

    /// Has anything of their own to show. `-preview-you` renders the member
    /// layout against fixtures without an account.
    private var isMember: Bool { auth.hasAccount || ProfileViewModel.isPreview }

    /// Reload when the person behind the session changes — including a guest
    /// upgraded in place, whose id stays the same while `hasAccount` flips.
    private var identity: String {
        "\(auth.userID?.uuidString ?? "none")|\(auth.hasAccount)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.top, 28)

                if isMember {
                    VStack(spacing: Theme.sectionGap) {
                        if let dashboard = guide.dashboard {
                            guideSection(dashboard)
                        }
                        practiceSection
                        digitalSection
                        inPersonSection
                        communitySection
                    }
                    .padding(.top, Theme.headerGap)
                } else {
                    guestInvitation
                        .padding(.top, Theme.headerGap)
                }

                VStack(spacing: 16) {
                    accountActions
                    legalLinks
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, Theme.sectionGap)

                Color.clear.frame(height: 120)
            }
        }
        .scrollIndicators(.hidden)
        .statusBarFade()
        .refreshable {
            guard isMember else { return }
            async let mine: Void = vm.load(force: true, settings: settings)
            async let guiding: Void = guide.load(for: identity)
            _ = await (mine, guiding)
        }
        .background { PhotoBackdrop(imageName: "home-bg", blur: 4, darken: 0.7) }
        .task(id: identity) {
            // A guest has nothing to load, but whatever the last member left
            // here still has to go — their sharing answer included.
            guard isMember else { vm.reset(); guide.reset(); return }
            async let mine: Void = vm.load(settings: settings)
            async let guiding: Void = guide.load(for: identity)
            _ = await (mine, guiding)
        }
        .sheet(isPresented: $showGuideDashboard) {
            GuideDashboardView(vm: guide)
        }
        .sheet(isPresented: $showBlocked) {
            BlockedMembersView()
        }
        .sheet(isPresented: $showEditName) {
            EditNameSheet(vm: EditNameViewModel(current: settings.name, birthDate: settings.birthDate,
                                                write: saveDetails),
                          isGuide: guide.dashboard != nil)
        }
        .sheet(isPresented: $showAccount) {
            AccountView(mode: accountMode, initialName: settings.name)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    vm.profileError = "That photo couldn't be read. Try a different one."
                    return
                }
                await vm.setAvatar(imageData: data, settings: settings)
            }
        }
        .confirmationDialog("Profile photo", isPresented: $showPhotoOptions, titleVisibility: .visible) {
            Button(settings.avatarUrl == nil ? "Choose a photo" : "Choose a new photo") {
                showPhotoPicker = true
            }
            if settings.avatarUrl != nil {
                Button("Remove photo", role: .destructive) {
                    Task { await vm.removeAvatar(settings: settings) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown beside your name in the Community feed.")
        }
        .alert("Couldn't save that", isPresented: Binding(get: { vm.profileError != nil }, set: { if !$0 { vm.profileError = nil } })) {
            Button("OK", role: .cancel) { vm.profileError = nil }
        } message: {
            Text(vm.profileError ?? "")
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, your profile and photo, your friends and likes, and the reflections saved on this phone. This can't be undone.")
        }
        .alert("Couldn't delete account", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await auth.deleteAccount()
            Haptics.success()
        } catch {
            Haptics.bump()
            Log.auth.error("Account deletion failed: \(error.localizedDescription)")
            // Offline or ours, never the raw error — that read "Edge Function
            // returned a non-2xx status code: 500". Either way the account is
            // still there, which is the one thing they need to know.
            deleteError = error.isOffline
                ? "You're offline, so your account hasn't been deleted. Reconnect and try again."
                : "Something went wrong at our end, and your account hasn't been deleted. Please try again in a moment."
        }
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        await auth.signOut()
    }

    /// The profile first, then this phone's copy (`AppSettings.name`,
    /// which greets them on Home): the profile is where the name lives, and
    /// the next sync would put the old one back on the phone otherwise.
    private func saveDetails(_ name: MemberName, _ birthDate: BirthDate?) async throws {
        guard let id = auth.userID, auth.hasAccount else { throw AppError.unknown }
        try await SupabaseService.shared.setProfileName(name, birthDate: birthDate, userID: id)
        guard auth.userID == id else { return }
        settings.name = name
        if let birthDate { settings.birthDate = birthDate }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 18) {
            if isMember {
                avatarButton
            } else {
                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 80, height: 80)
                    .breathing(scale: 1...1, opacity: 0.6...0.95)
            }
            VStack(spacing: 16) {
                if auth.hasAccount {
                    nameButton
                } else {
                    nameLine
                }
                // "Back" only for someone with an account to come back to: a
                // guest opening the tab for the first time was welcomed back.
                Text(isMember ? "Welcome back." : "Welcome.")
                    .font(Theme.headline(36, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.8)
                    .accessibilityIdentifier("profile-welcome")

                accountStatus
            }
            // This block is centred over the open sky of home-bg, the
            // brightest ground in the app — see View.onPhoto().
            .onPhoto()
            intentionsRow
        }
    }

    private var nameLine: some View {
        Text((settings.name.isEmpty ? "You" : settings.name.full).uppercased())
            .font(Theme.eyebrow(12))
            .tracking(3)
            .foregroundStyle(Theme.ink)
    }

    /// A member's name, which they can change: a small pencil says so, as the
    /// camera does on the face above it. A guest's name only lives on this
    /// phone, so theirs is just the line.
    private var nameButton: some View {
        Button {
            showEditName = true
        } label: {
            HStack(spacing: 8) {
                nameLine
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.inkSoft)
            }
            // About 44pt tall to the touch without moving anything: the
            // padding widens the shape, the negative padding hands the room
            // back to the layout (gotcha #5).
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .padding(.vertical, -14)
            .padding(.horizontal, -12)
        }
        .buttonStyle(.soulPressable)
        .accessibilityLabel(settings.name.isEmpty ? "Add your name" : "Your name, \(settings.name.full)")
        .accessibilityHint("Change the name other members see")
        .accessibilityIdentifier("profile-edit-name")
    }

    /// The member's face where the logo sits for a guest. Tapping offers a
    /// new photo or none; a small badge says it can be changed at all.
    private var avatarButton: some View {
        Button {
            Haptics.tap()
            showPhotoOptions = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(avatarUrl: settings.avatarUrl,
                           name: settings.name.full,
                           seed: auth.userID?.uuidString ?? "preview",
                           size: 92)
                    .overlay {
                        if vm.isUploadingAvatar {
                            Circle().fill(.black.opacity(0.45))
                            ProgressView().tint(Theme.ink)
                        }
                    }
                // A small square of ink at the face's shoulder: the photo
                // can be changed.
                Image(systemName: "camera")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.black)
                    .frame(width: 24, height: 24)
                    .background(Theme.ink, in: Rectangle())
                    .overlay(Rectangle().strokeBorder(Theme.bg, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.soulPressable)
        .disabled(vm.isUploadingAvatar)
        .accessibilityLabel(settings.avatarUrl == nil ? "Add a profile photo" : "Change your profile photo")
        .accessibilityIdentifier("profile-avatar")
    }

    /// What they came here for, as one quiet line — words and dots, no chips.
    @ViewBuilder
    private var intentionsRow: some View {
        let intentions = IntentionOption.all.filter { settings.intentions.contains($0.id) }
        if !intentions.isEmpty {
            Text(intentions.prefix(3).map(\.label).joined(separator: "  ·  "))
                .font(Theme.body(12))
                .tracking(0.3)
                .foregroundStyle(Theme.inkOnPhoto)
                .multilineTextAlignment(.center)
                .onPhoto()
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var accountStatus: some View {
        if isMember {
            Label(auth.email ?? "Signed in", systemImage: "checkmark.seal")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkOnPhoto)
        } else {
            Text("Guest · not signed in")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkOnPhoto)
        }
    }

    // MARK: - As a guide

    /// Only for a member the team has linked to a guide (0026): their month
    /// so far, opening onto the whole dashboard.
    private func guideSection(_ dashboard: GuideDashboard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "As a guide")
                .onPhoto()
            GuideSummaryCard(dashboard: dashboard) {
                showGuideDashboard = true
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    // MARK: - Your practice

    @ViewBuilder
    private var practiceSection: some View {
        let stats = history.stats
        let known = history.ledgerStatus == .loaded

        VStack(alignment: .leading, spacing: 24) {
            SectionLabel(title: "Your practice")
                .onPhoto()

            // Open numerals on the page, as a printed table: no tiles, a rule
            // between the two rows.
            Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 24) {
                GridRow {
                    StatTile(value: known ? stats.currentStreak : nil,
                             label: "Day streak",
                             caption: streakCaption(stats),
                             systemImage: "flame.fill",
                             accent: known && stats.currentStreak > 0,
                             breathes: known && stats.keptToday,
                             spoken: "Current streak",
                             spokenValue: known ? days(stats.currentStreak) : nil)
                        .accessibilityIdentifier("stat-current-streak")
                    StatTile(value: known ? stats.bestStreak : nil,
                             label: "Best streak",
                             caption: bestCaption(stats),
                             systemImage: "laurel.leading",
                             spoken: "Best streak",
                             spokenValue: known ? days(stats.bestStreak) : nil)
                        .accessibilityIdentifier("stat-best-streak")
                }
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 0.5)
                    .accessibilityHidden(true)
                GridRow {
                    StatTile(value: known ? stats.classesTaken : nil,
                             label: "Classes taken",
                             caption: "Sessions & movement",
                             systemImage: "figure.mind.and.body",
                             spoken: "Classes taken",
                             spokenValue: known ? "\(stats.classesTaken)" : nil)
                        .accessibilityIdentifier("stat-classes")
                    StatTile(value: known ? stats.minutesPracticed : nil,
                             label: "Minutes practiced",
                             caption: minutesCaption(stats),
                             systemImage: "hourglass",
                             spoken: "Minutes practiced",
                             spokenValue: known ? "\(stats.minutesPracticed)" : nil)
                        .accessibilityIdentifier("stat-minutes")
                }
            }
            .padding(.horizontal, Theme.gutter)

            if case .unavailable(let offline) = history.ledgerStatus {
                retryLine(ProfileLoadFailure(offline: offline))
            }
        }
    }

    private func streakCaption(_ stats: PracticeStats) -> String {
        guard history.ledgerStatus == .loaded else { return " " }
        return stats.streakCaption
    }

    private func bestCaption(_ stats: PracticeStats) -> String {
        guard history.ledgerStatus == .loaded else { return " " }
        if stats.bestStreak > 1, stats.bestStreak == stats.currentStreak { return "You're on it now" }
        return "Days in a row"
    }

    private func minutesCaption(_ stats: PracticeStats) -> String {
        guard history.ledgerStatus == .loaded, stats.minutesPracticed >= 60 else { return "Time in class" }
        return Duration.seconds(stats.minutesPracticed * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    // MARK: - Digital retreats

    private var digitalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: "Digital retreats")
                .onPhoto()

            let journeys = vm.journeys
            Group {
                if !vm.programsLoaded {
                    sectionSpinner
                } else if journeys.isEmpty, let failure = vm.programsFailure {
                    retryLine(failure)
                } else if journeys.isEmpty {
                    emptyCard(title: "Nothing joined yet",
                              detail: "Digital retreats are free, and walked one day at a time.",
                              action: "Browse digital retreats") { onOpenProgram(nil) }
                } else {
                    VStack(spacing: 0) {
                        ForEach(journeys) { journey in
                            journeyRow(journey)
                                .overlay(alignment: .top) {
                                    if journey.id != journeys.first?.id { Hairline() }
                                }
                                .listReveal()
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }

    @ViewBuilder
    private func journeyRow(_ journey: ProgramJourney) -> some View {
        let program = journey.program
        // A program taken down after they joined stays in their history but
        // can't be opened — the Programs tab has nowhere to land it.
        if program.published {
            PressableCard(action: { onOpenProgram(program.id) }) {
                journeyCard(journey, opens: true)
            }
            .accessibilityHint("Opens the digital retreat")
            .accessibilityIdentifier("journey-row")
        } else {
            journeyCard(journey, opens: false)
                .accessibilityIdentifier("journey-row")
        }
    }

    private func journeyCard(_ journey: ProgramJourney, opens: Bool) -> some View {
        HistoryRow(imageUrl: journey.program.imageUrl, opens: opens) {
            Text(journey.program.title)
                .font(Theme.headline(18, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.2)
                .lineLimit(1)
            switch journey.standing {
            case .inProgress(let day, let total, let fraction):
                HStack(spacing: 10) {
                    Text("DAY \(day) OF \(total)")
                        .font(Theme.eyebrow(10))
                        .tracking(1.6)
                        .foregroundStyle(Theme.ember)
                    ProgressRule(fraction: fraction, width: 56)
                }
            case .completed(let date):
                Label(date.map { "Completed · \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? "Completed",
                      systemImage: "checkmark.seal")
                    .font(Theme.body(12, weight: .medium))
                    // accentSoft, not accent: the deep olive sinks into black
                    // at this size. Same "done" colour the mirror's Programs
                    // chip uses.
                    .foregroundStyle(Theme.accentSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - In-person retreats

    private var inPersonSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: "In-person retreats")
                .onPhoto()

            Group {
                if !vm.retreatsLoaded {
                    sectionSpinner
                } else if vm.retreats.isEmpty, let failure = vm.retreatsFailure {
                    retryLine(failure)
                } else if vm.retreats.isEmpty {
                    emptyCard(title: "Your first gathering is ahead",
                              detail: "Once you've joined us in person, your retreats are kept here.",
                              action: "Explore retreats", perform: onOpenRetreats)
                } else {
                    VStack(spacing: 0) {
                        ForEach(vm.retreats) { retreat in
                            // Not a link: its detail screen is a booking page,
                            // and this retreat can no longer be booked.
                            HistoryRow(imageUrl: retreat.imageUrl, opens: false) {
                                Text(retreat.name)
                                    .font(Theme.headline(18, weight: .light))
                                    .foregroundStyle(Theme.ink)
                                    .kerning(-0.2)
                                Text("\(retreat.country) · \(retreat.whenWithYear)".uppercased())
                                    .font(Theme.eyebrow(10))
                                    .tracking(1.4)
                                    .foregroundStyle(Theme.inkSoft)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("past-retreat-row")
                            .overlay(alignment: .top) {
                                if retreat.id != vm.retreats.first?.id { Hairline() }
                            }
                            .listReveal()
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }

    // MARK: - Community

    /// The one switch the feed needs: whether this member appears in it. Off
    /// hides their finished practices from everyone, friends included; they
    /// stay findable and can still add and be added. Below it, the members
    /// they've blocked.
    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: "Community")
                .onPhoto()

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Share my practice")
                        .font(Theme.headline(17))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.2)
                    Text("Your finished practices appear in the Community feed as \u{201C}\(settings.name.shownInCommunity ?? "You") practiced …\u{201D}, and your face among the followers of guides you follow. Journal prompts never appear.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkOnPhoto)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onPhoto()
                Toggle("", isOn: Binding(
                    get: { vm.shareActivity ?? false },
                    set: { on in Task { await vm.setShareActivity(on) } }
                ))
                .labelsHidden()
                // Moss, as Open's switches are green.
                .tint(Theme.accentSoft)
                // Unknown until the profile row is read: dimmed and untouchable
                // rather than a position the server never confirmed.
                .disabled(vm.shareActivity == nil || vm.isSavingShare)
                .opacity(vm.shareActivity == nil ? 0.45 : 1)
                .accessibilityLabel("Share my practice in the Community feed")
                .accessibilityIdentifier("share-activity")
            }
            .padding(.vertical, 18)
            .padding(.horizontal, Theme.gutter)

            Button {
                Haptics.tap()
                showBlocked = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 22)
                    Text("Blocked members")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.ink)
                        .onPhoto()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(height: 56)
                // A rule above it, under the switch: two rows of one list.
                .overlay(alignment: .top) { Hairline() }
                .contentShape(Rectangle())
            }
            .buttonStyle(.soulPressableQuiet)
            .padding(.horizontal, Theme.gutter)
            .accessibilityHint("People you've blocked, and Unblock")
            .accessibilityIdentifier("open-blocked-members")
        }
    }

    // MARK: - Shared section states

    private var sectionSpinner: some View {
        ProgressView()
            .tint(Theme.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
    }

    private func emptyCard(title: String, detail: String, action: String,
                           perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.headline(20, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.3)
            Text(detail)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                perform()
            } label: {
                HStack(spacing: 6) {
                    Text(action)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .regular))
                }
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.ember)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.soulPressableQuiet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPhoto()
        .padding(.top, 14)
        .padding(.horizontal, Theme.gutter)
    }

    /// "Couldn't find out", as distinct from "nothing there". Retrying reloads
    /// the whole tab — it's three small reads.
    private func retryLine(_ failure: ProfileLoadFailure) -> some View {
        HStack(spacing: 10) {
            Image(systemName: failure == .offline ? "wifi.slash" : "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
            Text(failure.line)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkOnPhoto)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                Task { await vm.load(force: true, settings: settings) }
            } label: {
                Text("Try again")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.ember)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.soulPressableQuiet)
        }
        .onPhoto()
        .padding(.top, 10)
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: - Guest

    /// Every practice is behind the account gate, so a guest has no history —
    /// and four zeros would read as a verdict rather than an invitation.
    private var guestInvitation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR PRACTICE")
                .font(Theme.eyebrow(10))
                .tracking(3)
                .foregroundStyle(Theme.ember)
            Text("Keep it with you")
                .font(Theme.headline(26, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.5)
            Text("With an account, your streaks, classes and minutes gather here — alongside every retreat you join, digital or in person.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPhoto()
        // Open on the page under a rule — an invitation, not a box.
        .padding(.top, 24)
        .overlay(alignment: .top) { Hairline() }
        .padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guest-invitation")
    }

    // MARK: - Actions (sign in/up vs sign out) + dev tools

    @ViewBuilder
    private var accountActions: some View {
        VStack(spacing: 12) {
            if auth.hasAccount {
                // Each one waits for the other: a sign-out mid-deletion would
                // pull the session out from under the delete call, and a delete
                // mid-sign-out would be asked of the session being closed.
                SGPrimaryButton(title: isSigningOut ? "Signing out…" : "Sign out",
                                enabled: !isSigningOut && !isDeleting) {
                    Task { await signOut() }
                }
                Button {
                    Haptics.tap()
                    showDeleteConfirm = true
                } label: {
                    Text(isDeleting ? "Deleting…" : "Delete account")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.danger)
                        .onPhoto()
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        // The whole row, not just the letters (rendering gotcha 5).
                        .contentShape(Rectangle())
                        .opacity(isSigningOut ? 0.45 : 1)
                }
                .buttonStyle(.soulPressableQuiet)
                .accessibilityIdentifier("delete-account")
                .disabled(isDeleting || isSigningOut)
            } else {
                SGPrimaryButton(title: "Create account", filled: true) {
                    accountMode = .createAccount
                    showAccount = true
                }
                SGPrimaryButton(title: "Sign in") {
                    accountMode = .signIn
                    showAccount = true
                }
            }
            devReset
        }
    }

    // MARK: - Legal & support

    /// Privacy policy, terms, the retreat booking policy, and a way to reach a
    /// human. App Store Connect requires a resolving privacy policy URL and a
    /// support URL, and an app that creates accounts needs them reachable from
    /// inside the app — the checkout fineprint referring to "the enrollment
    /// terms" isn't enough on its own. Destinations live in `LegalLinks`.
    ///
    /// The retreat policy is here because in v1 it has nowhere else to be:
    /// `AppFeatures.paymentsEnabled` is false, so checkout — the screen that
    /// would normally carry it — is unreachable, and the retreat CTA is an
    /// email enquiry. Someone asking for a place should still be able to read
    /// the cancellation terms before they write.
    private var legalLinks: some View {
        HStack(spacing: 0) {
            legalLink("Privacy", url: LegalLinks.privacyPolicy)
            legalDivider
            legalLink("Terms", url: LegalLinks.terms)
            legalDivider
            legalLink("Retreat policy", url: LegalLinks.retreatPolicy)
            legalDivider
            legalLink("Support", url: LegalLinks.supportMail)
        }
        .padding(.top, 2)
    }

    private var legalDivider: some View {
        Text("·")
            .font(Theme.body(12))
            .foregroundStyle(Theme.inkSoft)
            .onPhoto()
            .padding(.horizontal, 7)
    }

    private func legalLink(_ title: String, url: URL) -> some View {
        Button {
            Haptics.tap()
            openURL(url)
        } label: {
            Text(title)
                .font(Theme.body(12))
                .foregroundStyle(Theme.inkSoft)
                .onPhoto()
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }

    /// Dev-only onboarding reset. Compiled out of Release builds.
    @ViewBuilder
    private var devReset: some View {
        #if DEBUG
        Button {
            Haptics.tap()
            app.resetAll()
        } label: {
            Text("Reset onboarding")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .onPhoto()
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        #endif
    }
}

// MARK: - Stat tile

/// One number, open on the page: the figure, a small caps label beneath with
/// its mark, and a line of caption — Open's "5 / DAY STREAK". The figure
/// fades in once it's known and crossfades when it changes (finishing a
/// practice while the tab is open moves the streak in place).
private struct StatTile: View {
    /// Nil until the ledger has loaded: a dash, never a zero that isn't true.
    let value: Int?
    let label: String
    let caption: String
    let systemImage: String
    var accent = false
    /// A live streak kept today: the flame breathes.
    var breathes = false
    let spoken: String
    let spokenValue: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let value {
                    Text(value.formatted())
                } else {
                    Text("–")
                }
            }
            .font(Theme.headline(44, weight: .light))
            .kerning(-1)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.opacity)

            HStack(spacing: 6) {
                // The one warm mark on the table: a streak that's alive.
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(accent ? Theme.ember : Theme.inkSoft)
                    .symbolEffect(.breathe, options: .repeat(.continuous),
                                  isActive: breathes && !reduceMotion)
                Text(label.uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(1.8)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 6)

            // Two lines, reserved on every tile: the streak captions need the
            // room to say plainly what happened, and reserving it keeps both
            // rows of the table even whichever caption is showing.
            Text(caption)
                .font(Theme.body(12))
                .foregroundStyle(accent ? Theme.inkOnPhoto : Theme.inkSoft)
                .lineLimit(2, reservesSpace: true)
                .lineSpacing(1)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Open on the page's photograph, not a tile.
        .onPhoto()
        .animation(Theme.Motion.reveal, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        // The caption is part of what the tile says (that today is done, what counts
        // as a class), so VoiceOver reads it too.
        .accessibilityValue(spokenValue.map { value in
            let note = caption.trimmingCharacters(in: .whitespaces)
            return note.isEmpty ? value : "\(value), \(note)"
        } ?? "Loading")
    }
}

// MARK: - History row

/// A square thumbnail and two lines, open on the page — one program or retreat
/// in the member's history. `opens` adds the chevron that says it goes
/// somewhere. The list draws the rules between rows.
private struct HistoryRow<Lines: View>: View {
    let imageUrl: String
    var opens = false
    @ViewBuilder var lines: Lines

    var body: some View {
        HStack(spacing: 16) {
            CatalogImage(imageUrl) { $0.resizable().scaledToFill() }
                .frame(width: 60, height: 60)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                lines
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onPhoto()

            if opens {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.vertical, 16)
        // The whole row answers a tap, not only its image and text.
        .contentShape(Rectangle())
    }
}

/// The rule between rows and above an open block.
private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

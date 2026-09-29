//
//  ProfileView.swift
//  Soulfull Gatherings
//
//  The You tab: who you are, what you've practised, and where you've been.
//
//  A member sees four numbers — current streak, best streak, classes taken,
//  minutes practised (`PracticeStats` defines each) — then the digital
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
    /// Read inside `body` so the observation registers.
    private let history = PracticeProgressStore.shared

    @State private var showAccount = false
    @State private var accountMode: AccountViewModel.Mode = .createAccount
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showPhotoOptions = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

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
                    VStack(spacing: 36) {
                        practiceSection
                        digitalSection
                        inPersonSection
                        communitySection
                    }
                    .padding(.top, 38)
                } else {
                    guestInvitation
                        .padding(.top, 34)
                }

                VStack(spacing: 16) {
                    accountActions
                    legalLinks
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)

                Color.clear.frame(height: 120)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable {
            guard isMember else { return }
            await vm.load(force: true, settings: settings)
        }
        .background {
            ZStack {
                PhotoBackdrop(imageName: "home-bg", blur: 4, darken: 0.7)
                AuroraBackground(speed: 0.7)
                    .opacity(0.35)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
        .task(id: identity) {
            guard isMember else { return }
            await vm.load(settings: settings)
        }
        .sheet(isPresented: $showAccount) {
            AccountView(mode: accountMode)
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
            Text("This permanently deletes your account, reservations, and saved data. This can't be undone.")
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
            deleteError = error.localizedDescription
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 18) {
            if isMember {
                avatarButton
            } else {
                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 88, height: 88)
                    .breathing(scale: 0.96...1.04, opacity: 0.82...0.95, period: 5.5)
            }
            VStack(spacing: 18) {
                Text((settings.userName.isEmpty ? "You" : settings.userName).uppercased())
                    .font(Theme.eyebrow(12))
                    .tracking(3)
                    .foregroundStyle(Theme.ink)
                Text("Welcome back.")
                    .font(Theme.headline(36))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)

                accountStatus
            }
            // This block is centred over the open sky of home-bg, the
            // brightest ground in the app — see View.onPhoto().
            .onPhoto()
            intentionsRow
        }
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
                           name: settings.userName,
                           seed: auth.userID?.uuidString ?? "preview",
                           size: 92)
                    .overlay {
                        if vm.isUploadingAvatar {
                            Circle().fill(.black.opacity(0.45))
                            ProgressView().tint(Theme.ink)
                        }
                    }
                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 28, height: 28)
                    .background(Theme.ink, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.soulPressableChip)
        .disabled(vm.isUploadingAvatar)
        .accessibilityLabel(settings.avatarUrl == nil ? "Add a profile photo" : "Change your profile photo")
        .accessibilityIdentifier("profile-avatar")
    }

    /// What they came here for, as quiet glass chips.
    @ViewBuilder
    private var intentionsRow: some View {
        let intentions = IntentionOption.all.filter { settings.intentions.contains($0.id) }
        if !intentions.isEmpty {
            HStack(spacing: 8) {
                ForEach(intentions.prefix(3)) { intention in
                    Text(intention.label)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .soulGlassCapsule()
                }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var accountStatus: some View {
        if isMember {
            Label(auth.email ?? "Signed in", systemImage: "checkmark.seal.fill")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkOnPhoto)
        } else {
            Text("Guest · not signed in")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: - Your practice

    @ViewBuilder
    private var practiceSection: some View {
        let stats = history.stats
        let known = history.ledgerStatus == .loaded

        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Your practice")

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
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
            .padding(.horizontal, 20)

            if case .unavailable(let offline) = history.ledgerStatus {
                retryLine(ProfileLoadFailure(offline: offline))
            }
        }
    }

    /// The one line on the streak tile that says what to do next. All of it
    /// reads off real history — nothing here is a nudge for its own sake.
    ///
    /// "Practiced today" and "kept today" are different: only a FINISHED
    /// practice counts toward the streak, but someone who opened a prompt and
    /// didn't write, or stopped a session short, has still practised. Telling
    /// them "practice today" contradicts what they just did; what's true is
    /// that a practice needs finishing — and the words name the practice and
    /// the streak outright ("finish one" left people asking one what).
    private func streakCaption(_ stats: PracticeStats) -> String {
        guard history.ledgerStatus == .loaded else { return " " }
        if stats.keptToday { return "You've completed a practice today" }
        if stats.currentStreak > 0 {
            return stats.practicedToday ? "Finish a practice today to keep your streak"
                                        : "Practice today to keep your streak"
        }
        return "Finish a practice today to start your streak"
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
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Digital retreats")

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
                    VStack(spacing: 10) {
                        ForEach(journeys) { journey in
                            journeyRow(journey)
                                .listReveal()
                        }
                    }
                    .padding(.horizontal, 20)
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
                .font(Theme.headline(18))
                .foregroundStyle(Theme.ink)
                .kerning(-0.2)
                .lineLimit(1)
            switch journey.standing {
            case .inProgress(let day, let total, let fraction):
                HStack(spacing: 10) {
                    Text("DAY \(day) OF \(total)")
                        .font(Theme.eyebrow(10))
                        .tracking(1.6)
                        .foregroundStyle(Theme.honey)
                    ProgressRule(fraction: fraction, width: 56)
                }
            case .completed(let date):
                Label(date.map { "Completed · \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? "Completed",
                      systemImage: "checkmark.seal.fill")
                    .font(Theme.body(12, weight: .medium))
                    // accentSoft, not accent: the deep olive sinks into dark
                    // glass at this size. Same "done" colour the mirror's
                    // Programs chip uses.
                    .foregroundStyle(Theme.accentSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - In-person retreats

    private var inPersonSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "In-person retreats")

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
                    VStack(spacing: 10) {
                        ForEach(vm.retreats) { retreat in
                            // Not a link: its detail screen is a booking page,
                            // and this retreat can no longer be booked.
                            HistoryRow(imageUrl: retreat.imageUrl, opens: false) {
                                Text(retreat.name)
                                    .font(Theme.headline(18))
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
                            .listReveal()
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Community

    /// The one switch the feed needs: whether this member appears in it. Off
    /// hides their finished practices from everyone, friends included; they
    /// stay findable and can still add and be added.
    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Community")

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share my practice")
                        .font(Theme.headline(17))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.2)
                    Text("Your finished practices appear in the Community feed as \u{201C}\(settings.userName.isEmpty ? "You" : Self.abbreviated(settings.userName)) practiced …\u{201D}, and your face among the followers of guides you follow. Journal prompts never appear.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: Binding(
                    get: { vm.shareActivity },
                    set: { on in Task { await vm.setShareActivity(on) } }
                ))
                .labelsHidden()
                .tint(Theme.honey)
                .disabled(vm.isSavingShare)
                .accessibilityLabel("Share my practice in the Community feed")
                .accessibilityIdentifier("share-activity")
            }
            .padding(16)
            .soulGlassCard()
            .padding(.horizontal, 20)
        }
    }

    /// "Hugo De Santiago" → "Hugo D.", the way the server abbreviates it.
    private static func abbreviated(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = parts.first else { return "You" }
        guard parts.count > 1, let initial = parts[1].first else { return first }
        return "\(first) \(initial)."
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
                .font(Theme.headline(18))
                .foregroundStyle(Theme.ink)
                .kerning(-0.2)
            Text(detail)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                perform()
            } label: {
                HStack(spacing: 6) {
                    Text(action)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.honey)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.soulPressableQuiet)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .soulGlassCard()
        .padding(.horizontal, 20)
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
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                Task { await vm.load(force: true) }
            } label: {
                Text("Try again")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.honey)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.soulPressableQuiet)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .soulGlassCard()
        .padding(.horizontal, 20)
    }

    // MARK: - Guest

    /// Every practice is behind the account gate, so a guest has no history —
    /// and four zeros would read as a verdict rather than an invitation.
    private var guestInvitation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR PRACTICE")
                .font(Theme.eyebrow(10))
                .tracking(3)
                .foregroundStyle(Theme.honey)
            Text("Keep it with you")
                .font(Theme.headline(22))
                .foregroundStyle(Theme.ink)
                .kerning(-0.2)
            Text("With an account, your streaks, classes and minutes gather here — alongside every retreat you join, digital or in person.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .soulGlassCard()
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guest-invitation")
    }

    // MARK: - Actions (sign in/up vs sign out) + dev tools

    @ViewBuilder
    private var accountActions: some View {
        VStack(spacing: 12) {
            if auth.hasAccount {
                SGPrimaryButton(title: "Sign out") {
                    Task { await auth.signOut() }
                }
                Button {
                    Haptics.tap()
                    showDeleteConfirm = true
                } label: {
                    Text(isDeleting ? "Deleting…" : "Delete account")
                        .font(Theme.body(13))
                        .foregroundStyle(Color(red: 0.85, green: 0.36, blue: 0.33))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
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
            .foregroundStyle(Theme.muted)
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
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        #endif
    }
}

// MARK: - Stat tile

/// One number on a glass tile. The figure rolls up from zero the first time it
/// appears, and rolls again whenever it changes — finishing a practice while
/// the tab is open moves the streak in place.
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
    @State private var shown = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent ? Theme.honey : Theme.inkSoft)
                .symbolEffect(.breathe, options: .repeat(.continuous),
                              isActive: breathes && !reduceMotion)
                .frame(height: 18)

            Spacer(minLength: 12)

            Group {
                if value != nil {
                    Text(shown.formatted())
                        .contentTransition(.numericText(value: Double(shown)))
                } else {
                    Text("–")
                }
            }
            .font(Theme.headline(40, weight: .light))
            .kerning(-1)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text(label.uppercased())
                .font(Theme.eyebrow(10))
                .tracking(1.8)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 4)

            // Two lines, reserved on every tile: the streak captions need the
            // room to say plainly what happened, and reserving it keeps all
            // four tiles the same height whichever caption is showing.
            Text(caption)
                .font(Theme.body(12))
                .foregroundStyle(accent ? Theme.honey : Theme.muted)
                .lineLimit(2, reservesSpace: true)
                .lineSpacing(1)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minHeight: 118)
        .padding(16)
        .soulGlassCard(tint: accent ? Theme.honey.opacity(0.08) : nil,
                       stroke: accent ? Theme.honey.opacity(0.35) : Theme.glassBorder)
        .onAppear { roll(to: value) }
        .onChange(of: value) { _, new in roll(to: new) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        // The caption is part of what the tile says (that today is done, what counts
        // as a class), so VoiceOver reads it too.
        .accessibilityValue(spokenValue.map { value in
            let note = caption.trimmingCharacters(in: .whitespaces)
            return note.isEmpty ? value : "\(value), \(note)"
        } ?? "Loading")
    }

    private func roll(to target: Int?) {
        guard let target, target != shown else { return }
        if reduceMotion {
            shown = target
        } else {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.9).delay(0.15)) {
                shown = target
            }
        }
    }
}

// MARK: - History row

/// A thumbnail and two lines on glass — one program or retreat in the
/// member's history. `opens` adds the chevron that says it goes somewhere.
private struct HistoryRow<Lines: View>: View {
    let imageUrl: String
    var opens = false
    @ViewBuilder var lines: Lines

    var body: some View {
        HStack(spacing: 14) {
            CatalogImage(imageUrl) { $0.resizable().scaledToFill() }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                lines
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if opens {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .padding(.trailing, 4)
        .soulGlassCard()
    }
}

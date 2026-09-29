//
//  InstructorProfileView.swift
//  Soulfull Gatherings
//
//  A guide's page. Their portrait breathing over their own photograph, blurred
//  to a colour field; the two numbers — followers, following — with the faces
//  of a few people who follow them; Follow; the bio; and everything they have
//  published, which opens exactly where it would from anywhere else.
//
//  Open to a guest end to end. Following and playing are the two things on
//  the page that need an account; both go through `requireAccount`.
//

import SwiftUI

struct InstructorProfileView: View {
    let backLabel: String
    /// A digital retreat in the library was tapped. The host decides whether
    /// that is a push (Digital Retreats tab) or a hand-off (anywhere else).
    var onOpenProgram: (Program) -> Void
    /// Injected so this view stays unaware of auth; the default runs straight
    /// through, which keeps previews working.
    var requireAccount: (@escaping () -> Void) -> Void

    @State private var vm: InstructorProfileViewModel
    @State private var nowPlaying: PracticeSession?
    @State private var bioExpanded = false
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    private let history = PracticeProgressStore.shared

    init(instructorID: String,
         backLabel: String = "Practices",
         onOpenProgram: @escaping (Program) -> Void = { _ in },
         requireAccount: @escaping (@escaping () -> Void) -> Void = { $0() }) {
        self.backLabel = backLabel
        self.onOpenProgram = onOpenProgram
        self.requireAccount = requireAccount
        _vm = State(initialValue: InstructorProfileViewModel(
            instructorID: instructorID,
            instructor: InstructorDirectory.shared.instructor(id: instructorID)))
    }

    private var isMember: Bool { auth.hasAccount || InstructorDirectory.isPreviewMember }

    /// Runs `action` now for a member, after the account sheet for a guest.
    private func gated(_ action: @escaping () -> Void) {
        if isMember { action() } else { requireAccount(action) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PracticeBackBar(label: backLabel)

                if let instructor = vm.instructor {
                    profile(instructor)
                } else if vm.notFound {
                    unavailable
                } else if let failure = vm.profileFailure {
                    failureState(failure) { Task { await vm.load() } }
                        .padding(.top, 120)
                } else {
                    ProgressView()
                        .tint(Theme.ink)
                        .padding(.top, 160)
                }

                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background {
            // Their own photograph, blurred until it is only its colour — so
            // each guide's page has a temperature of its own.
            PhotoBackdrop(imageName: vm.instructor?.photoUrl ?? "home-bg", blur: 48, darken: 0.86)
        }
        // Whoever is asking changes "followed by me" and "is me": re-read on
        // sign-in, which is also when a gated Follow is replayed.
        .task(id: "\(auth.userID?.uuidString ?? "guest")-\(auth.hasAccount)") { await vm.load() }
        .task { await history.refresh() }
        .onChange(of: nowPlaying) { _, new in
            guard new == nil else { return }
            Task { await history.refresh(force: true) }
        }
        .sheet(item: $nowPlaying) { session in
            PracticePlayerView(media: session.media)
        }
    }

    // MARK: - The page

    private func profile(_ instructor: Instructor) -> some View {
        VStack(spacing: 0) {
            header(instructor)
                .padding(.top, 26)
            stats
                .padding(.top, 26)
            followedBy
                .padding(.top, 14)
            followControl(instructor)
                .padding(.top, 20)
            if let bio = instructor.bio {
                about(bio)
                    .padding(.top, 36)
            }
            library(instructor)
                .padding(.top, 36)
        }
    }

    // MARK: Header

    private func header(_ instructor: Instructor) -> some View {
        VStack(spacing: 16) {
            AvatarView(avatarUrl: instructor.photoUrl, name: instructor.name,
                       seed: instructor.id, size: 112)
                .padding(6)
                .overlay(Circle().strokeBorder(Theme.honey.opacity(0.35), lineWidth: 1))
                .background {
                    // A slow honey halo: the portrait breathes, the page
                    // stays still. In a background so it never takes space.
                    Circle()
                        .fill(RadialGradient(colors: [Theme.honey.opacity(0.34), .clear],
                                             center: .center, startRadius: 52, endRadius: 118))
                        .frame(width: 236, height: 236)
                        .breathing(scale: 0.9...1.04, opacity: 0.65...1, period: 6)
                        .allowsHitTesting(false)
                }

            VStack(spacing: 8) {
                if let title = instructor.title {
                    Text(title.uppercased())
                        .font(Theme.eyebrow(11))
                        .tracking(2.6)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                }
                Text(instructor.name)
                    .font(Theme.headline(38))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.4)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("instructor-name")
            }
            .onPhoto()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Numbers

    private var stats: some View {
        let social = vm.social
        return HStack(spacing: 0) {
            stat(value: social.map { Presence.compact($0.followers) },
                 label: social?.followers == 1 ? "Follower" : "Followers",
                 spoken: social.map { "\($0.followers.formatted()) \($0.followers == 1 ? "follower" : "followers")" },
                 id: "instructor-followers")
            Rectangle()
                .fill(Theme.glassBorderHigh)
                .frame(width: 1, height: 36)
            stat(value: social.map { Presence.compact($0.following) },
                 label: "Following",
                 spoken: social.map { "Following \($0.following.formatted())" },
                 id: "instructor-following")
        }
        .frame(maxWidth: 280)
        .animation(.snappy(duration: 0.35), value: social)
    }

    private func stat(value: String?, label: String, spoken: String?, id: String) -> some View {
        VStack(spacing: 5) {
            Text(value ?? "–")
                .font(Theme.headline(28))
                .foregroundStyle(value == nil ? Theme.muted : Theme.ink)
                .kerning(-0.3)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(Theme.eyebrow(10))
                .tracking(2)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .onPhoto()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? "\(label), not loaded")
        // The label is the exact number, which is what should be spoken; the
        // value is the figure as drawn ("75.7k"), for the UI tests.
        .accessibilityValue(value ?? "")
        .accessibilityIdentifier(id)
    }

    /// Faces, "you" first when the viewer follows too — the server leaves the
    /// viewer out of its three, and the line names them, so the stack should
    /// show them.
    @ViewBuilder
    private var followedBy: some View {
        if let social = vm.social, let line = social.followedByLine() {
            HStack(spacing: 10) {
                faceStack(social)
                Text(line)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .onPhoto()
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line)
            .accessibilityIdentifier("instructor-followed-by")
            .transition(.opacity)
        }
    }

    private func faceStack(_ social: InstructorSocial) -> some View {
        let me = CommunityMember(id: auth.userID ?? InstructorDirectory.previewSelf,
                                 displayName: settings.userName.isEmpty ? "You" : settings.userName,
                                 avatarUrl: settings.avatarUrl)
        let faces = Array(((social.followedByMe ? [me] : []) + social.faces).prefix(3))
        return HStack(spacing: -8) {
            ForEach(Array(faces.enumerated()), id: \.element.id) { index, member in
                AvatarView(avatarUrl: member.avatarUrl, name: member.displayName,
                           seed: member.id.uuidString, size: 24)
                    .zIndex(Double(3 - index))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: social.followedByMe)
    }

    // MARK: Follow

    @ViewBuilder
    private func followControl(_ instructor: Instructor) -> some View {
        VStack(spacing: 10) {
            if vm.social?.isMe == true {
                Label("This is your profile", systemImage: "person.crop.circle")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .soulGlassCapsule()
            } else {
                FollowButton(following: vm.isFollowing, busy: vm.isFollowBusy,
                             name: instructor.name) {
                    let follow = !vm.isFollowing
                    follow ? Haptics.bump() : Haptics.tap()
                    gated { Task { await vm.setFollowing(follow) } }
                }
            }
            if let error = vm.followError {
                Text(error)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.honey)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.25), value: vm.followError)
    }

    // MARK: About

    private func about(_ bio: String) -> some View {
        // A long bio folds to five lines. Counted in characters rather than
        // measured: a bio is a paragraph or two, and "More" under a text that
        // wasn't cut would be a button that does nothing.
        let foldable = bio.count > 260
        return VStack(alignment: .leading, spacing: 10) {
            Text("ABOUT")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
                .onPhoto()
            Text(bio)
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(5)
                .lineLimit(foldable && !bioExpanded ? 5 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .onPhoto()
                .accessibilityIdentifier("instructor-bio")
            if foldable {
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.3)) { bioExpanded.toggle() }
                } label: {
                    Text(bioExpanded ? "Less" : "More")
                        .font(Theme.body(13, weight: .medium))
                        .underline()
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Library

    private func library(_ instructor: Instructor) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LIBRARY")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                Text("Practices with \(instructor.firstName)")
                    .font(Theme.headline(26))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
            }
            .onPhoto()

            if let library = vm.library {
                if library.isEmpty {
                    emptyLibrary(instructor)
                } else {
                    if !library.programs.isEmpty {
                        librarySection("Digital retreats") {
                            ForEach(library.programs) { program in
                                programCard(program)
                                    .listReveal()
                            }
                        }
                    }
                    if !library.sessions.isEmpty {
                        librarySection("Sessions") {
                            ForEach(library.sessions) { session in
                                PressableCard(action: { gated { nowPlaying = session } }) {
                                    sessionRow(session)
                                }
                                .accessibilityIdentifier("instructor-library-session")
                                .listReveal()
                            }
                        }
                    }
                }
            } else if let failure = vm.libraryFailure {
                failureState(failure) { Task { await vm.loadLibrary() } }
                    .padding(.top, 10)
            } else {
                ProgressView()
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func librarySection<Content: View>(_ title: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(Theme.eyebrow(10))
                .tracking(2)
                .foregroundStyle(Theme.inkSoft)
                .onPhoto()
            VStack(spacing: 10) { content() }
        }
    }

    private func programCard(_ program: Program) -> some View {
        PressableCard(action: { onOpenProgram(program) }) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(height: 176)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        CatalogImage(program.imageUrl) { $0.resizable().scaledToFill() }
                    }
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text(program.metaLine.uppercased())
                        .font(Theme.eyebrow(10))
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text(program.title)
                        .font(Theme.headline(24))
                        .foregroundStyle(.white)
                        .kerning(-0.3)
                    if let blurb = program.blurb {
                        Text(blurb)
                            .font(Theme.body(12))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                .padding(16)
            }
            .frame(height: 176)
            .soulGlassCard(radius: Theme.cardRadius)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(program.title), digital retreat, \(program.metaLine)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("instructor-library-program")
    }

    private func sessionRow(_ session: PracticeSession) -> some View {
        let progress = history.progress(kind: .session, contentID: session.id)
        return HStack(spacing: 14) {
            ZStack {
                CatalogImage(session.imageUrl) { $0.resizable().scaledToFill() }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                Image(systemName: session.mediaKind == .video ? "play.fill" : "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Theme.glassBorder, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(Theme.headline(16))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.category.title)
                    Text("·")
                    if let p = progress, p.isResumable, let remaining = p.remainingLabel {
                        Text(remaining).foregroundStyle(Theme.honey)
                    } else {
                        Text(session.durationLabel)
                    }
                }
                .font(Theme.eyebrow(10))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSoft)
                if let p = progress, p.isResumable {
                    ProgressRule(fraction: p.fraction)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
            if progress?.completed == true {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.honey.opacity(0.85))
                    .accessibilityLabel("Completed")
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .soulGlassCard(radius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func emptyLibrary(_ instructor: Instructor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.honey)
            Text("Nothing published yet")
                .font(Theme.headline(18))
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
            Text("\(instructor.firstName)'s first practices are on their way.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .soulGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("instructor-library-empty")
    }

    // MARK: - States

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("This profile isn't available")
                .font(Theme.headline(22))
                .foregroundStyle(Theme.ink)
            Text("It may have been taken down. Anything this guide published is still in the library.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPhoto()
        .frame(maxWidth: .infinity)
        .padding(.top, 140)
    }

    private func failureState(_ failure: InstructorLoadFailure,
                              retry: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: failure == .offline ? "wifi.slash" : "exclamationmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.muted)
            Text(failure.title)
                .font(Theme.headline(20))
                .foregroundStyle(Theme.ink)
            Text(failure.detail)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                retry()
            } label: {
                Text("Try again")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .soulGlassCapsule()
            }
            .buttonStyle(.soulPressableQuiet)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Follow button

/// Honey and filled to ask; quiet glass with a check once it's done — the
/// same two weights the Friends screen gives its primary and secondary verbs.
private struct FollowButton: View {
    let following: Bool
    let busy: Bool
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: following ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(following ? "Following" : "Follow")
                    .font(Theme.body(15, weight: .medium))
                    .tracking(0.3)
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(following ? Theme.ink : Color.black)
            .frame(width: 196, height: 50)
            .background {
                if !following {
                    Capsule().fill(Theme.honey)
                        .transition(.opacity)
                }
            }
            .modifier(GlassWhenFollowing(enabled: following))
            .contentShape(Capsule())
            .opacity(busy ? 0.6 : 1)
        }
        .buttonStyle(.soulPressableQuiet)
        .disabled(busy)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: following)
        .accessibilityLabel(following ? "Following" : "Follow")
        .accessibilityHint(following ? "Unfollows \(name)" : "Follows \(name)")
        .accessibilityIdentifier("instructor-follow")
    }
}

private struct GlassWhenFollowing: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.soulGlassCapsule(interactive: true, stroke: Theme.glassBorderHigh)
        } else {
            content
        }
    }
}

#Preview {
    let state = AppState()
    return NavigationStack {
        InstructorProfileView(instructorID: "alma-guerra")
            .toolbar(.hidden, for: .navigationBar)
    }
    .environment(state.auth)
    .environment(state.settings)
    .preferredColorScheme(.dark)
}

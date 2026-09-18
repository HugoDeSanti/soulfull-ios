//
//  SoulfullGatheringsApp.swift
//  Soulfull Gatherings
//
//  App entry. Owns the single AppState that drives stage routing
//  (loading → welcome → onboarding → main) and anonymous auth via
//  AuthManager. The `.task` initiates auth and transitions out of
//  the loading stage as quickly as the network allows.
//

import SwiftUI

@main
struct SoulfullGatheringsApp: App {
    @State private var appState = AppState()

    init() {
        #if DEBUG
        // UI-test hooks: deterministic state for the automated tour.
        if CommandLine.arguments.contains("-uitest-reset") {
            appState.settings.reset()
        }
        if CommandLine.arguments.contains("-uitest-onboarded") {
            appState.settings.userName = "Mara"
            appState.settings.hasOnboarded = true
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .environment(appState)
                .environment(appState.settings)
                .environment(appState.auth)
                .preferredColorScheme(.dark)
                .tint(Theme.ink)
                .task { await appState.initializeAuth() }
                .onOpenURL { url in
                    // Email-confirmation / magic-link callback (soulfull://auth-callback).
                    Task { await appState.auth.handleDeepLink(url) }
                }
        }
    }

    /// The app root, or a DEBUG screen override for visual passes without
    /// driving the full app to it (`-preview-retreat` / `-preview-experience`
    /// launch args). Release builds always show `RootView`.
    ///
    /// `-preview-checkout` and `-preview-chat` are gone with the screens they
    /// rendered: the Stripe checkout (dependency dropped) and the mocked
    /// assistant chat (the app has no AI).
    @ViewBuilder private var rootContent: some View {
        #if DEBUG
        if CommandLine.arguments.contains("-preview-retreat") {
            NavigationStack {
                PreviewRetreat { RetreatDetailView(retreat: $0).toolbar(.hidden, for: .navigationBar) }
            }
        } else if CommandLine.arguments.contains("-preview-retreats") {
            PreviewRetreatsStack()
        } else if CommandLine.arguments.contains("-preview-experience") {
            NavigationStack {
                PreviewRetreat { RetreatExperienceHubView(retreat: $0).toolbar(.hidden, for: .navigationBar) }
            }
        } else if CommandLine.arguments.contains("-preview-todos") {
            NavigationStack {
                PreviewRetreat { RetreatTodosView(retreat: $0).toolbar(.hidden, for: .navigationBar) }
            }
        } else if CommandLine.arguments.contains("-preview-packing") {
            NavigationStack {
                PreviewRetreat { PackingListView(retreat: $0).toolbar(.hidden, for: .navigationBar) }
            }
        } else if CommandLine.arguments.contains("-preview-guides") {
            NavigationStack {
                PreviewRetreat { RetreatGuidesView(retreat: $0).toolbar(.hidden, for: .navigationBar) }
            }
        } else if CommandLine.arguments.contains("-preview-enquiry") {
            PreviewRetreat {
                RetreatEnquiryView(retreat: $0, initialName: "Hugo",
                                   accountEmail: "hugo@soulfullgatherings.com")
            }
        } else if CommandLine.arguments.contains("-preview-confirm-email") {
            AccountView(previewConfirmationFor: "hugo@soulfullgatherings.com")
        } else if CommandLine.arguments.contains("-preview-program") {
            NavigationStack {
                PreviewProgram { ProgramDetailView(program: $0).toolbar(.hidden, for: .navigationBar) }
            }
        } else if CommandLine.arguments.contains("-preview-program-day") {
            NavigationStack {
                PreviewProgram { program in
                    // Day 1 — the only one a not-yet-enrolled preview can show.
                    if let day = program.authoredDays.first {
                        ProgramDayView(program: program, day: day)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
            }
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}

#if DEBUG
/// Supplies a **real** program to the `-preview-program*` screens, falling back
/// to the fixture.
///
/// The fallback is what `PreviewRetreat` learned the hard way and is why this
/// exists at all: the day-by-day content lives in `programs.curriculum`, so a
/// preview pinned to `Program.mock` would stop reflecting the real thing the
/// moment someone edits the dashboard. Prefers a program that actually has
/// authored days.
private struct PreviewProgram<Content: View>: View {
    @ViewBuilder var content: (Program) -> Content
    @State private var program: Program?

    var body: some View {
        Group {
            if let program {
                content(program)
            } else {
                Theme.bg.ignoresSafeArea().overlay(ProgressView().tint(Theme.ink))
            }
        }
        .task {
            let all = (try? await SupabaseService.shared.fetchPrograms()) ?? []
            program = all.first(where: \.isStartable) ?? all.first ?? Program.mock.first
            if let program { await ProgramStore.shared.resolveContent(for: program) }
        }
    }
}

/// The retreats stack (`-preview-retreats`) against the live catalog, with the
/// detail push wired so a tap on the focused name goes somewhere — the same
/// hand-off `HomeRoot` makes, minus the rest of Home.
private struct PreviewRetreatsStack: View {
    @State private var path: [Retreat] = []

    var body: some View {
        NavigationStack(path: $path) {
            RetreatsStackView(onSelect: { path.append($0) })
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Retreat.self) {
                    RetreatDetailView(retreat: $0).toolbar(.hidden, for: .navigationBar)
                }
        }
    }
}

/// Supplies a **real** retreat to the `-preview-*` screens.
///
/// They used to render `Retreat.mock[0]`, which stopped being useful the moment
/// the brochure and the trip photography moved into `retreats.experience`: the
/// fixture carries neither, so every post-purchase preview came up empty and
/// the arg quietly stopped doing its job. Prefers a retreat that actually has a
/// document, falling back to the first one.
private struct PreviewRetreat<Content: View>: View {
    @ViewBuilder var content: (Retreat) -> Content
    @State private var retreat: Retreat?

    var body: some View {
        Group {
            if let retreat {
                content(retreat)
            } else {
                Theme.bg.ignoresSafeArea().overlay(ProgressView().tint(Theme.ink))
            }
        }
        .task {
            let all = (try? await SupabaseService.shared.fetchRetreats()) ?? []
            retreat = all.first { $0.experience != nil } ?? all.first
        }
    }
}
#endif

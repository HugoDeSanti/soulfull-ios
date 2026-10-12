//
//  TabRouter.swift
//  Soulfull Gatherings
//
//  Which tab is showing, and what one tab has asked another to open — the
//  shell's state, held in one observable object rather than in `MainTabView`.
//
//  Each tab lives in a hosting controller of its own (`TabPager`), and its
//  page is built ONCE, when the tab is first selected. The state used to be
//  `@State` on `MainTabView`, whose body therefore re-ran on every tab
//  switch, push, hand-off and scene change — rebuilding all six pages with
//  fresh closures and handing each to its controller, so every open tab
//  re-ran its body (Home walking the whole practice ledger three times) for a
//  push on another. Now the pages hold this object, read what they need from
//  it, and SwiftUI re-renders exactly the readers of what changed.
//
//  So a page never sees a value it was built with change. Anything a tab
//  needs from above that can change goes through here (as `scenePhase` does),
//  never as a value passed when the page is made.
//

import SwiftUI

@Observable @MainActor
final class TabRouter {

    var tab: MainTab

    /// The tabs whose stack has something pushed — on the showing one, the
    /// nav bows out so detail screens own the full canvas. Per tab because
    /// every tab keeps its stack: a hand-off can leave one tab with a screen
    /// pushed and push onto another in the same update, and a single shared
    /// flag ended up with whichever wrote last.
    var pushed: Set<MainTab> = []

    /// Set when another tab asks to open a Practice section (Home's ritual
    /// card). `PracticeRoot` consumes and clears it, which is what makes the
    /// jump land on the right screen rather than just the Practice landing.
    var pendingPractice: PracticeMenuItem?
    /// Set when Home's "Day N is open" card (or the You tab, or a program
    /// reminder) asks to open a program. Consumed by `ProgramsRoot`.
    var pendingProgram: String?
    /// Set when a card on Home's gatherings shelf asks to open a retreat.
    /// Consumed by `GatheringsRoot` once its catalog is in.
    var pendingRetreat: Retreat?
    /// A like push was tapped. Consumed by `CommunityRoot`, which pushes the
    /// Notifications screen.
    var pendingNotifications = false

    /// The scene's phase, for the tabs: a hosting controller of our own
    /// doesn't inherit it from the scene the way a SwiftUI child would, and
    /// written practices time themselves by it.
    var scenePhase: ScenePhase = .active

    /// The account sheet, one for the whole shell, so a gated tap works from
    /// any tab and survives the tab switch Home's ritual card performs.
    var showAccount = false
    /// Holds the interrupted action while the account sheet is up, then
    /// replays it (`AccountGate`).
    @ObservationIgnored let gate = AccountGate()

    init(tab: MainTab = .home) {
        self.tab = tab
    }

    // MARK: - Hand-offs

    func openRetreat(_ retreat: Retreat) {
        pendingRetreat = retreat
        tab = .gatherings
    }

    func openPractice(_ item: PracticeMenuItem) {
        pendingPractice = item
        tab = .practice
    }

    /// Nil switches to the tab without opening anything.
    func openProgram(_ programID: String?) {
        pendingProgram = programID
        tab = .programs
    }

    func openNotifications() {
        pendingNotifications = true
        tab = .community
    }

    // MARK: - The account gate

    /// Runs `action` at once for someone with an account; otherwise holds it
    /// and raises the account sheet, whose dismissal replays it
    /// (`resumeAfterAccountSheet`).
    func requireAccount(signedIn: Bool, _ action: @escaping () -> Void) {
        if gate.require(signedIn: signedIn, action) { showAccount = true }
    }

    func resumeAfterAccountSheet(signedIn: Bool) {
        gate.resume(signedIn: signedIn)
    }

    // MARK: - The nav bar

    /// The showing tab has a screen pushed.
    var isNavHidden: Bool { pushed.contains(tab) }

    /// One tab's entry in `pushed`, for its stack root to report through.
    func navHidden(_ item: MainTab) -> Binding<Bool> {
        Binding(get: { self.pushed.contains(item) },
                set: { hidden in
                    if hidden { self.pushed.insert(item) } else { self.pushed.remove(item) }
                })
    }
}

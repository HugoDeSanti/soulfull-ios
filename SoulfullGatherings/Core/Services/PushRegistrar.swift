//
//  PushRegistrar.swift
//  Soulfull Gatherings
//
//  Push notifications for likes. The device's APNs token is registered under
//  the signed-in member (`device_tokens`), the like trigger posts to the
//  `send-like-push` Edge Function, and APNs does the rest.
//
//  Permission is asked ONCE, from a card on the Community tab — the place a
//  like is worth something — never at launch. A member who already said yes
//  to program nudges is registered silently, since the permission is shared.
//  Guests are never registered: a push about your practice needs a "you".
//

import SwiftUI
import UserNotifications

@Observable @MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()

    /// What the system currently allows. `.notDetermined` is the only state
    /// the prompt card shows for.
    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// A like push was tapped: the shell switches to Community → Notifications
    /// and clears this.
    var openNotificationsRequested = false
    /// The card was declined with "Not now". Per install, not per member — a
    /// refusal is a refusal.
    var promptDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: "sg.pushPromptDismissed") }
        set { UserDefaults.standard.set(newValue, forKey: "sg.pushPromptDismissed") }
    }

    /// The token APNs last handed us, hex. Kept so sign-out can forget it.
    private var token: String? {
        get { UserDefaults.standard.string(forKey: "sg.pushToken") }
        set { UserDefaults.standard.set(newValue, forKey: "sg.pushToken") }
    }
    private var registeredFor: UUID?

    /// Debug builds register with APNs sandbox; TestFlight and the App Store
    /// use production. Sent with the token so the server picks the right host.
    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    // MARK: - Permission

    func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Registers with APNs if the member has already allowed notifications.
    /// Cheap, and safe to call on every identity change.
    func syncIfAuthorized(isMember: Bool) async {
        await refreshStatus()
        guard isMember, status == .authorized || status == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
        // A token we already hold can be filed under this member right away.
        await upload()
    }

    /// The card's "Turn on": asks, then registers if allowed.
    @discardableResult
    func requestAndRegister() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            guard granted else { return false }
            UIApplication.shared.registerForRemoteNotifications()
            return true
        } catch {
            Log.data.info("Push permission request failed: \(error.localizedDescription)")
            await refreshStatus()
            return false
        }
    }

    // MARK: - Token

    /// APNs answered. Called from the app delegate.
    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        if hex != token { registeredFor = nil }
        token = hex
        Task { await upload() }
    }

    func didFailToRegister(_ error: Error) {
        Log.data.info("APNs registration failed: \(error.localizedDescription)")
    }

    /// Files the token under the signed-in member. No-op for a guest, or
    /// when this token is already filed under this member.
    private func upload() async {
        let auth = SupabaseService.shared.client.auth
        guard let token, let user = auth.currentUser, !(user.isAnonymous) else { return }
        guard registeredFor != user.id else { return }
        do {
            try await SupabaseService.shared.registerDeviceToken(token, userID: user.id,
                                                                 environment: Self.environment)
            registeredFor = user.id
        } catch {
            Log.data.info("Device token upload failed: \(error.localizedDescription)")
        }
    }

    /// Sign-out: this phone stops being the member's. Best-effort — the
    /// server-side claim trigger also hands the token to whoever signs in
    /// next, so a missed delete costs nothing to anyone but the signed-out
    /// member's own quiet.
    func forgetDevice() async {
        registeredFor = nil
        guard let token else { return }
        do {
            try await SupabaseService.shared.removeDeviceToken(token)
        } catch {
            Log.data.info("Device token removal failed: \(error.localizedDescription)")
        }
    }

    /// The Notifications screen was opened: nothing is unseen any more.
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    }
}

/// Receives the APNs token and the tap on a notification. Everything else the
/// app does with notifications (program nudges) is local and needs no delegate,
/// but a delegate is the only way to get the token and to show a banner while
/// the app is in the foreground.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushRegistrar.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushRegistrar.shared.didFailToRegister(error) }
    }

    // The two delegate callbacks are `nonisolated` with completion handlers:
    // UIApplicationDelegate makes this class main-actor, and the async forms
    // would then need to move non-Sendable UNNotification values onto it.

    /// Foreground: still show it. A like arriving while you're on the Practice
    /// tab is worth a banner; the program nudge always was.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Tapped: a like opens Community → Notifications.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let kind = response.notification.request.content.userInfo["kind"] as? String
        if kind == "like" {
            Task { @MainActor in PushRegistrar.shared.openNotificationsRequested = true }
        }
        completionHandler()
    }
}

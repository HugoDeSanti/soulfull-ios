//
//  LegalLinks.swift
//  Soulfull Gatherings
//
//  Every outward-facing legal / support destination in one place.
//
//  All three pages are live on the Squarespace site and were verified to
//  return 200 on 2026-09-07. The sources they were published from live in
//  `website/legal/` at the repo root — edit those and re-publish, so the repo
//  copy and the live page never drift apart.
//
//  Note the `www.` host: the apex redirects, and App Review follows redirects
//  fine, but linking the final URL saves a hop from inside the app.
//

import Foundation

enum LegalLinks {

    /// Hosted privacy policy. Must stay identical to the Privacy Policy URL
    /// entered in App Store Connect — a mismatch is a review flag.
    static let privacyPolicy = URL(string: "https://www.soulfullgatherings.com/soulfull-privacy-policy")!

    /// App + website terms: accounts, licence, the wellness disclaimer, the
    /// clauses Apple requires, and dispute resolution.
    static let terms = URL(string: "https://www.soulfullgatherings.com/soulfull-terms-of-service")!

    /// Retreat booking, deposits, cancellation windows and refunds. This is
    /// what the checkout fineprint means by "the cancellation policy" — the
    /// app-level `terms` above do **not** cover it, so link this one wherever
    /// money or a reservation is involved.
    static let retreatPolicy = URL(string: "https://www.soulfullgatherings.com/soulfull-retreat-policy")!

    /// The monitored inbox. Same address the three published pages give for
    /// privacy requests, support and bookings.
    ///
    /// Also the destination of every "Request a place" enquiry while
    /// reservations are off (`AppFeatures.paymentsEnabled == false`).
    static let supportEmail = "info@soulfullgatherings.com"

    /// `mailto:` for general support, subject pre-filled.
    static var supportMail: URL {
        mail(subject: "Soulfull — support")
    }

    /// `mailto:` for a place on a specific retreat, used by the detail screen's
    /// CTA while reservations are off.
    static func enquiry(about retreat: String) -> URL {
        mail(subject: "Soulfull — a place on \(retreat)")
    }

    private static func mail(subject: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        // `URLComponents` percent-encodes spaces as `%20`, which Mail accepts.
        return components.url ?? URL(string: "mailto:\(supportEmail)")!
    }
}

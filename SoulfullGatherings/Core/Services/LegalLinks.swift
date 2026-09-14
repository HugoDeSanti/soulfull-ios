//
//  LegalLinks.swift
//  Soulfull Gatherings
//
//  Every outward-facing legal / support destination in one place.
//
//  All three pages are live on the Squarespace site and were verified to
//  return 200 on 2026-09-07. The published page is the only copy — the repo
//  sources under `website/legal/` were removed on 2026-09-07; recover them
//  from git history (`git show d20e3f6:website/legal/`) if one needs editing.
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
    /// Also where every retreat application lands while reservations are off
    /// (`AppFeatures.paymentsEnabled == false`) — see `RetreatEnquiry.recipient`.
    static let supportEmail = "info@soulfullgatherings.com"

    /// `mailto:` for general support, subject pre-filled.
    static var supportMail: URL {
        mail(subject: "Soulfull — support")
    }

    // `enquiry(about:)` lived here until the retreat CTA stopped opening a
    // blank email: a `mailto:` carrying only a subject asked the guest to
    // work out for themselves what the retreat team needed to know. The CTA
    // now opens `RetreatEnquiryView`, which asks the website's own
    // application questions and composes the mail from the answers. Recover
    // the helper from git history if a bare enquiry link is ever wanted again.

    private static func mail(subject: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        // `URLComponents` percent-encodes spaces as `%20`, which Mail accepts.
        return components.url ?? URL(string: "mailto:\(supportEmail)")!
    }
}

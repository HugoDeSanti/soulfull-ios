//
//  LegalLinks.swift
//  Soulfull Gatherings
//
//  Every outward-facing legal / support destination in one place.
//
//  ⚠️ THESE ARE PLACEHOLDERS AND MUST BE REPLACED BEFORE SUBMITTING.
//
//  App Store Connect requires a privacy policy URL that actually resolves, and
//  a support URL — a reviewer will open both. An app that creates accounts and
//  (from 1.1) takes payment also needs its terms reachable from inside the app,
//  not just named in checkout fineprint.
//
//  Search for TODO below; there are three values to set.
//

import Foundation

enum LegalLinks {

    /// TODO: replace with the real hosted privacy policy before submitting.
    /// Must match the Privacy Policy URL entered in App Store Connect.
    static let privacyPolicy = URL(string: "https://soulfullgatherings.com/privacy")!

    /// TODO: replace with the real hosted terms + cancellation policy.
    /// This is what the checkout fineprint refers to ("the enrollment terms
    /// and cancellation policy"), so it must cover both.
    static let terms = URL(string: "https://soulfullgatherings.com/terms")!

    /// TODO: replace with the real support address.
    /// Also used for retreat enquiries while reservations are off
    /// (`AppFeatures.paymentsEnabled == false`).
    static let supportEmail = "hello@soulfullgatherings.com"

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

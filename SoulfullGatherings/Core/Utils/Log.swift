//
//  Log.swift
//  Soulfull Gatherings
//
//  Thin `os.Logger` facade replacing the bare `print()` calls that used to ship
//  in Release builds — they wrote to the device console on customers' phones,
//  auth failures included.
//
//  `Logger` is the right tool rather than `#if DEBUG print`: it is effectively
//  free when nothing is listening, it is filterable by subsystem/category in
//  Console.app, and — the reason it matters here — string interpolation is
//  **redacted by default** in release, so an error containing a token or an
//  email doesn't leak. Anything safe to read publicly must say so explicitly
//  with `\(value, privacy: .public)`.
//

import Foundation
import os

enum Log {
    private static let subsystem = "com.soulfullgatherings.app"

    /// Session lifecycle: anonymous sign-in, account upgrade, deep links.
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Supabase fetches and cache behaviour.
    static let data = Logger(subsystem: subsystem, category: "data")

    /// Media resolution and playback.
    static let media = Logger(subsystem: subsystem, category: "media")

    /// Reservations: PaymentIntent, PaymentSheet, booking reconciliation.
    static let payment = Logger(subsystem: subsystem, category: "payment")
}

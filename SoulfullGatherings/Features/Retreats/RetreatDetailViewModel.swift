//
//  RetreatDetailViewModel.swift
//  Soulfull Gatherings
//
//  Reflects whether this retreat is already reserved. Payment state is
//  server-truth (the `stripe-webhook` Edge Function writes `bookings`); this VM
//  only reads it.
//
//  The client-side charge — `PaymentService` + `RetreatCheckoutView` +
//  `reserve()`/`confirmBooking()` — was removed with the StripePaymentSheet
//  dependency (v1). Reading a `bookings` row is plain Supabase and stays, so a
//  reservation made by any means still shows here. Restore the charge path from
//  git history if payments return; see `AppFeatures.paymentsEnabled`.
//

import SwiftUI

@Observable @MainActor
final class RetreatDetailViewModel {

    enum Phase: Equatable {
        case idle
        case reserved
        case failed(String)
    }

    let retreat: Retreat
    private(set) var phase: Phase = .idle

    init(retreat: Retreat) {
        self.retreat = retreat
    }

    var isReserved: Bool { phase == .reserved }
    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// On appear: reflect an existing paid booking so a reserved retreat shows
    /// as such. Best-effort — failures leave the screen in `.idle`.
    func loadExistingBooking(userID: UUID?) async {
        guard let userID, !isReserved else { return }
        do {
            let booking = try await SupabaseService.shared.fetchBooking(retreatID: retreat.id, userID: userID)
            if booking?.isPaid == true { phase = .reserved }
        } catch {
            Log.payment.error("Booking check failed: \(error.localizedDescription)")
        }
    }
}

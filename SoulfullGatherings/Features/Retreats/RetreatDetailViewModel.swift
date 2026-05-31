//
//  RetreatDetailViewModel.swift
//  Soulfull Gatherings
//
//  Drives the Reserve flow on the retreat detail screen: checks for an existing
//  paid booking, runs the Stripe PaymentSheet, and reflects the result. Payment
//  state is server-truth (the webhook writes `bookings`); this VM only triggers
//  the flow and mirrors the outcome locally.
//

import SwiftUI

@Observable @MainActor
final class RetreatDetailViewModel {

    enum Phase: Equatable {
        case idle
        case preparing   // requesting the PaymentIntent
        case reserved
        case failed(String)
    }

    let retreat: Retreat
    private(set) var phase: Phase = .idle

    init(retreat: Retreat) {
        self.retreat = retreat
    }

    var isReserved: Bool { phase == .reserved }
    var isBusy: Bool { phase == .preparing }
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
            print("[RetreatDetailViewModel] booking check failed: \(error)")
        }
    }

    /// Requests a PaymentIntent and presents Stripe's PaymentSheet. Caller must
    /// have already ensured the user has a permanent account.
    func reserve() async {
        phase = .preparing
        do {
            let intent = try await PaymentService.shared.createPaymentIntent(retreatID: retreat.id)
            let result = try await PaymentService.shared.presentPaymentSheet(
                for: intent,
                merchantName: "Soulfull Gatherings"
            )
            switch result {
            case .completed:
                Haptics.success()
                phase = .reserved
            case .canceled:
                phase = .idle
            case .failed(let error):
                Haptics.bump()
                phase = .failed(error.localizedDescription)
            }
        } catch {
            Haptics.bump()
            phase = .failed(error.localizedDescription)
        }
    }
}

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
        case confirming  // paid; waiting for the webhook to write `bookings`
        case reserved
        case failed(String)
    }

    let retreat: Retreat
    private(set) var phase: Phase = .idle

    init(retreat: Retreat) {
        self.retreat = retreat
    }

    var isReserved: Bool { phase == .reserved }
    /// Any in-flight state that should keep the CTA disabled.
    var isBusy: Bool { phase == .preparing || phase == .confirming }

    /// Paid, but still reconciling against the `bookings` row.
    var isConfirming: Bool { phase == .confirming }
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

    /// Requests a PaymentIntent and presents Stripe's PaymentSheet. Caller must
    /// have already ensured the user has a permanent account. `userID` is used
    /// to reconcile the resulting booking against server truth.
    func reserve(userID: UUID?) async {
        // Re-entrancy is guarded here, not only by the view disabling its
        // button: a second entry would re-enter `.preparing` and present a
        // second PaymentSheet over the first.
        guard !isBusy else { return }
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
                // Stripe says paid, but the `bookings` row is written
                // asynchronously by the webhook. Claiming `.reserved` on the
                // client alone meant a slow or failed webhook left a charged
                // customer looking at "Reserve" on the next launch, because
                // `loadExistingBooking` found nothing. Wait for server truth.
                await confirmBooking(userID: userID)
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

    /// Polls `bookings` for the row the Stripe webhook writes, with a short
    /// backoff. The charge has already succeeded at this point, so failing to
    /// see the row is a reconciliation problem, not a payment problem — say so
    /// plainly rather than reverting the CTA and inviting a second charge.
    private func confirmBooking(userID: UUID?) async {
        guard let userID else {
            phase = .reserved   // Nothing to reconcile against; trust Stripe.
            return
        }
        phase = .confirming

        // ~9s total: the webhook normally lands in well under two.
        for delay in [0.4, 0.8, 1.2, 2.0, 2.0, 2.5] {
            if let booking = try? await SupabaseService.shared.fetchBooking(retreatID: retreat.id, userID: userID),
               booking.isPaid {
                phase = .reserved
                return
            }
            try? await Task.sleep(for: .seconds(delay))
        }

        // Still nothing. The payment went through, so treat it as reserved and
        // let the user in — but leave a trail, because a booking row that never
        // arrives means the webhook needs looking at.
        Log.payment.error("Booking row not visible after payment for retreat \(self.retreat.id, privacy: .public)")
        phase = .reserved
    }
}

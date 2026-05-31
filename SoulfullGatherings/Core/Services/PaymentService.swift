//
//  PaymentService.swift
//  Soulfull Gatherings
//
//  Stripe payments façade. Calls the `create-payment-intent` Edge Function for
//  a retreat, then configures and presents Stripe's PaymentSheet. Stripe keys
//  never live in the app — the publishable key is returned by the function.
//

import SwiftUI
import UIKit
@preconcurrency import Supabase
import StripePaymentSheet

@MainActor
final class PaymentService {
    static let shared = PaymentService()

    private let client: SupabaseClient
    /// Held strongly while a sheet is on screen so it isn't deallocated mid-flow.
    private var activeSheet: PaymentSheet?

    private init() {
        client = SupabaseService.shared.client
    }

    /// Server response from `create-payment-intent`.
    struct PaymentIntent: Decodable {
        let paymentIntentClientSecret: String
        let ephemeralKeySecret: String
        let customerId: String
        let publishableKey: String
    }

    enum PaymentError: LocalizedError {
        case noPresenter
        var errorDescription: String? { "Couldn't open the payment screen. Please try again." }
    }

    private struct CreatePaymentIntentBody: Encodable {
        let retreatId: Int
        /// The version this SDK pins. The function mints the ephemeral key with
        /// exactly this so PaymentSheet never sees a version mismatch — no manual
        /// server/SDK version coordination needed.
        let stripeApiVersion: String

        enum CodingKeys: String, CodingKey {
            case retreatId = "retreat_id"
            case stripeApiVersion = "stripe_api_version"
        }
    }

    /// Requests a PaymentIntent for a retreat. The function reads the
    /// authoritative price server-side; the caller's session JWT authorizes it.
    func createPaymentIntent(retreatID: Int) async throws -> PaymentIntent {
        let body = CreatePaymentIntentBody(retreatId: retreatID,
                                           stripeApiVersion: STPAPIClient.apiVersion)
        return try await client.functions.invoke(
            "create-payment-intent",
            options: FunctionInvokeOptions(body: body)
        )
    }

    /// Configures and presents Stripe's PaymentSheet, returning its result.
    func presentPaymentSheet(for intent: PaymentIntent,
                             merchantName: String) async throws -> PaymentSheetResult {
        STPAPIClient.shared.publishableKey = intent.publishableKey

        var config = PaymentSheet.Configuration()
        config.merchantDisplayName = merchantName
        config.customer = .init(id: intent.customerId, ephemeralKeySecret: intent.ephemeralKeySecret)
        config.allowsDelayedPaymentMethods = false

        let sheet = PaymentSheet(paymentIntentClientSecret: intent.paymentIntentClientSecret,
                                 configuration: config)
        activeSheet = sheet

        guard let presenter = Self.topViewController() else {
            activeSheet = nil
            throw PaymentError.noPresenter
        }

        let result: PaymentSheetResult = await withCheckedContinuation { continuation in
            sheet.present(from: presenter) { continuation.resume(returning: $0) }
        }
        activeSheet = nil
        return result
    }

    /// Walks to the frontmost presented view controller to present from.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

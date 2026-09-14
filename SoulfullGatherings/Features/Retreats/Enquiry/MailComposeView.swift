//
//  MailComposeView.swift
//  Soulfull Gatherings
//
//  The system mail composer, wrapped for SwiftUI.
//
//  **Why the composer and not a server-side send.** An application is a
//  conversation opener: the team reads it and writes back. Sending it from the
//  guest's own address means the reply lands where they expect it, they keep a
//  copy in Sent, and they can see exactly what they are sending before it goes
//  — none of which is true of a silent POST. It also needs no mail provider,
//  no API key and no Edge Function, so there is nothing that can be
//  misconfigured into dropping an application on the floor.
//
//  The cost is that it needs Mail set up on the device. `MFMailComposeViewController.canSendMail()`
//  answers that up front and the form falls back to putting the whole
//  application on the pasteboard alongside the address — see
//  `RetreatEnquiryView.submit()`. Never present this controller without
//  checking first: presented when it can't send, it shows an empty screen.
//
//  ⚠️ `MFMailComposeViewController` must not be wrapped in effects — it is
//  UIKit-backed, and a blur or Metal effect over it renders the yellow
//  placeholder (rendering gotcha #1 in CLAUDE.md). It is presented as its own
//  full-screen sheet for that reason.
//

import MessageUI
import SwiftUI

struct MailComposeView: UIViewControllerRepresentable {

    /// What the composer reports back. `cancelled` and `sent` are both normal
    /// outcomes — a guest who backs out has not hit an error.
    enum Outcome {
        case sent
        case cancelled
        case failed
    }

    let recipients: [String]
    let subject: String
    let body: String
    let onFinish: (Outcome) -> Void

    /// Whether this device can present the composer at all.
    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {
        // Composed once; the draft belongs to the user from here.
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (Outcome) -> Void

        init(onFinish: @escaping (Outcome) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            if let error {
                Log.data.error("Mail composer failed: \(error.localizedDescription)")
            }
            switch result {
            case .sent:      onFinish(.sent)
            case .failed:    onFinish(.failed)
            // A saved draft is not a sent application, and telling someone it
            // was would be worse than saying nothing.
            case .cancelled, .saved: onFinish(.cancelled)
            @unknown default: onFinish(.cancelled)
            }
        }
    }
}

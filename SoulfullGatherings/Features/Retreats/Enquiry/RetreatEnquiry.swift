//
//  RetreatEnquiry.swift
//  Soulfull Gatherings
//
//  One completed retreat application, and the email it turns into.
//
//  The questions here mirror the "Join a retreat" form on
//  soulfullgatherings.com field for field, in the same order, with the same
//  wording and the same option lists — so an application sent from the app
//  and one sent from the website arrive in the same inbox describing the same
//  person in the same terms. Squarespace names that form **"Retreats
//  Application"**; the subject line below says the same thing.
//
//  Keeping the question text in one place (`Question`) rather than typing it
//  into the form and again into the email body is what stops the two drifting:
//  the label a guest answered and the label the team reads are the same string.
//
//  If the website form changes, change it here. The fields are not derivable
//  from anything in the app — they are the retreat team's own intake
//  questions, and the answers are only useful if they match what the team
//  already reads on every other application.
//

import Foundation

/// A validated application. The view model holds the half-filled draft; this
/// is what a *complete* one looks like, which is why every required answer is
/// non-optional here and the two optional questions are plain `String` that
/// may be empty.
struct RetreatEnquiry {

    var firstName: String
    var lastName: String
    var dateOfBirth: Date
    var basedIn: String
    var phone: String
    /// Optional on the website too.
    var instagram: String
    /// The retreat being applied for, as a display label
    /// (`"Mallorca, Spain (July 21–26, 2027)"`).
    var retreat: String
    var about: String
    var decision: Decision
    var email: String
    var investment: Investment
    /// Optional on the website too.
    var referral: String

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    // MARK: - The questions, verbatim

    /// The form's question titles, exactly as the website asks them. Used by
    /// the form UI *and* by the email body, so the two cannot disagree.
    enum Question {
        static let name = "Name"
        static let dateOfBirth = "Date of Birth"
        static let dateOfBirthHelp = "Guests must be above legal age to join."
        static let basedIn = "Where are you based?"
        static let phone = "Phone"
        static let phoneHelp = "Please make sure you can receive WhatsApp messages."
        static let instagram = "Instagram"
        static let retreat = "What retreat are you interested in attending?"
        static let about = "A little about you and why this retreat called you in."
        static let aboutHelp = "Help us get to know you, your lifestyle, personality and professional side. We'd love to know why this retreat called you in."
        static let decision = "Where are you in your decision?"
        static let email = "Email"
        static let investment = "What's the investment you usually allocate when selecting an all-inclusive experience abroad, considering being around people just like you?"
        static let referral = "Do you know a past member of Soulfull Gatherings? If so, who?"
    }

    // MARK: - Choice questions

    /// "Where are you in your decision?" — the website's three options, verbatim.
    enum Decision: String, CaseIterable, Identifiable {
        case wantToKnowMore = "Definitely want to know more"
        case excitedWantMore = "Really excited about all of it, but want to know more"
        case readyToJoin = "I'm completely ready to join"

        var id: String { rawValue }
    }

    /// The investment band. Written exactly as the website lists them —
    /// including the first one's missing thousands separator, because these
    /// are the team's own answer labels and a report that groups applications
    /// by band should group app and web submissions together.
    enum Investment: String, CaseIterable, Identifiable {
        case band3500 = "€3500+"
        case band4500 = "€4,500+"
        case band5500 = "€5,500+"
        case band6500 = "€6,500+"

        var id: String { rawValue }
    }

    // MARK: - The email

    /// Where every application goes. The same monitored inbox the website
    /// form and the three published legal pages use.
    static let recipient = LegalLinks.supportEmail

    var mailSubject: String {
        "Retreats Application — \(fullName) — \(retreat)"
    }

    /// Plain text, one question per block. The questions are long enough that
    /// a `Question: answer` line would wrap badly in Mail, so each answer sits
    /// under its question — which also means a multi-line answer (the "about
    /// you" paragraph) needs no special case.
    var mailBody: String {
        var blocks: [String] = [
            block(Question.name, fullName),
            block(Question.dateOfBirth, dateOfBirth.formatted(date: .long, time: .omitted)),
            block(Question.basedIn, basedIn),
            block(Question.phone, phone)
        ]
        if !instagram.isEmpty { blocks.append(block(Question.instagram, instagram)) }
        blocks += [
            block(Question.retreat, retreat),
            block(Question.about, about),
            block(Question.decision, decision.rawValue),
            block(Question.email, email),
            block(Question.investment, investment.rawValue)
        ]
        if !referral.isEmpty { blocks.append(block(Question.referral, referral)) }

        return """
        A new retreat application, sent from the Soulfull Gatherings iOS app.

        \(blocks.joined(separator: "\n\n"))
        """
    }

    private func block(_ question: String, _ answer: String) -> String {
        "\(question)\n\(answer.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

// MARK: - Retreat → an option on the retreat question

extension Retreat {
    /// How this retreat reads as an answer to
    /// "What retreat are you interested in attending?" — matching the shape
    /// the website's own options use ("Chamonix, France (February 1-7, 2027)").
    ///
    /// Lives here rather than on the model because it is this form's phrasing,
    /// not a general-purpose label: `when` alone omits the year, and a year is
    /// exactly what the retreat team needs to tell two cohorts apart.
    var enquiryLabel: String {
        let cal = Calendar.current
        let startYear = cal.component(.year, from: startDate)
        let endYear = cal.component(.year, from: endDate)
        let years = startYear == endYear ? "\(startYear)" : "\(startYear)–\(endYear)"
        return "\(name), \(country) (\(when), \(years))"
    }
}

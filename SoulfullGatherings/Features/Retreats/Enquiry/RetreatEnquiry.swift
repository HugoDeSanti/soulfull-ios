//
//  RetreatEnquiry.swift
//  Soulfull Gatherings
//
//  One completed retreat application, as it is sent to the server.
//
//  The questions here mirror the "Join a retreat" form on
//  soulfullgatherings.com field for field, in the same order, with the same
//  wording and the same option lists — so an application sent from the app
//  and one sent from the website arrive in the same inbox describing the same
//  person in the same terms. Squarespace names that form **"Retreats
//  Application"**; the subject line the server builds says the same thing.
//
//  `Question` holds that wording once, for the form to label its controls
//  with. The Edge Function repeats the same strings when it writes the email,
//  so the team reads an application in the words it was asked in — there is no
//  build-time link between the two, so change them together.
//
//  If the website form changes, change it here. The fields are not derivable
//  from anything in the app — they are the retreat team's own intake
//  questions, and the answers are only useful if they match what the team
//  already reads on every other application.
//
//  **This type does not render the email.** The answers are POSTed to the
//  `send-retreat-enquiry` Edge Function, which composes and sends it, so there
//  is exactly one renderer and a modified client cannot dictate what lands in
//  the team's inbox. Note what is *missing* from the payload as a result: the
//  applicant's email address. The server reads it from the caller's JWT — it is
//  the address of the account they are signed in to, which is why the form
//  shows it locked rather than asking for it.
//

import Foundation

/// A validated application. The view model holds the half-filled draft; this
/// is what a *complete* one looks like, which is why every required answer is
/// non-optional here and the two optional questions are plain `String` that
/// may be empty.
///
/// `Encodable` straight into the Edge Function's body — snake_case keys, and a
/// date of birth as a plain `yyyy-MM-dd` string rather than whatever the
/// encoder's date strategy happens to be that day.
struct RetreatEnquiry: Encodable {

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
    var investment: Investment
    /// Optional on the website too.
    var referral: String

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Wire format

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case dateOfBirth = "date_of_birth"
        case basedIn = "based_in"
        case phone, instagram, retreat, about, decision, investment, referral
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(firstName, forKey: .firstName)
        try c.encode(lastName, forKey: .lastName)
        try c.encode(Self.dayString(dateOfBirth), forKey: .dateOfBirth)
        try c.encode(basedIn, forKey: .basedIn)
        try c.encode(phone, forKey: .phone)
        try c.encode(instagram, forKey: .instagram)
        try c.encode(retreat, forKey: .retreat)
        try c.encode(about, forKey: .about)
        try c.encode(decision.rawValue, forKey: .decision)
        try c.encode(investment.rawValue, forKey: .investment)
        try c.encode(referral, forKey: .referral)
    }

    /// The calendar day the applicant picked, as `yyyy-MM-dd`.
    ///
    /// Read in the device's time zone — the one the form showed the date in.
    /// It was formatted in UTC, and the picker's value carries the time of day
    /// the wheel was opened at, so an applicant far enough from Greenwich
    /// (evenings in the Americas, mornings in Asia) sent the team the day
    /// before or after the one on their screen. Gregorian whatever the device's
    /// own calendar, so the server can always read it.
    static func dayString(_ date: Date, in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    // MARK: - The questions, verbatim

    /// The form's question titles, exactly as the website asks them. The
    /// `send-retreat-enquiry` Edge Function repeats them when it writes the
    /// email — keep the two in step by hand.
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

    // MARK: - Where it goes

    /// The monitored inbox every application lands in. Shown on the form so
    /// the applicant can see where their answers are going; the actual
    /// addressing happens server-side, in `send-retreat-enquiry`.
    static let recipient = LegalLinks.supportEmail
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

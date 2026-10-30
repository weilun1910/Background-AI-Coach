import Foundation

// MARK: - Habits and workflows

/// A habit the app can notice over time, where a tip could save the student
/// some effort. Each one is matched to workflows in the catalog.
enum Habit: String, Codable, CaseIterable {
    /// Copy-pasting back and forth between an AI chat and a document.
    case aiDocShuttle = "ai-doc-shuttle"
    /// Looking at someone's profile before a coffee chat.
    case coffeeChatPrep = "coffee-chat-prep"
    /// Reading a job posting for a company you've been writing to.
    case postingAfterDraft = "posting-after-draft"
    /// A long stretch on one reading.
    case longReading = "long-reading"
    /// A slide deck that has stayed blank for a while.
    case blankSlides = "blank-slides"
    /// Pasting your resume into a new AI chat again.
    case resumeRepaste = "resume-repaste"

    /// The moment it's closest to, for the card's icon and wording.
    var momentKind: MomentKind {
        switch self {
        case .aiDocShuttle, .postingAfterDraft, .resumeRepaste: return .writing
        case .coffeeChatPrep: return .networking
        case .longReading: return .reading
        case .blankSlides: return .presentation
        }
    }
}

struct Workflow: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var habit: Habit
    /// One line for the card.
    var summary: String
    var why: String
    /// AI apps that can run it, like "chatgpt" or "claude".
    var hubs: [String]
    /// Or specific tools from the catalog, like Gemini Notebook.
    var tools: [String]?
    /// Careers it suits best. Empty means everyone.
    var careers: [String]?
    var steps: [String]
    /// The prompt, with {org}, {doc}, {role} and {topic} filled in on the Mac.
    var prompt: String
    /// A line added to the prompt for a career, like action titles for consulting.
    var careerPrompts: [String: String]?
    /// Where to look for a new tool when nothing the student has can run it.
    var bucket: String?
    var score: Double
    var source: String?
}

// MARK: - Careers

enum Careers {
    static let all: [(id: String, name: String)] = [
        ("consulting", "Consulting"),
        ("finance", "Finance and banking"),
        ("tech", "Tech and product"),
        ("software", "Software engineering"),
        ("design", "Design"),
        ("research", "Research and academia"),
        ("health", "Medicine and health"),
        ("policy", "Policy, law and government"),
        ("media", "Media and the arts"),
        ("undecided", "Not sure yet"),
    ]

    static func name(_ id: String) -> String {
        all.first { $0.id == id }?.name ?? id
    }

    /// Short names for running text: "consulting and policy".
    static let short = ["consulting": "consulting", "finance": "finance", "tech": "tech", "software": "software engineering", "design": "design", "research": "research", "health": "medicine", "policy": "policy", "media": "media", "undecided": "exploring"]

    static func list(_ ids: [String]) -> String {
        let names = ids.map { short[$0] ?? name($0).lowercased() }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}

// MARK: - What the app noticed

enum ActivityKind: String, Codable, CaseIterable {
    case drafting, reading, jobPosting, profile, aiChat, slides, notes, email, coding, design, browsing, other

    var isDocument: Bool { self == .drafting }
}

/// One line in the activity journal. Only this label is kept, never the
/// window's text or a picture of it.
struct ActivityEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var app: String
    var bundleID: String?
    var kind: ActivityKind
    var label: String
    var topic: String?
    var organization: String?
    var careerRelated: Bool
    var cues: Set<String>
    /// "title" for a window title, "look" for a look at the window.
    var source: String
    var readBy: Detector
}

/// Labels of what the app noticed, kept on this Mac for 14 days.
final class ActivityJournal {
    let url: URL
    static let keepDays = 14.0
    private(set) var entries: [ActivityEntry] = []

    init(url: URL) {
        self.url = url
        load()
        prune()
    }

    private func load() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = text.split(separator: "\n").compactMap { try? decoder.decode(ActivityEntry.self, from: Data($0.utf8)) }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let lines = entries.compactMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        if lines.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func append(_ entry: ActivityEntry) {
        var clean = entry
        clean.label = Redact.clean(entry.label)
        clean.topic = entry.topic.map(Redact.clean)
        entries.append(clean)
        save()
    }

    func prune(now: Date = Clock.now) {
        let cutoff = now.addingTimeInterval(-Self.keepDays * 86_400)
        let before = entries.count
        entries.removeAll { $0.date < cutoff }
        if entries.count != before { save() }
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: url)
    }

    func today(_ now: Date = Clock.now) -> [ActivityEntry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: now) && $0.date <= now }
    }
}

/// Strips things that shouldn't sit in a label even on this Mac.
enum Redact {
    static func clean(_ text: String) -> String {
        var s = text
        let patterns = [
            #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            #"https?://\S+"#,
            #"\+?\d[\d\s().-]{7,}\d"#,
            #"\d{4,}"#,
        ]
        for pattern in patterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Never read

/// Windows the app never reads and never interrupts.
enum NeverRead {
    static let apps: [(id: String, name: String)] = [
        ("com.1password.1password", "1Password"),
        ("com.agilebits.onepassword7", "1Password 7"),
        ("com.bitwarden.desktop", "Bitwarden"),
        ("com.apple.Passwords", "Passwords"),
        ("com.apple.keychainaccess", "Keychain Access"),
        ("com.apple.MobileSMS", "Messages"),
        ("net.whatsapp.WhatsApp", "WhatsApp"),
        ("org.whispersystems.signal-desktop", "Signal"),
        ("ru.keepcoder.Telegram", "Telegram"),
        ("com.hnc.Discord", "Discord"),
        ("com.apple.mail", "Mail"),
        ("com.apple.FaceTime", "FaceTime"),
    ]

    /// Words in a window title that mean the window is private.
    static let titleWords = [
        "private browsing", "incognito", "inprivate", "password", "passcode", "sign in", "log in",
        "bank", "chase", "venmo", "paypal", "zelle", "robinhood", "fidelity", "schwab", "credit card",
        "social security", "tax return", "mychart", "patient portal", "therapy", "medical record",
    ]

    /// Why this window is off limits, or nil if it's fine to read.
    static func reason(bundleID: String?, app: String, title: String, extra: Set<String>) -> String? {
        if let bundleID, extra.contains(bundleID) { return "you added \(app) to the never-read list" }
        if let bundleID, apps.contains(where: { $0.id == bundleID }) { return "\(app) is on the never-read list" }
        if let bundleID, AppMoments.callApps.contains(bundleID) { return "you look like you're on a call" }
        let t = title.lowercased()
        if let word = titleWords.first(where: { t.contains($0) }) {
            return "the window title mentions \u{201C}\(word)\u{201D}"
        }
        return nil
    }
}

// MARK: - Focus

/// Which window was in front and when. Kept in memory for an hour, never saved.
struct FocusSample {
    var date: Date
    var bundleID: String
    var app: String
    var title: String
}

final class FocusTracker {
    private(set) var samples: [FocusSample] = []

    func record(bundleID: String, app: String, title: String, at date: Date = Clock.now) {
        if let last = samples.last, last.bundleID == bundleID, last.title == title { return }
        samples.append(FocusSample(date: date, bundleID: bundleID, app: app, title: title))
        samples.removeAll { date.timeIntervalSince($0.date) > 3600 }
    }

    var current: FocusSample? { samples.last }

    /// How long the current window has been in front.
    func dwell(now: Date = Clock.now) -> TimeInterval {
        guard let current else { return 0 }
        return now.timeIntervalSince(current.date)
    }

    /// How many times focus moved between the two kinds of window lately.
    func switches(within seconds: TimeInterval, now: Date = Clock.now, _ a: (FocusSample) -> Bool, _ b: (FocusSample) -> Bool) -> (count: Int, aName: String?, bName: String?) {
        let recent = samples.filter { now.timeIntervalSince($0.date) <= seconds }
        var count = 0
        var aName: String?
        var bName: String?
        var previous: Bool?
        for sample in recent {
            let side: Bool? = a(sample) ? true : (b(sample) ? false : nil)
            guard let side else { continue }
            if side { aName = sample.app } else { bName = sample.app }
            if let previous, previous != side { count += 1 }
            previous = side
        }
        return (count, aName, bName)
    }

    func clear() { samples = [] }
}

// MARK: - Apps the habits care about

enum HabitApps {
    static let aiChat: [String: String] = [
        "com.openai.chat": "ChatGPT",
        "com.openai.codex": "ChatGPT",
        "com.anthropic.claudefordesktop": "Claude",
        "com.google.GeminiMacOS": "Gemini",
        "com.microsoft.copilot-mac": "Copilot",
        "ai.perplexity.mac": "Perplexity",
    ]
    static let documents: Set<String> = ["com.microsoft.Word", "com.apple.iWork.Pages"]
    static let slides: Set<String> = ["com.apple.iWork.Keynote", "com.microsoft.Powerpoint"]
    static let readers: Set<String> = ["com.apple.Preview", "net.sourceforge.skim-app.skim"]
    static let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser"]

    static func isAIChat(_ s: FocusSample) -> Bool {
        if aiChat[s.bundleID] != nil { return true }
        let t = s.title.lowercased()
        return browsers.contains(s.bundleID) && ["chatgpt", "claude", "gemini"].contains { t.contains($0) }
    }

    static func isDocument(_ s: FocusSample) -> Bool {
        documents.contains(s.bundleID) || (browsers.contains(s.bundleID) && s.title.lowercased().contains("google docs"))
    }

    /// "ChatGPT" for the ChatGPT app or a ChatGPT tab.
    static func chatName(_ s: FocusSample) -> String {
        if let name = aiChat[s.bundleID] { return name }
        let t = s.title.lowercased()
        if t.contains("claude") { return "Claude" }
        if t.contains("gemini") { return "Gemini" }
        return "ChatGPT"
    }
}

// MARK: - Habit detection

struct HabitMatch {
    var habit: Habit
    /// What the app noticed, in plain words, for the card's headline.
    var noticed: String
    var organization: String?
    var topic: String?
    var role: String?
    /// One card per habit and subject a day.
    var key: String
}

/// Rules over the window in front, today's labels and the calendar.
/// Each rule needs evidence from more than one moment, or a stretch of time.
@MainActor
struct HabitDetector {
    let focus: FocusTracker
    let journal: [ActivityEntry]
    let upcoming: [UpcomingItem]
    let now: Date

    static let shuttleWindow: TimeInterval = 20 * 60
    static let shuttleSwitches = 4
    static let readingMinutes = 25.0
    static let blankMinutes = 10.0

    private var day: String { now.formatted(.iso8601.year().month().day()) }

    /// Habits that show up in one look at a window, plus what came before it.
    /// Switching habits are checked separately, when the window changes.
    func match(_ entry: ActivityEntry, dwell: TimeInterval) -> HabitMatch? {
        if let m = coffeeChatPrep(entry) { return m }
        if let m = postingAfterDraft(entry) { return m }
        if let m = resumeRepaste(entry) { return m }
        if let m = blankSlides(entry, dwell: dwell) { return m }
        if let m = longReading(entry, dwell: dwell) { return m }
        return nil
    }

    func aiDocShuttle() -> HabitMatch? {
        let result = focus.switches(within: Self.shuttleWindow, now: now, HabitApps.isAIChat, HabitApps.isDocument)
        guard result.count >= Self.shuttleSwitches else { return nil }
        let chat = focus.samples.last(where: HabitApps.isAIChat).map(HabitApps.chatName) ?? "your AI app"
        let doc = result.bName ?? "your document"
        let draft = journal.last { $0.kind == .drafting && Timing.isToday($0.date, now: now) }
        let org = draft?.organization
        let minutes = max(1, Int(Self.shuttleWindow / 60))
        return HabitMatch(
            habit: .aiDocShuttle,
            noticed: "You've gone back and forth between \(chat) and \(shortApp(doc)) \(result.count) times in the last \(minutes) minutes.",
            organization: org,
            topic: draft?.topic,
            key: "habit:\(Habit.aiDocShuttle.rawValue):\(day)"
        )
    }

    func coffeeChatPrep(_ entry: ActivityEntry) -> HabitMatch? {
        guard entry.kind == .profile else { return nil }
        let soon = upcoming.first { item in
            guard let kind = item.kind, [.networking, .interview].contains(kind) else { return false }
            let lead = item.start.timeIntervalSince(now)
            return lead > 0 && lead <= 3 * 3600
        }
        guard let soon else { return nil }
        let org = entry.organization ?? OrgNames.organization(in: soon.title)
        let what = soon.kind == .interview ? "interview" : "coffee chat"
        let site = entry.cues.contains("profile") ? "LinkedIn" : entry.app
        return HabitMatch(
            habit: .coffeeChatPrep,
            noticed: "You're looking at someone's profile on \(site), and your \(org.map { OrgNames.shortOrg($0) + " " } ?? "")\(what) is at \(soon.start.formatted(date: .omitted, time: .shortened)).",
            organization: org,
            topic: entry.topic,
            role: entry.cues.first { $0.hasPrefix("role:") }.map { String($0.dropFirst(5)) },
            key: "habit:\(Habit.coffeeChatPrep.rawValue):\(soon.id)"
        )
    }

    func postingAfterDraft(_ entry: ActivityEntry) -> HabitMatch? {
        guard entry.kind == .jobPosting, let org = entry.organization else { return nil }
        let key = OrgNames.orgKey(org)
        let draft = journal.last { $0.kind == .drafting && $0.organization.map(OrgNames.orgKey) == key && $0.date < entry.date }
        guard let draft else { return nil }
        let when = Timing.isToday(draft.date, now: now) ? (Calendar.current.component(.hour, from: draft.date) < 12 ? "this morning" : "earlier today") : "on \(draft.date.formatted(.dateTime.weekday(.wide)))"
        return HabitMatch(
            habit: .postingAfterDraft,
            noticed: "You're reading the \(OrgNames.shortOrg(org)) posting, and you worked on your \(OrgNames.shortOrg(org)) \(draft.topic ?? "draft") \(when).",
            organization: org,
            topic: draft.topic,
            key: "habit:\(Habit.postingAfterDraft.rawValue):\(key):\(day)"
        )
    }

    func resumeRepaste(_ entry: ActivityEntry) -> HabitMatch? {
        guard entry.kind == .aiChat, entry.cues.contains("resume") else { return nil }
        let earlier = journal.last { $0.kind == .aiChat && $0.cues.contains("resume") && entry.date.timeIntervalSince($0.date) > 2 * 3600 }
        guard let earlier else { return nil }
        let when = Timing.isToday(earlier.date, now: now) ? "earlier today" : "on \(earlier.date.formatted(.dateTime.weekday(.wide)))"
        return HabitMatch(
            habit: .resumeRepaste,
            noticed: "You've pasted your resume into a new \(entry.app) chat again. The last time was \(when).",
            key: "habit:\(Habit.resumeRepaste.rawValue):\(day)"
        )
    }

    func blankSlides(_ entry: ActivityEntry, dwell: TimeInterval) -> HabitMatch? {
        guard entry.kind == .slides, entry.cues.contains("blank"), dwell >= Self.blankMinutes * 60 else { return nil }
        return HabitMatch(
            habit: .blankSlides,
            noticed: "Your deck in \(shortApp(entry.app)) has been mostly empty for \(Int(dwell / 60)) minutes.",
            organization: entry.organization,
            topic: entry.topic,
            key: "habit:\(Habit.blankSlides.rawValue):\(day)"
        )
    }

    func longReading(_ entry: ActivityEntry, dwell: TimeInterval) -> HabitMatch? {
        guard entry.kind == .reading, dwell >= Self.readingMinutes * 60 else { return nil }
        return HabitMatch(
            habit: .longReading,
            noticed: "You've been on the same reading for \(Int(dwell / 60)) minutes.",
            topic: entry.topic,
            key: "habit:\(Habit.longReading.rawValue):\(day)"
        )
    }

    private func shortApp(_ name: String) -> String {
        name.replacingOccurrences(of: "Microsoft ", with: "")
    }
}

// MARK: - Text helpers

enum OrgNames {
    /// Employers the rules know by name. The model handles the rest.
    static let knownOrgs = [
        "McKinsey & Company", "McKinsey", "Bain & Company", "Bain", "Boston Consulting Group", "BCG",
        "Goldman Sachs", "Morgan Stanley", "J.P. Morgan", "JPMorgan", "Jane Street", "Citadel", "Evercore",
        "Lazard", "Deloitte", "Accenture", "PwC", "KPMG", "Google", "Microsoft", "Apple", "Meta", "Amazon",
        "Teach For America", "Fulbright",
    ]

    /// The first employer named in the text, if any.
    static func organization(in text: String) -> String? {
        let lower = text.lowercased()
        var best: (index: String.Index, name: String)?
        for name in knownOrgs {
            guard let range = lower.range(of: name.lowercased()) else { continue }
            if best == nil || range.lowerBound < best!.index { best = (range.lowerBound, name) }
        }
        return best?.name
    }

    /// "McKinsey & Company" and "McKinsey" are the same employer.
    static func orgKey(_ org: String) -> String {
        shortOrg(org).lowercased()
    }

    /// The name people use: "McKinsey" for "McKinsey & Company".
    static func shortOrg(_ org: String) -> String {
        var s = org
        for suffix in [" & Company", " & Co.", " & Co", ", Inc.", " Inc.", " Inc", " LLC", " Group"] where s.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
        }
        if s == "Boston Consulting" { return "BCG" }
        return s
    }
}

// MARK: - What it learned

/// What the outcome log says about this student, worked out on the Mac.
struct Learned: Equatable {
    /// Apps where cards wait, by bundle ID, with how many cards were put off there.
    var holdApps: [String: Int] = [:]
    /// Multipliers for tools and workflows the student acted on or waved away.
    var weights: [String: Double] = [:]
    /// The same, in plain words, for the menu and Settings.
    var lines: [String] = []

    static let holdAfter = 2
    static let lookback: TimeInterval = 14 * 86_400

    static func from(_ events: [OutcomeEvent], now: Date, appName: (String) -> String) -> Learned {
        var learned = Learned()
        let recent = events.filter { now.timeIntervalSince($0.date) <= lookback && $0.date <= now }

        for event in recent where ["later", "dismissed"].contains(event.event) {
            guard let app = event.app, !app.isEmpty, !AppMoments.callApps.contains(app) else { continue }
            learned.holdApps[app, default: 0] += 1
        }
        learned.holdApps = learned.holdApps.filter { $0.value >= holdAfter }

        var acted = 0
        for event in recent {
            let key = event.workflow ?? event.tool
            guard !key.isEmpty else { continue }
            let delta: Double
            switch event.event {
            case "tip_opened", "coach_opened", "setup_started": delta = 0.1
            case "later": delta = -0.08
            case "dismissed": delta = -0.12
            default: delta = 0
            }
            if event.event == "tip_opened" { acted += 1 }
            if delta != 0 { learned.weights[key, default: 1] += delta }
        }
        learned.weights = learned.weights.mapValues { min(1.3, max(0.6, $0)) }

        for (app, count) in learned.holdApps.sorted(by: { $0.key < $1.key }) {
            learned.lines.append("Cards wait while you're in \(appName(app)). You put off or closed \(count) there in the last two weeks.")
        }
        if acted > 0 {
            learned.lines.append("You've opened \(acted == 1 ? "a tip" : "\(acted) tips") lately, so tips like \(acted == 1 ? "it" : "those") rank a little higher.")
        }
        return learned
    }

    func weight(_ key: String) -> Double { weights[key] ?? 1 }
}

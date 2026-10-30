import Foundation

// MARK: - Moments

/// A workflow moment the app can notice. Buckets in the catalog list the
/// moments they cover, so this is the shared vocabulary between the cloud
/// catalog and the Mac.
enum MomentKind: String, Codable, CaseIterable, Identifiable {
    case meeting, networking, interview, lecture, exam, presentation, writing, reading, design, coding

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meeting: return "Meeting"
        case .networking: return "Coffee chat"
        case .interview: return "Interview"
        case .lecture: return "Class or seminar"
        case .exam: return "Exam"
        case .presentation: return "Presentation"
        case .writing: return "Writing deadline"
        case .reading: return "Reading"
        case .design: return "Design work"
        case .coding: return "Coding"
        }
    }

    var symbol: String {
        switch self {
        case .meeting: return "person.3"
        case .networking: return "cup.and.saucer"
        case .interview: return "person.crop.rectangle"
        case .lecture: return "building.columns"
        case .exam: return "checklist"
        case .presentation: return "play.rectangle"
        case .writing: return "doc.text"
        case .reading: return "book"
        case .design: return "paintbrush.pointed"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Used in walkthrough titles, e.g. "Using Granola for your coffee chat".
    var phrase: String {
        switch self {
        case .meeting: return "your meeting"
        case .networking: return "your coffee chat"
        case .interview: return "your interview"
        case .lecture: return "your class"
        case .exam: return "your exam"
        case .presentation: return "your presentation"
        case .writing: return "your draft"
        case .reading: return "your reading"
        case .design: return "your design work"
        case .coding: return "your code"
        }
    }

    /// "a coffee chat", "an interview"
    var withArticle: String {
        if self == .reading { return "reading time" }
        let l = label.lowercased()
        let vowel = l.first.map { "aeiou".contains($0) } ?? false
        return (vowel ? "an " : "a ") + l
    }
}

enum SignalSource: String, Codable {
    case calendar, activeApp, simulated
    /// Window titles and occasional looks at the front window.
    case screen
}

enum Detector: String, Codable {
    case onDeviceModel, rules, appRules, habitRules

    var label: String {
        switch self {
        case .onDeviceModel: return "Apple's on-device model"
        case .rules: return "keyword rules"
        case .appRules: return "app rules"
        case .habitRules: return "habit rules"
        }
    }
}

struct Moment: Identifiable, Equatable {
    var id: String
    var kind: MomentKind
    var source: SignalSource
    var title: String
    var startDate: Date?
    var detectedBy: Detector
    var context: String?
    var detectedAt = Clock.now
}

// MARK: - Catalog

struct Catalog: Codable {
    var version: String
    var publishedAt: String
    var note: String?
    var buckets: [Bucket]
    var tools: [Tool]
    /// Tips and workflows for tools people already have. Older catalogs have none.
    var workflows: [Workflow]?

    static let empty = Catalog(version: "none", publishedAt: "", note: nil, buckets: [], tools: [], workflows: [])

    func bucket(_ id: String) -> Bucket? { buckets.first { $0.id == id } }
    func tool(_ id: String) -> Tool? { tools.first { $0.id == id } }
    func workflow(_ id: String) -> Workflow? { (workflows ?? []).first { $0.id == id } }
    func workflows(for habit: Habit) -> [Workflow] { (workflows ?? []).filter { $0.habit == habit } }
    func tools(in bucket: Bucket) -> [Tool] { tools.filter { $0.buckets.contains(bucket.id) } }
    func buckets(for kind: MomentKind) -> [Bucket] { buckets.filter { $0.moments.contains(kind) } }
}

struct Bucket: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var plural: String
    var job: String
    var gapLine: String
    var moments: [MomentKind]
    var symbol: String
}

enum ToolKind: String, Codable {
    /// A Mac app we can see in /Applications.
    case app
    /// A website. We can't see it, so the user tells us if they use it.
    case web
    /// A feature inside something else (a hub like ChatGPT, or an app like Zoom).
    case feature
    /// An MCP server added to Claude Code.
    case claudeMCP
    /// A command-line tool.
    case cli
}

enum Evidence: String, Codable {
    case onPaper, tested, outcomes

    var label: String {
        switch self {
        case .onPaper: return "Checked against docs"
        case .tested: return "Tested by our team"
        case .outcomes: return "Students kept using it"
        }
    }

    var symbol: String {
        switch self {
        case .onPaper: return "doc.text.magnifyingglass"
        case .tested: return "checkmark.seal"
        case .outcomes: return "person.2"
        }
    }
}

struct Detect: Codable, Hashable {
    var appNames: [String]?
    var mcpServers: [String]?
    var commands: [String]?
}

enum SetupMethod: String, Codable {
    case brewCask, openURL, claudeMCP
}

struct SetupRecipe: Codable, Hashable {
    var method: SetupMethod
    var brewCask: String?
    var url: String?
    var command: String?
    var steps: [String]
    var minutes: Int
}

struct Tool: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var vendor: String
    var kind: ToolKind
    var hub: String?
    var symbol: String
    var requires: String?
    /// Moments this tool is a poor fit for, even though its bucket covers them.
    /// Zoom's summary only works when you host, so not for coffee chats.
    var notFor: [MomentKind]?
    var buckets: [String]
    var scores: [String: Double]
    var evidence: Evidence
    var free: Bool
    var cost: String
    var dataAccess: String
    var consentNote: String?
    var why: String
    var coachLine: String?
    var avoidIf: String?
    var detect: Detect
    var setup: SetupRecipe
    var walkthrough: [String: [String]]
    /// A version of the walkthrough for a career, like a case interview for consulting.
    var careerWalkthrough: [String: [String]]?
    /// Careers this tool is especially good for. It ranks a little higher for them.
    var careers: [String]?
    var source: String

    func score(for bucket: String) -> Double { scores[bucket] ?? 0 }

    func walkthrough(for kind: MomentKind) -> [String] {
        walkthrough[kind.rawValue] ?? walkthrough["default"] ?? walkthrough.values.first ?? []
    }

    func walkthrough(for kind: MomentKind, careers: [String]) -> [String] {
        for career in careers {
            if let steps = careerWalkthrough?[career] { return steps }
        }
        return walkthrough(for: kind)
    }

    /// Tools the user has to tell us about, because the Mac can't see them.
    var isSelfReported: Bool { kind == .web || kind == .feature }

    func fits(_ kind: MomentKind) -> Bool { !(notFor ?? []).contains(kind) }
}

/// What happened when a moment came in.
enum HandleResult {
    case shown(Suggestion)
    case held(Suggestion, String)
    case quiet(String)
    case duplicate
}

// MARK: - Decisions

enum ToolUsage {
    case none, owned, inUse
}

enum BucketState: Equatable {
    case empty
    case unused([String])
    case inUse([String])
    case notForMe
}

enum SuggestionKind: String {
    /// The bucket is empty: suggest a new tool and set it up.
    case setUp
    /// The user owns a tool for this but isn't using it: show them how.
    case coach
    /// A habit could go better with a tool the user already has: a workflow and a prompt.
    case tip
}

struct Suggestion: Identifiable, Equatable {
    let id = UUID()
    var moment: Moment
    var bucket: Bucket
    var tool: Tool
    var kind: SuggestionKind
    var headline: String
    var detail: String
    /// For tips: the workflow, and its prompt filled in for this moment.
    var workflow: Workflow? = nil
    var prompt: String? = nil
    /// Where the app got this from, in plain words. "From a look at this window."
    var how: String? = nil
    /// What it learned that shaped this card, if anything.
    var learned: String? = nil
    /// Steps for the rundown, already picked for the user's career.
    var steps: [String] = []

    static func == (a: Suggestion, b: Suggestion) -> Bool { a.id == b.id }
}

enum PanelState: Equatable {
    case card(Suggestion)
    case setup(Suggestion)
    case walkthrough(Suggestion)
    case done(Suggestion)
    case quiet(title: String, reason: String)
}

struct ActivityItem: Identifiable {
    let id = UUID()
    var date = Clock.now
    var symbol: String
    var title: String
    var detail: String
}

struct UpcomingItem: Identifiable {
    var id: String
    var title: String
    var start: Date
    var kind: MomentKind?
    var detectedBy: Detector
}

extension String {
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
}

enum Timing {
    static func phrase(until start: Date, now: Date = Clock.now) -> String {
        let mins = Int((start.timeIntervalSince(now) / 60).rounded())
        if mins <= 0 { return "is happening now" }
        if mins < 60 { return "starts in \(mins) min" }
        let time = start.formatted(date: .omitted, time: .shortened)
        if isToday(start, now: now) { return "is today at \(time)" }
        if isTomorrow(start, now: now) { return "is tomorrow at \(time)" }
        let day = start.formatted(.dateTime.weekday(.wide))
        return "is on \(day) at \(time)"
    }

    static func short(_ start: Date, now: Date = Clock.now) -> String {
        let time = start.formatted(date: .omitted, time: .shortened)
        if isToday(start, now: now) { return time }
        if isTomorrow(start, now: now) { return "Tomorrow \(time)" }
        return start.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

    static func isToday(_ date: Date, now: Date = Clock.now) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: now)
    }

    static func isTomorrow(_ date: Date, now: Date = Clock.now) -> Bool {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return false }
        return Calendar.current.isDate(date, inSameDayAs: tomorrow)
    }
}

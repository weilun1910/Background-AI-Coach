import Foundation

/// Everything the app saves lives in one folder on this Mac:
/// ~/Library/Application Support/Background AI Coach
final class Store {
    let dir: URL

    init() {
        if let custom = ProcessInfo.processInfo.environment["RECOMMENDER_DATA_DIR"] {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        } else if AppModel.personaLaunch {
            // The persona demo never writes into your real settings.
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("Background AI Coach Personas", isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Background AI Coach", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, _ name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value) {
            try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }
}

enum CatalogLoader {
    /// Order: an explicit override, the catalog shipped in the app, then the
    /// last downloaded copy. In production the daily download would come first.
    static func load(cacheDir: URL) -> (Catalog, String?) {
        var urls: [URL] = []
        if let env = ProcessInfo.processInfo.environment["RECOMMENDER_CATALOG"] {
            urls.append(URL(fileURLWithPath: env))
        }
        if let bundled = Bundle.main.url(forResource: "catalog", withExtension: "json") {
            urls.append(bundled)
        }
        urls.append(cacheDir.appendingPathComponent("catalog.json"))

        var lastError: String?
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                return (try JSONDecoder().decode(Catalog.self, from: data), nil)
            } catch {
                lastError = "Couldn't read \(url.lastPathComponent): \(error)"
            }
        }
        return (.empty, lastError ?? "No catalog found.")
    }
}

struct DemoSettings: Codable, Equatable {
    /// Ignore what's installed, so suggestions show up on a well-stocked Mac.
    var freshMac = false
    /// Walk through setup without installing anything.
    var dryRun = false
    /// Let more than the daily limit through.
    var ignoreCap = false
}

struct Preferences: Codable, Equatable {
    var onboarded = false
    var mainHub = "none"
    var freeOnly = true
    var selfReported: Set<String> = []
    var notForMe: Set<String> = []
    var dailyCap = 1
    var pausedUntil: Date?
    var calendarEnabled = true
    var appSensorEnabled = true
    var useOnDeviceModel = true
    var demo = DemoSettings()
    /// Careers the student is working toward, from onboarding.
    var careers: [String] = []
    var recruitingNow = false
    /// Read the title of the window in front. Needs Accessibility. Off by default.
    var windowTitlesEnabled = false
    /// Take an occasional look at the window in front. Needs Screen Recording. Off by default.
    var screenLooksEnabled = false
    /// Apps the student added to the never-read list, by bundle ID.
    var neverRead: Set<String> = []
    /// Workflows the student said no to.
    var notForMeWorkflows: Set<String> = []
    /// New apps it may suggest in a week. 0 means no limit.
    var newToolsPerWeek = 1

    static let hubs: [(id: String, name: String)] = [
        ("claude", "Claude"),
        ("chatgpt", "ChatGPT"),
        ("gemini", "Gemini"),
        ("copilot", "Copilot"),
        ("none", "None yet"),
    ]

    init() {}

    // Decode field by field so older saved files still load after new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? d.onboarded
        mainHub = try c.decodeIfPresent(String.self, forKey: .mainHub) ?? d.mainHub
        freeOnly = try c.decodeIfPresent(Bool.self, forKey: .freeOnly) ?? d.freeOnly
        selfReported = try c.decodeIfPresent(Set<String>.self, forKey: .selfReported) ?? d.selfReported
        notForMe = try c.decodeIfPresent(Set<String>.self, forKey: .notForMe) ?? d.notForMe
        dailyCap = try c.decodeIfPresent(Int.self, forKey: .dailyCap) ?? d.dailyCap
        pausedUntil = try c.decodeIfPresent(Date.self, forKey: .pausedUntil)
        calendarEnabled = try c.decodeIfPresent(Bool.self, forKey: .calendarEnabled) ?? d.calendarEnabled
        appSensorEnabled = try c.decodeIfPresent(Bool.self, forKey: .appSensorEnabled) ?? d.appSensorEnabled
        useOnDeviceModel = try c.decodeIfPresent(Bool.self, forKey: .useOnDeviceModel) ?? d.useOnDeviceModel
        demo = try c.decodeIfPresent(DemoSettings.self, forKey: .demo) ?? d.demo
        careers = try c.decodeIfPresent([String].self, forKey: .careers) ?? d.careers
        recruitingNow = try c.decodeIfPresent(Bool.self, forKey: .recruitingNow) ?? d.recruitingNow
        windowTitlesEnabled = try c.decodeIfPresent(Bool.self, forKey: .windowTitlesEnabled) ?? d.windowTitlesEnabled
        screenLooksEnabled = try c.decodeIfPresent(Bool.self, forKey: .screenLooksEnabled) ?? d.screenLooksEnabled
        neverRead = try c.decodeIfPresent(Set<String>.self, forKey: .neverRead) ?? d.neverRead
        notForMeWorkflows = try c.decodeIfPresent(Set<String>.self, forKey: .notForMeWorkflows) ?? d.notForMeWorkflows
        newToolsPerWeek = try c.decodeIfPresent(Int.self, forKey: .newToolsPerWeek) ?? d.newToolsPerWeek
    }

    /// Either screen signal is on, so the app looks for habits.
    var behaviorOn: Bool { windowTitlesEnabled || screenLooksEnabled }
}

/// Bookkeeping that isn't a preference: which moments were already handled.
struct RuntimeState: Codable {
    var handled: [String: Date] = [:]
    var reused: Set<String> = []
}

// MARK: - Outcome log

/// One line per thing that happened to a suggestion. Stays on this Mac.
struct OutcomeEvent: Codable {
    var date: Date
    var event: String
    var tool: String
    var bucket: String
    var moment: String
    var source: String
    /// The app in front when it happened, so the app can learn when not to interrupt.
    var app: String? = nil
    /// setUp, coach or tip.
    var kind: String? = nil
    var workflow: String? = nil
}

final class OutcomeLog {
    let url: URL
    private(set) var events: [OutcomeEvent] = []

    init(url: URL) {
        self.url = url
        load()
    }

    private func load() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        events = text.split(separator: "\n").compactMap { line in
            try? decoder.decode(OutcomeEvent.self, from: Data(line.utf8))
        }
    }

    func append(_ event: OutcomeEvent) {
        events.append(event)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(event) else { return }
        let line = data + Data("\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    func clear() {
        events = []
        try? FileManager.default.removeItem(at: url)
    }

    func count(_ event: String, on day: Date) -> Int {
        events.filter { $0.event == event && Calendar.current.isDate($0.date, inSameDayAs: day) }.count
    }

    func lastDate(_ event: String, tool: String) -> Date? {
        events.last { $0.event == event && $0.tool == tool }?.date
    }

    /// New apps suggested in the last week, for the one-new-app-a-week limit.
    func newToolsShown(since date: Date) -> Int {
        events.filter { $0.event == "shown" && $0.kind == "setUp" && $0.date >= date }.count
    }

    /// Adds past events without touching the file. The persona demo uses this.
    func seed(_ past: [OutcomeEvent]) {
        events.insert(contentsOf: past, at: 0)
    }
}

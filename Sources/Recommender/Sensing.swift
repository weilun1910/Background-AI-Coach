import AppKit
import EventKit

// MARK: - Calendar

enum CalendarAccess {
    case notDetermined, granted, denied
}

/// Reads event titles and times from calendars added to this Mac.
final class CalendarSensor {
    let store = EKEventStore()

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func events(from start: Date, to end: Date) -> [EKEvent] {
        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }
}

// MARK: - Active app

/// Tells us which app just came to the front. No window titles, no screen.
final class ActiveAppSensor {
    var onActivate: ((NSRunningApplication) -> Void)?
    private var token: NSObjectProtocol?

    func start() {
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onActivate?(app)
        }
    }
}

enum AppMoments {
    /// Apps whose repeated use counts as a workflow moment.
    static let map: [String: MomentKind] = [
        "com.figma.Desktop": .design,
        "com.canva.CanvaDesktop": .design,
        "com.microsoft.VSCode": .coding,
        "com.apple.dt.Xcode": .coding,
        "com.todesktop.230313mzl4w4u92": .coding,
        "com.apple.Terminal": .coding,
        "com.googlecode.iterm2": .coding,
        "com.mitchellh.ghostty": .coding,
        "com.apple.iWork.Keynote": .presentation,
        "com.microsoft.Powerpoint": .presentation,
        "com.microsoft.Word": .writing,
        "com.apple.iWork.Pages": .writing,
        "com.apple.Preview": .reading,
        "net.sourceforge.skim-app.skim": .reading,
    ]

    /// While one of these is in front, the user is probably on a call. Not a calm moment.
    static let callApps: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.apple.FaceTime",
        "com.cisco.webexmeetingsapp",
        "Cisco-Systems.Spark",
    ]
}

// MARK: - Inventory

struct InstalledApp {
    var name: String
    var url: URL
    var bundleID: String?
    var lastUsed: Date?
}

/// What the user already has: installed apps (with when they were last
/// opened), Claude Code MCP servers, and a few command-line tools.
final class Inventory {
    private(set) var apps: [String: InstalledApp] = [:]
    private(set) var mcpServers: Set<String> = []
    private(set) var commands: Set<String> = []
    private(set) var refreshedAt: Date?
    /// True when a persona's pretend Mac is loaded. Then nothing real is scanned.
    private(set) var isFixture = false

    func loadFixture(apps: [(name: String, lastUsed: Date?)], mcpServers: [String], commands: [String]) {
        isFixture = true
        var found: [String: InstalledApp] = [:]
        for app in apps {
            found[app.name.lowercased()] = InstalledApp(name: app.name, url: URL(fileURLWithPath: "/Applications/\(app.name).app"), bundleID: nil, lastUsed: app.lastUsed)
        }
        self.apps = found
        self.mcpServers = Set(mcpServers.map { $0.lowercased() })
        self.commands = Set(commands)
        refreshedAt = Clock.now
    }

    /// After a pretend setup: the tool is now on the pretend Mac and just used.
    func markInstalled(_ tool: Tool) {
        if let name = tool.detect.appNames?.first {
            apps[name.lowercased()] = InstalledApp(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleID: nil, lastUsed: Clock.now)
        }
        if let server = tool.detect.mcpServers?.first { mcpServers.insert(server.lowercased()) }
        if let command = tool.detect.commands?.first { commands.insert(command) }
    }

    func refresh() {
        guard !isFixture else { return }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]
        var found: [String: InstalledApp] = [:]
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                let key = name.lowercased()
                if found[key] != nil { continue }
                let lastUsed = NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date
                found[key] = InstalledApp(name: name, url: url, bundleID: Bundle(url: url)?.bundleIdentifier, lastUsed: lastUsed)
            }
        }
        apps = found
        mcpServers = Self.readMCPServers(home: home)
        commands = Self.findCommands(["claude", "codex"], home: home)
        refreshedAt = Date()
    }

    func app(named names: [String]?) -> InstalledApp? {
        for name in names ?? [] {
            if let app = apps[name.lowercased()] { return app }
        }
        return nil
    }

    /// Reads only the names of MCP servers from Claude Code's config.
    static func readMCPServers(home: URL) -> Set<String> {
        let url = home.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var names = Set<String>()
        if let top = obj["mcpServers"] as? [String: Any] {
            names.formUnion(top.keys.map { $0.lowercased() })
        }
        if let projects = obj["projects"] as? [String: Any] {
            for case let project as [String: Any] in projects.values {
                if let servers = project["mcpServers"] as? [String: Any] {
                    names.formUnion(servers.keys.map { $0.lowercased() })
                }
            }
        }
        return names
    }

    static func findCommands(_ names: [String], home: URL) -> Set<String> {
        let dirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".claude/local").path,
            home.appendingPathComponent(".npm-global/bin").path,
        ]
        var found = Set<String>()
        for name in names {
            for dir in dirs where FileManager.default.isExecutableFile(atPath: "\(dir)/\(name)") {
                found.insert(name)
                break
            }
        }
        return found
    }
}

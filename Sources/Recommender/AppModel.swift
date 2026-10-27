import AppKit
import EventKit
import SwiftUI

/// Ties the pieces together: sense -> detect a moment -> check the bucket ->
/// decide -> schedule -> show a card -> set up -> walkthrough -> log.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var catalog: Catalog
    @Published private(set) var catalogError: String?
    @Published var prefs: Preferences {
        didSet {
            guard prefs != oldValue else { return }
            store.save(prefs, "preferences.json")
            detector.useModel = prefs.useOnDeviceModel
            refreshStates()
        }
    }
    @Published private(set) var bucketStates: [String: BucketState] = [:]
    @Published var upcoming: [UpcomingItem] = []
    @Published private(set) var activity: [ActivityItem] = []
    @Published private(set) var pending: Suggestion?
    @Published var panel: PanelState?
    @Published private(set) var calendarAccess: CalendarAccess = .notDetermined

    let store: Store
    let inventory = Inventory()
    let log: OutcomeLog
    let detector = MomentDetector()
    let calendar = CalendarSensor()
    let appSensor = ActiveAppSensor()
    let setup = SetupRunner()

    private var runtime: RuntimeState
    private var timers: [Timer] = []
    private var ticking = false
    private var started = false
    private var activations: [String: [Date]] = [:]
    private var pendingNotBefore: Date?
    private(set) var frontmost: String?

    /// Launched for the persona demo: nothing on this Mac is read.
    nonisolated static let personaLaunch = ["--personas", "--persona-test", "--stage", "--stage-test"].contains { CommandLine.arguments.contains($0) }
    /// A persona's pretend Mac is loaded in place of this one.
    @Published private(set) var personaMode = false

    init() {
        let store = Store()
        self.store = store
        self.log = OutcomeLog(url: store.dir.appendingPathComponent("outcomes.jsonl"))
        self.prefs = store.load("preferences.json", as: Preferences.self) ?? Preferences()
        self.runtime = store.load("state.json", as: RuntimeState.self) ?? RuntimeState()
        let (catalog, error) = CatalogLoader.load(cacheDir: store.dir)
        self.catalog = catalog
        self.catalogError = error
        detector.useModel = prefs.useOnDeviceModel
        if !Self.personaLaunch {
            inventory.refresh()
            calendarAccess = calendar.access
        }
        refreshStates()
    }

    // MARK: - Persona demo

    /// Swaps in a persona's pretend Mac: their apps, their settings, an empty
    /// log. The engine and the cards are unchanged.
    func enterPersona(prefs newPrefs: Preferences, apps: [(name: String, lastUsed: Date?)], mcpServers: [String], commands: [String]) {
        personaMode = true
        closePanel()
        pending = nil
        pendingNotBefore = nil
        activity = []
        activations = [:]
        frontmost = nil
        runtime = RuntimeState()
        saveRuntime()
        log.clear()
        inventory.loadFixture(apps: apps, mcpServers: mcpServers, commands: commands)
        calendarAccess = .granted
        prefs = newPrefs
        refreshStates()
    }

    /// Which app is in front. The persona demo uses this to put someone on a call.
    func setFrontmost(_ bundleID: String?) {
        frontmost = bundleID
        showPendingIfCalm()
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        appSensor.onActivate = { [weak self] app in
            Task { @MainActor in self?.appActivated(app) }
        }
        appSensor.start()

        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.inventory.refresh()
                self?.refreshStates()
            }
        })
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: calendar.store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    // MARK: - What the user has

    func usage(of tool: Tool) -> ToolUsage {
        if prefs.selfReported.contains(tool.id) { return .inUse }
        let fresh = prefs.demo.freshMac
        switch tool.kind {
        case .web:
            return .none
        case .feature:
            if let hub = tool.hub, hub == prefs.mainHub { return .owned }
            if !fresh, inventory.app(named: tool.detect.appNames) != nil { return .owned }
            return .none
        case .app:
            if fresh { return .none }
            guard let app = inventory.app(named: tool.detect.appNames) else { return .none }
            if let last = app.lastUsed, last > Clock.now.addingTimeInterval(-30 * 86_400) { return .inUse }
            return .owned
        case .claudeMCP:
            if fresh { return .none }
            let names = Set((tool.detect.mcpServers ?? []).map { $0.lowercased() })
            return inventory.mcpServers.isDisjoint(with: names) ? .none : .inUse
        case .cli:
            if fresh { return .none }
            if (tool.detect.commands ?? []).contains(where: { inventory.commands.contains($0) }) { return .inUse }
            if inventory.app(named: tool.detect.appNames) != nil { return .owned }
            return .none
        }
    }

    var engine: GapEngine {
        GapEngine(catalog: catalog, prefs: prefs, usage: { [unowned self] tool in self.usage(of: tool) })
    }

    func refreshStates() {
        let engine = self.engine
        var states: [String: BucketState] = [:]
        for bucket in catalog.buckets { states[bucket.id] = engine.state(of: bucket) }
        bucketStates = states
    }

    func coverageLine(for bucket: Bucket) -> String {
        switch bucketStates[bucket.id] ?? .empty {
        case .empty: return "Nothing yet"
        case .unused(let ids): return "Not using: \(toolNames(ids))"
        case .inUse(let ids): return toolNames(ids)
        case .notForMe: return "You turned this off"
        }
    }

    func primaryState(for kind: MomentKind?) -> BucketState? {
        guard let kind, let bucket = catalog.buckets(for: kind).first else { return nil }
        return bucketStates[bucket.id]
    }

    func toolNames(_ ids: [String]) -> String {
        let names = ids.compactMap { catalog.tool($0)?.name }
        if names.count <= 2 { return names.joined(separator: " and ") }
        return names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
    }

    func appIcon(for tool: Tool) -> NSImage? {
        guard let app = inventory.app(named: tool.detect.appNames),
              FileManager.default.fileExists(atPath: app.url.path) else { return nil }
        return NSWorkspace.shared.icon(forFile: app.url.path)
    }

    // MARK: - Sensing loop

    func tick() {
        if personaMode {
            showPendingIfCalm()
            return
        }
        calendarAccess = calendar.access
        showPendingIfCalm()
        guard calendarAccess == .granted, prefs.calendarEnabled else {
            upcoming = []
            return
        }
        guard !ticking else { return }
        ticking = true
        let now = Clock.now
        let events = calendar.events(from: now.addingTimeInterval(-5 * 60), to: now.addingTimeInterval(36 * 3600))
        Task { @MainActor in
            defer { self.ticking = false }
            var items: [UpcomingItem] = []
            for event in events.prefix(20) {
                let title = event.title ?? "Untitled event"
                let start = event.startDate ?? now
                let (kind, detectedBy) = await detector.classify(title)
                let id = "cal:\(event.calendarItemIdentifier):\(Int(start.timeIntervalSince1970))"
                items.append(UpcomingItem(id: id, title: title, start: start, kind: kind, detectedBy: detectedBy))
                guard let kind, shouldTrigger(start: start, now: now) else { continue }
                let moment = Moment(id: id, kind: kind, source: .calendar, title: title, startDate: start, detectedBy: detectedBy)
                handle(moment, simulated: false)
            }
            upcoming = items
            pruneRuntime()
        }
    }

    /// Up to 30 minutes before an event, or the evening before a next-day event.
    func shouldTrigger(start: Date, now: Date) -> Bool {
        let lead = start.timeIntervalSince(now)
        if lead > -5 * 60 && lead <= 30 * 60 { return true }
        let hour = Calendar.current.component(.hour, from: now)
        return (17...22).contains(hour) && Timing.isTomorrow(start, now: now)
    }

    func appActivated(_ app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier ?? ""
        frontmost = bundleID
        checkReuse(appName: app.localizedName)
        showPendingIfCalm()
        guard prefs.appSensorEnabled, let kind = AppMoments.map[bundleID] else { return }

        let now = Clock.now
        var recent = (activations[bundleID] ?? []).filter { now.timeIntervalSince($0) < 15 * 60 }
        recent.append(now)
        activations[bundleID] = recent
        guard recent.count >= 3 else { return }

        let name = app.localizedName ?? "this app"
        let day = now.formatted(.iso8601.year().month().day())
        let moment = Moment(
            id: "app:\(kind.rawValue):\(day)",
            kind: kind,
            source: .activeApp,
            title: name,
            startDate: nil,
            detectedBy: .appRules,
            context: "You've switched to \(name) \(recent.count) times in the last 15 minutes."
        )
        handle(moment, simulated: false)
    }

    // MARK: - Deciding and scheduling

    @discardableResult
    func handle(_ moment: Moment, simulated: Bool) -> HandleResult {
        if !simulated {
            if runtime.handled[moment.id] != nil { return .duplicate }
            runtime.handled[moment.id] = Clock.now
            saveRuntime()
        }
        let timing = moment.startDate.map { Timing.phrase(until: $0) } ?? ""
        let title = activityTitle(moment)
        let read = readLine(moment)

        switch engine.decide(for: moment, timing: timing) {
        case .quiet(let reason):
            addActivity(symbol: moment.kind.symbol, title: title, detail: "\(read)Stayed quiet. \(reason)")
            log.append(OutcomeEvent(date: Clock.now, event: "quiet", tool: "", bucket: "", moment: moment.kind.rawValue, source: moment.source.rawValue))
            if simulated {
                panel = .quiet(title: title, reason: reason)
            }
            return .quiet(reason)
        case .suggest(let suggestion):
            let verb = suggestion.kind == .coach ? "Coaching on" : "Suggesting"
            addActivity(symbol: moment.kind.symbol, title: title, detail: "\(read)\(verb) \(suggestion.tool.name).")
            if simulated || canShow() {
                present(suggestion)
                return .shown(suggestion)
            }
            let reason = holdReason()
            pending = suggestion
            pendingNotBefore = nil
            addActivity(symbol: "clock", title: "Holding \(suggestion.tool.name) for later", detail: reason)
            return .held(suggestion, reason)
        }
    }

    var isPaused: Bool {
        if let until = prefs.pausedUntil { return until > Clock.now }
        return false
    }

    var shownToday: Int { log.count("shown", on: Clock.now) }

    func canShow() -> Bool {
        if panel != nil || isPaused { return false }
        if let front = frontmost, AppMoments.callApps.contains(front) { return false }
        if !prefs.demo.ignoreCap && shownToday >= prefs.dailyCap { return false }
        return true
    }

    private func holdReason() -> String {
        if isPaused { return "You paused suggestions." }
        if let front = frontmost, AppMoments.callApps.contains(front) { return "You look like you're on a call." }
        if shownToday >= prefs.dailyCap { return "You've already had today's suggestion." }
        return "Another card is open."
    }

    func showPendingIfCalm() {
        guard let pending, canShow(), Clock.now >= (pendingNotBefore ?? .distantPast) else { return }
        self.pending = nil
        present(pending)
    }

    func present(_ suggestion: Suggestion) {
        setup.reset()
        panel = .card(suggestion)
        record("shown", suggestion)
    }

    // MARK: - Card actions

    func accept(_ s: Suggestion) {
        record(s.kind == .coach ? "coach_opened" : "setup_started", s)
        panel = s.kind == .coach ? .walkthrough(s) : .setup(s)
    }

    func runSetup(_ s: Suggestion) {
        record("setup_run", s)
        setup.run(s.tool, dryRun: prefs.demo.dryRun)
    }

    func finishSetup(_ s: Suggestion) {
        record("setup_done", s)
        if personaMode {
            // On a pretend Mac, setting a tool up means it's now there and in use.
            inventory.markInstalled(s.tool)
            if s.tool.kind == .web { prefs.selfReported.insert(s.tool.id) }
        } else {
            inventory.refresh()
        }
        refreshStates()
        panel = .walkthrough(s)
    }

    func finishWalkthrough(_ s: Suggestion) {
        record("walkthrough_done", s)
        panel = .done(s)
    }

    func later(_ s: Suggestion) {
        record("later", s)
        pending = s
        pendingNotBefore = Clock.now.addingTimeInterval(2 * 3600)
        closePanel()
    }

    func never(_ s: Suggestion) {
        record("never_bucket", s)
        closePanel()
        prefs.notForMe.insert(s.bucket.id)
        addActivity(symbol: "hand.raised", title: "No more \(s.bucket.plural)", detail: "You can turn this back on in Settings.")
    }

    func dismiss() {
        if case .card(let s) = panel { record("dismissed", s) }
        closePanel()
    }

    func closePanel() {
        panel = nil
        setup.reset()
    }

    private func record(_ event: String, _ s: Suggestion) {
        log.append(OutcomeEvent(date: Clock.now, event: event, tool: s.tool.id, bucket: s.bucket.id, moment: s.moment.kind.rawValue, source: s.moment.source.rawValue))
    }

    /// If the user opens a tool within a week of setting it up, note that it stuck.
    private func checkReuse(appName: String?) {
        guard let appName,
              let tool = catalog.tools.first(where: { ($0.detect.appNames ?? []).contains { $0.caseInsensitiveCompare(appName) == .orderedSame } }),
              !runtime.reused.contains(tool.id),
              let done = log.lastDate("setup_done", tool: tool.id) else { return }
        let age = Clock.now.timeIntervalSince(done)
        guard age > 10 * 60, age < 7 * 86_400 else { return }
        runtime.reused.insert(tool.id)
        saveRuntime()
        log.append(OutcomeEvent(date: Clock.now, event: "reused", tool: tool.id, bucket: tool.buckets.first ?? "", moment: "", source: "activeApp"))
        addActivity(symbol: "arrow.uturn.backward", title: "You opened \(tool.name) again", detail: "Noted on this Mac as a sign the suggestion helped.")
    }

    // MARK: - Controls

    func requestCalendar() {
        Task { @MainActor in
            _ = await calendar.requestAccess()
            calendar.store.refreshSourcesIfNecessary()
            calendarAccess = calendar.access
            tick()
        }
    }

    func pause(hours: Double?) {
        if let hours {
            prefs.pausedUntil = Clock.now.addingTimeInterval(hours * 3600)
        } else {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Clock.now))!
            prefs.pausedUntil = tomorrow.addingTimeInterval(8 * 3600)
        }
    }

    func resume() {
        prefs.pausedUntil = nil
        showPendingIfCalm()
    }

    func resetAll() {
        closePanel()
        pending = nil
        activity = []
        runtime = RuntimeState()
        saveRuntime()
        log.clear()
        prefs = Preferences()
    }

    // MARK: - Demo moments

    struct DemoMoment: Identifiable {
        enum When {
            case minutes(Double)
            case tomorrowAt(Int)
            case inDays(Int, hour: Int)
            case app(MomentKind, String)
        }
        let id: String
        let label: String
        let title: String
        let when: When

        var startDate: Date? {
            let cal = Calendar.current
            switch when {
            case .minutes(let m):
                return Clock.now.addingTimeInterval(m * 60)
            case .tomorrowAt(let hour):
                let day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Clock.now))!
                return day.addingTimeInterval(Double(hour) * 3600)
            case .inDays(let days, let hour):
                let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Clock.now))!
                return day.addingTimeInterval(Double(hour) * 3600)
            case .app:
                return nil
            }
        }
    }

    static let demos: [DemoMoment] = [
        DemoMoment(id: "coffee", label: "Coffee chat in 15 min", title: "Coffee chat w/ Priya (Goldman Sachs)", when: .minutes(15)),
        DemoMoment(id: "interview", label: "Mock interview tomorrow", title: "OCS mock interview", when: .tomorrowAt(10)),
        DemoMoment(id: "exam", label: "Midterm in two days", title: "ECON 1150 midterm", when: .inDays(2, hour: 9)),
        DemoMoment(id: "presentation", label: "Group presentation in 25 min", title: "ENAS 3110 team presentation", when: .minutes(25)),
        DemoMoment(id: "deadline", label: "Application due tomorrow", title: "McKinsey BA application due", when: .tomorrowAt(17)),
        DemoMoment(id: "reading", label: "Seminar readings tomorrow", title: "Seminar readings (3 papers)", when: .tomorrowAt(14)),
        DemoMoment(id: "figma", label: "Going back and forth to Figma", title: "Figma", when: .app(.design, "You've switched to Figma 4 times in the last 15 minutes.")),
        DemoMoment(id: "cursor", label: "Coding in Cursor", title: "Cursor", when: .app(.coding, "You've switched to Cursor 3 times in the last 15 minutes.")),
        DemoMoment(id: "dinner", label: "Dinner with friends (should stay quiet)", title: "Dinner with Sam and Alex", when: .minutes(45)),
    ]

    func simulate(_ demo: DemoMoment) {
        let id = "demo:\(demo.id):\(UUID().uuidString)"
        if case .app(let kind, let context) = demo.when {
            handle(Moment(id: id, kind: kind, source: .simulated, title: demo.title, startDate: nil, detectedBy: .appRules, context: context), simulated: true)
            return
        }
        let start = demo.startDate
        Task { @MainActor in
            let (kind, detectedBy) = await detector.classify(demo.title)
            guard let kind else {
                let title = "\u{201C}\(demo.title)\u{201D}"
                let reason = "\(detectedBy.label.capitalizedFirst) read this as a personal event, so there's nothing to suggest."
                addActivity(symbol: "calendar", title: title, detail: "Stayed quiet. \(reason)")
                panel = .quiet(title: title, reason: reason)
                return
            }
            handle(Moment(id: id, kind: kind, source: .simulated, title: demo.title, startDate: start, detectedBy: detectedBy), simulated: true)
        }
    }

    // MARK: - Helpers

    private func activityTitle(_ m: Moment) -> String {
        switch m.source {
        case .activeApp: return m.title
        case .calendar, .simulated:
            return m.startDate == nil ? m.title : "\u{201C}\(m.title)\u{201D}"
        }
    }

    private func readLine(_ m: Moment) -> String {
        guard m.startDate != nil else { return "" }
        return "Read as \(m.kind.withArticle) by \(m.detectedBy.label). "
    }

    func addActivity(symbol: String, title: String, detail: String) {
        activity.insert(ActivityItem(symbol: symbol, title: title, detail: detail), at: 0)
        if activity.count > 20 { activity.removeLast(activity.count - 20) }
    }

    private func saveRuntime() {
        store.save(runtime, "state.json")
    }

    private func pruneRuntime() {
        let cutoff = Clock.now.addingTimeInterval(-7 * 86_400)
        let before = runtime.handled.count
        runtime.handled = runtime.handled.filter { $0.value > cutoff }
        if runtime.handled.count != before { saveRuntime() }
    }
}

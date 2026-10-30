import AppKit
import EventKit
import SwiftUI

/// What happened when the app looked at a window.
enum ScreenOutcome {
    /// It didn't look, and says why.
    case skipped(String)
    /// It kept this label, and maybe found a habit.
    case read(ActivityEntry, HandleResult?)
}

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
            reader.useModel = prefs.useOnDeviceModel
            refreshStates()
            if started { startScreenTimer() }
        }
    }
    @Published private(set) var bucketStates: [String: BucketState] = [:]
    @Published var upcoming: [UpcomingItem] = []
    @Published private(set) var activity: [ActivityItem] = []
    @Published private(set) var pending: Suggestion?
    @Published var panel: PanelState?
    @Published private(set) var calendarAccess: CalendarAccess = .notDetermined
    /// What the outcome log taught it, like which apps to stay quiet in.
    @Published private(set) var learned = Learned()
    /// The last label it kept from a look at a window, for the menu.
    @Published private(set) var lastLook: (date: Date, text: String)?

    let store: Store
    let inventory = Inventory()
    let log: OutcomeLog
    let detector = MomentDetector()
    let calendar = CalendarSensor()
    let appSensor = ActiveAppSensor()
    let setup = SetupRunner()
    let journal: ActivityJournal
    let focus = FocusTracker()
    let reader = ActivityReader()

    private var runtime: RuntimeState
    private var timers: [Timer] = []
    private var ticking = false
    private var started = false
    private var activations: [String: [Date]] = [:]
    private var pendingNotBefore: Date?
    private(set) var frontmost: String?
    private var screenTimer: Timer?
    private var lookTimes: [Date] = []
    private var lastLookAt: [String: Date] = [:]
    private var sensingScreen = false

    /// Launched for the persona demo: nothing on this Mac is read.
    nonisolated static let personaLaunch = ["--personas", "--persona-test", "--stage", "--stage-test"].contains { CommandLine.arguments.contains($0) }
    /// A persona's pretend Mac is loaded in place of this one.
    @Published private(set) var personaMode = false

    init() {
        let store = Store()
        self.store = store
        self.log = OutcomeLog(url: store.dir.appendingPathComponent("outcomes.jsonl"))
        self.journal = ActivityJournal(url: store.dir.appendingPathComponent("journal.jsonl"))
        self.prefs = store.load("preferences.json", as: Preferences.self) ?? Preferences()
        self.runtime = store.load("state.json", as: RuntimeState.self) ?? RuntimeState()
        let (catalog, error) = CatalogLoader.load(cacheDir: store.dir)
        self.catalog = catalog
        self.catalogError = error
        detector.useModel = prefs.useOnDeviceModel
        reader.useModel = prefs.useOnDeviceModel
        if !Self.personaLaunch {
            inventory.refresh()
            calendarAccess = calendar.access
        }
        refreshStates()
        refreshLearned()
    }

    // MARK: - Persona demo

    /// Swaps in a persona's pretend Mac: their apps, their settings, an empty
    /// log. The engine and the cards are unchanged.
    func enterPersona(prefs newPrefs: Preferences, apps: [(name: String, lastUsed: Date?)], mcpServers: [String], commands: [String], history: [OutcomeEvent] = []) {
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
        log.seed(history)
        journal.clear()
        focus.clear()
        lookTimes = []
        lastLookAt = [:]
        lastLook = nil
        inventory.loadFixture(apps: apps, mcpServers: mcpServers, commands: commands)
        calendarAccess = .granted
        prefs = newPrefs
        refreshStates()
        refreshLearned()
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
        timers.append(Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.journal.prune()
                self?.refreshLearned()
            }
        })
        startScreenTimer()
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
        GapEngine(catalog: catalog, prefs: prefs, usage: { [unowned self] tool in self.usage(of: tool) }, learned: learned, newToolAllowed: newToolAllowed)
    }

    /// The one-new-app-a-week budget. The demo's "ignore the limit" lifts it too.
    var newToolAllowed: Bool {
        if prefs.newToolsPerWeek <= 0 || prefs.demo.ignoreCap { return true }
        return log.newToolsShown(since: Clock.now.addingTimeInterval(-7 * 86_400)) < prefs.newToolsPerWeek
    }

    func refreshLearned() {
        // Only events after the last reset count.
        let start = log.events.lastIndex { $0.event == "learning_reset" }.map { $0 + 1 } ?? 0
        learned = Learned.from(Array(log.events[start...]), now: Clock.now) { [unowned self] id in self.appName(for: id) }
    }

    /// A readable name for a bundle ID, for "Cards wait while you're in Word".
    func appName(for bundleID: String) -> String {
        if let app = inventory.apps.values.first(where: { $0.bundleID == bundleID }) { return app.name.replacingOccurrences(of: "Microsoft ", with: "") }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Microsoft ", with: "")
        }
        if let known = NeverRead.apps.first(where: { $0.id == bundleID }) { return known.name }
        let names = ["com.microsoft.Word": "Word", "com.apple.iWork.Pages": "Pages", "com.figma.Desktop": "Figma", "com.apple.iWork.Keynote": "Keynote", "com.microsoft.Powerpoint": "PowerPoint"]
        return names[bundleID] ?? bundleID
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
        if prefs.behaviorOn {
            let title = prefs.windowTitlesEnabled && ScreenPermissions.accessibility ? (WindowTitles.front(pid: app.processIdentifier) ?? "") : ""
            noteFocus(bundleID: bundleID, app: app.localizedName ?? bundleID, title: title)
        }
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
        if let front = frontmost, isNeverRead(front) { return false }
        if let front = frontmost, learned.holdApps[front] != nil { return false }
        if !prefs.demo.ignoreCap && shownToday >= prefs.dailyCap { return false }
        return true
    }

    private func holdReason() -> String {
        if isPaused { return "You paused suggestions." }
        if let front = frontmost, AppMoments.callApps.contains(front) { return "You look like you're on a call." }
        if let front = frontmost, isNeverRead(front) { return "\(appName(for: front)) is on your never-read list, so nothing pops up there." }
        if let front = frontmost, let count = learned.holdApps[front] {
            return "You put off or closed \(count) cards while you were in \(appName(for: front)), so this one waits until you switch apps."
        }
        if shownToday >= prefs.dailyCap { return prefs.dailyCap == 1 ? "You've already had today's suggestion." : "You've already had today's \(prefs.dailyCap) suggestions." }
        return "Another card is open."
    }

    func isNeverRead(_ bundleID: String) -> Bool {
        prefs.neverRead.contains(bundleID) || NeverRead.apps.contains { $0.id == bundleID }
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
        switch s.kind {
        case .coach:
            record("coach_opened", s)
            panel = .walkthrough(s)
        case .tip:
            record("tip_opened", s)
            panel = .walkthrough(s)
        case .setUp:
            record("setup_started", s)
            panel = .setup(s)
        }
    }

    /// Puts a tip's prompt on the clipboard, ready to paste.
    func copyPrompt(_ s: Suggestion) {
        guard let prompt = s.prompt else { return }
        if !personaMode {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
        }
        record("prompt_copied", s)
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
        if let workflow = s.workflow {
            record("never_workflow", s)
            closePanel()
            prefs.notForMeWorkflows.insert(workflow.id)
            addActivity(symbol: "hand.raised", title: "No more \u{201C}\(workflow.name)\u{201D}", detail: "You can turn this back on in Settings.")
            return
        }
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
        log.append(OutcomeEvent(date: Clock.now, event: event, tool: s.tool.id, bucket: s.bucket.id, moment: s.moment.kind.rawValue, source: s.moment.source.rawValue, app: frontmost, kind: s.kind.rawValue, workflow: s.workflow?.id))
        refreshLearned()
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
        journal.clear()
        focus.clear()
        lastLook = nil
        prefs = Preferences()
        refreshLearned()
    }

    /// Forget what it learned. The log keeps its history, but nothing before this counts.
    func resetLearning() {
        log.append(OutcomeEvent(date: Clock.now, event: "learning_reset", tool: "", bucket: "", moment: "", source: ""))
        refreshLearned()
        showPendingIfCalm()
    }

    func clearJournal() {
        journal.clear()
        lastLook = nil
    }

    // MARK: - Screen and habits

    static let lookAfter: TimeInterval = 60
    static let lookEvery: TimeInterval = 5 * 60
    static let looksPerHour = 12

    func startScreenTimer() {
        let want = prefs.behaviorOn && !personaMode && !Self.personaLaunch
        if want, screenTimer == nil {
            screenTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.senseScreen() }
            }
        } else if !want {
            screenTimer?.invalidate()
            screenTimer = nil
        }
    }

    /// Every few seconds while screen reading is on: note the window in front,
    /// and take a look at it once the student has stayed in it a while.
    func senseScreen() async {
        guard !sensingScreen, !personaMode, prefs.behaviorOn, !isPaused,
              let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return }
        sensingScreen = true
        defer { sensingScreen = false }
        let name = app.localizedName ?? bundleID
        let title = prefs.windowTitlesEnabled && ScreenPermissions.accessibility ? (WindowTitles.front(pid: app.processIdentifier) ?? "") : ""
        noteFocus(bundleID: bundleID, app: name, title: title)

        let canRead = ScreenPermissions.accessibility
        let canCapture = ScreenPermissions.screen
        guard prefs.screenLooksEnabled, canRead || canCapture else { return }
        let now = Clock.now
        let windowKey = bundleID + "|" + title
        lookTimes.removeAll { now.timeIntervalSince($0) > 3600 }
        guard focus.dwell(now: now) >= Self.lookAfter,
              now.timeIntervalSince(lastLookAt[windowKey] ?? .distantPast) >= Self.lookEvery,
              lookTimes.count < Self.looksPerHour else { return }
        // Nothing is read while a password field has the keyboard, or in a never-read window.
        if ScreenPermissions.secureInput { return }
        if canRead && WindowText.focusedIsSecure(pid: app.processIdentifier) { return }
        if NeverRead.reason(bundleID: bundleID, app: name, title: title, extra: prefs.neverRead) != nil { return }
        lastLookAt[windowKey] = now
        lookTimes.append(now)
        // The window's own text first. A picture only when the app keeps its text to itself.
        let text = canRead ? WindowText.front(pid: app.processIdentifier) : []
        if text.joined().count >= 200 || !canCapture {
            await lookAt(image: nil, text: text, app: name, bundleID: bundleID, title: title, dwell: focus.dwell(now: now))
        } else {
            let image = try? await WindowCapture.frontWindow(pid: app.processIdentifier)
            await lookAt(image: image, app: name, bundleID: bundleID, title: title, dwell: focus.dwell(now: now))
        }
    }

    /// Remembers which window is in front. When it changes, checks for habits
    /// that show up in switching, like pasting between an AI chat and a doc.
    func noteFocus(bundleID: String, app: String, title: String, at date: Date = Clock.now) {
        let changed = focus.current.map { $0.bundleID != bundleID || $0.title != title } ?? true
        focus.record(bundleID: bundleID, app: app, title: title, at: date)
        guard changed, prefs.behaviorOn else { return }
        if NeverRead.reason(bundleID: bundleID, app: app, title: title, extra: prefs.neverRead) != nil { return }
        checkSwitchingHabits()
    }

    /// Habits that show up in switching, like pasting between an AI chat and a doc.
    @discardableResult
    func checkSwitchingHabits() -> HandleResult? {
        guard prefs.behaviorOn else { return nil }
        let detector = HabitDetector(focus: focus, journal: journal.entries, upcoming: upcoming, now: Clock.now)
        guard let match = detector.aiDocShuttle() else { return nil }
        return handleHabit(match, how: prefs.windowTitlesEnabled ? "From your window titles, read on this Mac." : "From which apps you switched between, on this Mac.")
    }

    /// Reads one window: checks it isn't off limits, reads the text in the
    /// picture, keeps a short label and looks for a habit. The picture and its
    /// text are dropped when this returns. Nothing is written but the label.
    @discardableResult
    func lookAt(image: CGImage?, text: [String] = [], app: String, bundleID: String?, title: String, dwell: TimeInterval) async -> ScreenOutcome {
        if let reason = NeverRead.reason(bundleID: bundleID, app: app, title: title, extra: prefs.neverRead) {
            addActivity(symbol: "eye.slash", title: "Didn't look at \(app)", detail: "Nothing was read because \(reason).")
            return .skipped(reason)
        }
        var lines = text
        if let image { lines = await TextReader.lines(in: image) }
        let read = await reader.read(app: app, bundleID: bundleID, title: title, lines: lines)
        lines.removeAll()
        let entry = ActivityEntry(date: Clock.now, app: app, bundleID: bundleID, kind: read.kind, label: read.label(app: app), topic: read.topic, organization: read.organization, careerRelated: read.careerRelated, cues: read.cues, source: image == nil && text.isEmpty ? "title" : "look", readBy: read.readBy)
        let detector = HabitDetector(focus: focus, journal: journal.entries, upcoming: upcoming, now: Clock.now)
        journal.append(entry)
        let kept = Redact.clean(entry.label)
        lastLook = (Clock.now, kept)
        addActivity(symbol: "eye", title: "Looked at \(app)", detail: "Kept \u{201C}\(kept)\u{201D}. The picture and its text are gone.")
        guard let match = detector.match(entry, dwell: dwell) else {
            showPendingIfCalm()
            return .read(entry, nil)
        }
        let how: String
        if image != nil {
            how = "From a look at this window, read on this Mac. Only a short label was kept."
        } else if !text.isEmpty {
            how = "From the text in this window, read on this Mac. Only a short label was kept."
        } else {
            how = "From your window title, read on this Mac."
        }
        return .read(entry, handleHabit(match, how: how))
    }

    @discardableResult
    func handleHabit(_ match: HabitMatch, how: String) -> HandleResult {
        if runtime.handled[match.key] != nil { return .duplicate }
        runtime.handled[match.key] = Clock.now
        saveRuntime()
        let moment = Moment(id: match.key, kind: match.habit.momentKind, source: .screen, title: match.noticed, startDate: nil, detectedBy: .habitRules, context: match.noticed)
        switch engine.decide(habit: match, moment: moment, how: how) {
        case .quiet(let reason):
            addActivity(symbol: "lightbulb", title: "Noticed a habit", detail: "\(match.noticed) Stayed quiet. \(reason)")
            log.append(OutcomeEvent(date: Clock.now, event: "quiet", tool: "", bucket: "", moment: moment.kind.rawValue, source: "screen", app: frontmost))
            return .quiet(reason)
        case .suggest(let s):
            let what = s.kind == .tip ? "a tip for \(s.tool.name)" : s.tool.name
            addActivity(symbol: "lightbulb", title: "Noticed a habit", detail: "\(match.noticed) Suggesting \(what).")
            if canShow() {
                present(s)
                return .shown(s)
            }
            let reason = holdReason()
            pending = s
            pendingNotBefore = nil
            addActivity(symbol: "clock", title: "Holding \(what) for later", detail: reason)
            return .held(s, reason)
        }
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
        case .activeApp, .screen: return m.title
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

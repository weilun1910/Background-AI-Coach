import AppKit
import SwiftUI

// MARK: - Persona data

struct PersonaFile: Codable {
    var note: String?
    var personas: [Persona]
}

struct Persona: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var tagline: String
    var about: String
    var shows: String
    var color: String
    var prefs: PersonaPrefs
    var apps: [PersonaApp]
    var mcpServers: [String]?
    var commands: [String]?
    /// Things that happened in the weeks before the demo day, so the day can
    /// show what the app learned from them.
    var history: [PersonaHistory]?
    var steps: [PersonaStep]

    static func == (a: Persona, b: Persona) -> Bool { a.id == b.id }
}

struct PersonaPrefs: Codable {
    var mainHub: String
    var freeOnly: Bool
    var selfReported: [String]
    var notForMe: [String]
    var dailyCap: Int
    var careers: [String]?
    var recruitingNow: Bool?
    var windowTitles: Bool?
    var screenLooks: Bool?
    /// Leave out for the original five days, which ran without a weekly limit.
    var newToolsPerWeek: Int?
}

struct PersonaHistory: Codable {
    var daysAgo: Int
    var event: String
    var tool: String
    var workflow: String?
    var kind: String?
    /// The app in front, by bundle ID.
    var app: String?
}

struct PersonaApp: Codable, Hashable {
    var name: String
    var daysSinceUsed: Int?
}

enum PersonaStepType: String, Codable {
    case calendar, appSwitch, callStart, callEnd, nextMorning
    /// Something on screen: switching windows, and maybe a look at the front one.
    case screen
}

/// What the presenter is meant to click on the card. The headless run clicks it.
enum PresenterClick: String, Codable {
    case setUp, notForMe, later, close
}

struct PersonaStep: Codable {
    var at: String
    var day: Int?
    var type: PersonaStepType
    var title: String?
    var startsAt: String?
    var startsDay: Int?
    var bundleID: String?
    var moment: MomentKind?
    var switches: Int?
    var click: PresenterClick?
    /// For screen steps: take a look at the front window.
    var glimpse: Bool?
    /// For screen steps: minutes the front window has been in front.
    var dwell: Int?
    var narration: String
    /// Windows on the pretend desktop for the full-screen demo, back to front.
    var scene: [SceneWindowSpec]?
}

enum OutcomeTone {
    case card, held, quiet, info
}

struct StepOutcome {
    var text: String
    var tone: OutcomeTone
}

// MARK: - Demo controller

/// Plays a persona's day through the real app, one moment per click.
/// The pretend Mac replaces this one, and the clock jumps to each moment.
@MainActor
final class PersonaDemo: ObservableObject {
    static let shared = PersonaDemo()

    let personas: [Persona]
    let loadError: String?
    let model = AppModel.shared

    @Published private(set) var persona: Persona?
    @Published private(set) var nextIndex = 0
    @Published private(set) var outcomes: [Int: StepOutcome] = [:]
    @Published private(set) var running = false

    /// Midnight of the pretend day. Every step's time is counted from here.
    private var dayStart = Calendar.current.startOfDay(for: Date())
    private var upcomingGeneration = 0
    /// The latest Coming up refresh, so the stage test can wait for it before rendering.
    private(set) var upcomingTask: Task<Void, Never>?

    init() {
        var loaded: [Persona] = []
        var problem: String?
        if let url = Bundle.main.url(forResource: "personas", withExtension: "json") {
            do {
                loaded = try JSONDecoder().decode(PersonaFile.self, from: Data(contentsOf: url)).personas
            } catch {
                problem = "Couldn't read personas.json: \(error)"
            }
        } else {
            problem = "personas.json isn't in the app bundle."
        }
        personas = loaded
        loadError = problem
    }

    var isFinished: Bool {
        guard let persona else { return true }
        return nextIndex >= persona.steps.count
    }

    var lastPlayed: (PersonaStep, StepOutcome)? {
        guard let persona, nextIndex > 0, let outcome = outcomes[nextIndex - 1] else { return nil }
        return (persona.steps[nextIndex - 1], outcome)
    }

    func select(_ persona: Persona) {
        self.persona = persona
        nextIndex = 0
        outcomes = [:]
        dayStart = Calendar.current.startOfDay(for: Date())
        if let first = persona.steps.first {
            Clock.set(date(day: first.day ?? 0, time: first.at).addingTimeInterval(-60))
        }

        var prefs = Preferences()
        prefs.onboarded = true
        prefs.mainHub = persona.prefs.mainHub
        prefs.freeOnly = persona.prefs.freeOnly
        prefs.selfReported = Set(persona.prefs.selfReported)
        prefs.notForMe = Set(persona.prefs.notForMe)
        prefs.dailyCap = persona.prefs.dailyCap
        prefs.careers = persona.prefs.careers ?? []
        prefs.recruitingNow = persona.prefs.recruitingNow ?? false
        prefs.windowTitlesEnabled = persona.prefs.windowTitles ?? false
        prefs.screenLooksEnabled = persona.prefs.screenLooks ?? false
        prefs.newToolsPerWeek = persona.prefs.newToolsPerWeek ?? 0
        prefs.demo = DemoSettings(freshMac: false, dryRun: true, ignoreCap: false)

        let apps = persona.apps.map { app in
            (name: app.name, lastUsed: app.daysSinceUsed.map { Clock.now.addingTimeInterval(-Double($0) * 86_400) })
        }
        let history = (persona.history ?? []).map { h in
            OutcomeEvent(date: Clock.now.addingTimeInterval(-Double(h.daysAgo) * 86_400), event: h.event, tool: h.tool, bucket: "", moment: "", source: "history", app: h.app, kind: h.kind, workflow: h.workflow)
        }
        model.enterPersona(prefs: prefs, apps: apps, mcpServers: persona.mcpServers ?? [], commands: persona.commands ?? [], history: history)
        // Clear the last persona's events now; reading the new titles takes a moment.
        model.upcoming = []
        refreshUpcoming()
    }

    func restart() {
        if let persona { select(persona) }
    }

    func next() async {
        guard let persona, nextIndex < persona.steps.count, !running else { return }
        running = true
        defer { running = false }
        // The presenter moved on without clicking the card.
        if model.panel != nil { model.dismiss() }

        let index = nextIndex
        let step = persona.steps[index]
        Clock.set(date(day: step.day ?? 0, time: step.at))
        let outcome = await play(step, index: index, persona: persona)
        outcomes[index] = outcome
        nextIndex = index + 1
        refreshUpcoming()
    }

    private func play(_ step: PersonaStep, index: Int, persona: Persona) async -> StepOutcome {
        let id = "persona:\(persona.id):\(index)"
        switch step.type {
        case .calendar:
            let title = step.title ?? "Untitled event"
            let start = date(day: step.startsDay ?? step.day ?? 0, time: step.startsAt ?? step.at)
            let (kind, detectedBy) = await model.detector.classify(title)
            guard let kind else {
                model.addActivity(symbol: "calendar", title: "\u{201C}\(title)\u{201D}", detail: "Read by \(detectedBy.label) as personal. Stayed quiet.")
                return StepOutcome(text: "Quiet. \(detectedBy.label.capitalizedFirst) read it as personal.", tone: .quiet)
            }
            let moment = Moment(id: id, kind: kind, source: .calendar, title: title, startDate: start, detectedBy: detectedBy)
            return describe(model.handle(moment, simulated: false), readAs: "Read as \(kind.withArticle). ")

        case .appSwitch:
            let name = step.title ?? "an app"
            model.setFrontmost(step.bundleID)
            let moment = Moment(
                id: id,
                kind: step.moment ?? .design,
                source: .activeApp,
                title: name,
                startDate: nil,
                detectedBy: .appRules,
                context: "You've switched to \(name) \(step.switches ?? 3) times in the last 15 minutes."
            )
            return describe(model.handle(moment, simulated: false))

        case .callStart:
            model.setFrontmost(step.bundleID ?? "us.zoom.xos")
            model.addActivity(symbol: "video", title: step.title ?? "On a call", detail: "Cards wait until the call ends.")
            return StepOutcome(text: "On a call. Cards wait until it ends.", tone: .info)

        case .callEnd:
            model.setFrontmost(nil)
            if case .card(let s) = model.panel {
                return StepOutcome(text: "Call ended. Showed the waiting \(s.tool.name) card.", tone: .card)
            }
            return StepOutcome(text: "Call ended. Nothing was waiting.", tone: .info)

        case .nextMorning:
            model.tick()
            if case .card(let s) = model.panel {
                return StepOutcome(text: "New day. Showed the waiting \(s.tool.name) card.", tone: .card)
            }
            return StepOutcome(text: "New day. Nothing was waiting.", tone: .info)

        case .screen:
            let windows = step.scene?.map(StageDirector.window) ?? []
            recordSwitching(step, windows: windows)
            return describeScreen(await playScreen(step, windows: windows))
        }
    }

    // MARK: Screen steps

    /// What a screen step did: a card (or not), or a look that was skipped.
    enum ScreenStepResult {
        case handled(HandleResult)
        case skipped(String)
        case nothing(String?)
    }

    /// The front window's app: its name and bundle ID.
    func frontApp(_ step: PersonaStep, windows: [StageWindow]) -> (key: String, name: String, bundleID: String) {
        let key = windows.last?.app ?? "finder"
        let info = StageApps.info(key)
        return (key, info.name, step.bundleID ?? info.bundleIDs.first ?? key)
    }

    /// Puts the switching between the last two windows into the app's focus
    /// history, spread over the last few minutes. Ends on the front window.
    func recordSwitching(_ step: PersonaStep, windows: [StageWindow]) {
        let now = Clock.now
        let front = frontApp(step, windows: windows)
        let dwell = Double(step.dwell ?? 2) * 60
        let switches = step.switches ?? 0
        guard switches > 0, windows.count >= 2 else {
            model.focus.record(bundleID: front.bundleID, app: front.name, title: windowTitle(windows.last), at: now.addingTimeInterval(-dwell))
            return
        }
        let other = windows[windows.count - 2]
        let otherInfo = StageApps.info(other.app)
        let otherID = otherInfo.bundleIDs.first ?? other.app
        model.focus.record(bundleID: front.bundleID, app: front.name, title: windowTitle(windows.last), at: now.addingTimeInterval(-Double(switches + 1) * 120))
        for i in 0..<switches {
            let onOther = i % 2 == 0
            let at = now.addingTimeInterval(-Double(switches - i) * 120 + (i == switches - 1 ? 0 : 0))
            if onOther {
                model.focus.record(bundleID: otherID, app: otherInfo.name, title: windowTitle(other), at: at)
            } else {
                model.focus.record(bundleID: front.bundleID, app: front.name, title: windowTitle(windows.last), at: at)
            }
        }
        if model.focus.current?.bundleID != front.bundleID {
            model.focus.record(bundleID: front.bundleID, app: front.name, title: windowTitle(windows.last), at: now)
        }
    }

    private func windowTitle(_ window: StageWindow?) -> String {
        guard let window else { return "" }
        return window.title
    }

    /// Plays a screen step through the real app: the switching habit check,
    /// then a look at the front window, read by the real text recognition
    /// and Apple's model from a picture of the pretend window.
    func playScreen(_ step: PersonaStep, windows: [StageWindow]) async -> ScreenStepResult {
        // Habits like coffee chat prep read the calendar, so let it finish loading.
        await upcomingTask?.value
        let front = frontApp(step, windows: windows)
        let hadCard = model.panel != nil
        model.setFrontmost(front.bundleID)
        if !hadCard, case .card(let s) = model.panel {
            return .handled(.shown(s))
        }
        // The look comes first, so a habit found in switching can use what it saw.
        var kept: String?
        if step.glimpse == true, let window = windows.last {
            let title = windowTitle(window)
            if let reason = NeverRead.reason(bundleID: front.bundleID, app: front.name, title: title, extra: model.prefs.neverRead) {
                // Off limits: no picture is even taken.
                model.addActivity(symbol: "eye.slash", title: "Didn't look at \(front.name)", detail: "Nothing was read because \(reason).")
                return .skipped(reason)
            }
            let image = Snapshots.image(StageWindowView(window: window, director: StageDirector.shared), width: window.frame.width, height: window.frame.height)
            switch await model.lookAt(image: image, app: front.name, bundleID: front.bundleID, title: title, dwell: Double(step.dwell ?? 2) * 60) {
            case .skipped(let reason):
                return .skipped(reason)
            case .read(let entry, let result):
                if let result, !isDuplicate(result) { return .handled(result) }
                kept = entry.label
            }
        }
        if (step.switches ?? 0) > 0, let result = model.checkSwitchingHabits(), !isDuplicate(result) {
            return .handled(result)
        }
        return .nothing(kept)
    }

    private func isDuplicate(_ result: HandleResult) -> Bool {
        if case .duplicate = result { return true }
        return false
    }

    private func describeScreen(_ result: ScreenStepResult) -> StepOutcome {
        switch result {
        case .handled(let r):
            if case .shown(let s) = r, s.kind == .tip {
                return StepOutcome(text: "Tip: \(s.workflow?.name ?? s.tool.name) in \(s.tool.name).", tone: .card)
            }
            if case .held(let s, let reason) = r, s.kind == .tip {
                return StepOutcome(text: "Held a tip. \(reason)", tone: .held)
            }
            return describe(r)
        case .skipped(let reason):
            return StepOutcome(text: "Didn't look. \(reason.capitalizedFirst).", tone: .quiet)
        case .nothing(let label):
            return StepOutcome(text: label.map { "Kept \u{201C}\($0)\u{201D}. No habit, so quiet." } ?? "Nothing to do.", tone: .quiet)
        }
    }

    private func describe(_ result: HandleResult, readAs: String = "") -> StepOutcome {
        switch result {
        case .shown(let s):
            return StepOutcome(text: readAs + (s.kind == .coach ? "Coached on \(s.tool.name)." : "Suggested \(s.tool.name)."), tone: .card)
        case .held(let s, let reason):
            return StepOutcome(text: readAs + "Held \(s.tool.name). \(reason)", tone: .held)
        case .quiet(let reason):
            return StepOutcome(text: readAs + "Quiet. \(reason)", tone: .quiet)
        case .duplicate:
            return StepOutcome(text: "Already handled.", tone: .info)
        }
    }

    // MARK: Time

    func date(day: Int, time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let base = Calendar.current.date(byAdding: .day, value: day, to: dayStart) ?? dayStart
        let hour = parts.first ?? 9
        let minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    func timeLabel(_ step: PersonaStep) -> String {
        let d = date(day: step.day ?? 0, time: step.at)
        let time = d.formatted(date: .omitted, time: .shortened)
        return (step.day ?? 0) == 0 ? time : d.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

    func stepLabel(_ step: PersonaStep) -> String {
        switch step.type {
        case .calendar:
            let start = date(day: step.startsDay ?? step.day ?? 0, time: step.startsAt ?? step.at)
            return "\u{201C}\(step.title ?? "")\u{201D} at \(Timing.short(start, now: date(day: step.day ?? 0, time: step.at)))"
        case .appSwitch:
            return "Switches to \(step.title ?? "an app") \(step.switches ?? 3) times"
        case .callStart:
            return "Joins \(step.title ?? "a call")"
        case .callEnd:
            return "The call ends"
        case .nextMorning:
            return "Next morning"
        case .screen:
            let app = step.scene?.last.map { StageApps.info($0.app).name } ?? "an app"
            if let switches = step.switches, switches > 0 { return "Goes back and forth to \(app) \(switches) times" }
            return step.glimpse == true ? "Working in \(app)" : "Switches to \(app)"
        }
    }

    var clockLabel: String {
        Clock.now.formatted(.dateTime.weekday(.wide).hour().minute())
    }

    /// The menu bar's "Coming up" shows the persona's remaining events.
    func refreshUpcoming(from start: Int? = nil) {
        guard let persona else {
            model.upcoming = []
            return
        }
        let first = start ?? nextIndex
        let remaining = persona.steps.enumerated().filter { $0.offset > first - 1 && $0.element.type == .calendar }
        upcomingGeneration += 1
        let generation = upcomingGeneration
        upcomingTask = Task { @MainActor in
            var items: [UpcomingItem] = []
            for (index, step) in remaining {
                let title = step.title ?? ""
                let start = date(day: step.startsDay ?? step.day ?? 0, time: step.startsAt ?? step.at)
                let (kind, detectedBy) = await model.detector.classify(title)
                items.append(UpcomingItem(id: "persona-\(index)", title: title, start: start, kind: kind, detectedBy: detectedBy))
            }
            // A newer refresh started while this one was reading titles.
            guard generation == upcomingGeneration else { return }
            model.upcoming = items
        }
    }

    // MARK: Headless run

    /// Plays every persona's day, clicking what the presenter is meant to click,
    /// and prints each outcome. Optionally renders the screens to PNG.
    func runHeadless(renderTo dir: URL?) async {
        if let loadError { print(loadError) }
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        for persona in personas {
            select(persona)
            print("\n\(persona.name): \(persona.tagline)")
            print("  Coverage: " + model.catalog.buckets.map { "\($0.name) \(SelfTest.describe(model.bucketStates[$0.id] ?? .empty))" }.joined(separator: ", "))
            while !isFinished {
                let index = nextIndex
                let step = persona.steps[index]
                await next()
                print("  \(timeLabel(step))  \(stepLabel(step))")
                print("      -> \(outcomes[index]?.text ?? "?")")
                if let dir, model.panel != nil {
                    Snapshots.render(PanelView(model: model), width: 380, to: dir.appendingPathComponent("\(persona.id)-\(index)-card.png"))
                }
                if index == 0, let dir {
                    Snapshots.render(PersonaDemoView(demo: self, model: model), width: PersonaDemoView.width, height: PersonaDemoView.height, to: dir.appendingPathComponent("\(persona.id)-window-start.png"))
                }
                await click(step.click)
            }
            if let dir {
                Snapshots.render(PersonaDemoView(demo: self, model: model), width: PersonaDemoView.width, height: PersonaDemoView.height, to: dir.appendingPathComponent("\(persona.id)-window-end.png"))
                Snapshots.render(MenuContentView(model: model), width: 360, to: dir.appendingPathComponent("\(persona.id)-menu.png"))
            }
        }
    }

    private func click(_ click: PresenterClick?) async {
        guard case .card(let s) = model.panel else { return }
        switch click {
        case .setUp:
            model.accept(s)
            if s.kind == .tip { model.copyPrompt(s) }
            if s.kind == .setUp {
                model.runSetup(s)
                try? await Task.sleep(for: .seconds(1.4))
                model.finishSetup(s)
            }
            model.finishWalkthrough(s)
            model.closePanel()
        case .notForMe:
            model.never(s)
        case .later:
            model.later(s)
        case .close, .none:
            model.dismiss()
        }
    }
}

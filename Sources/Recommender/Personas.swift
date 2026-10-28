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
    var steps: [PersonaStep]

    static func == (a: Persona, b: Persona) -> Bool { a.id == b.id }
}

struct PersonaPrefs: Codable {
    var mainHub: String
    var freeOnly: Bool
    var selfReported: [String]
    var notForMe: [String]
    var dailyCap: Int
}

struct PersonaApp: Codable, Hashable {
    var name: String
    var daysSinceUsed: Int?
}

enum PersonaStepType: String, Codable {
    case calendar, appSwitch, callStart, callEnd, nextMorning
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
        prefs.demo = DemoSettings(freshMac: false, dryRun: true, ignoreCap: false)

        let apps = persona.apps.map { app in
            (name: app.name, lastUsed: app.daysSinceUsed.map { Clock.now.addingTimeInterval(-Double($0) * 86_400) })
        }
        model.enterPersona(prefs: prefs, apps: apps, mcpServers: persona.mcpServers ?? [], commands: persona.commands ?? [])
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

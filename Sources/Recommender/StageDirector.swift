import AppKit
import SwiftUI

// MARK: - Stage data

/// One window in a persona's scene, as written in personas.json.
struct SceneWindowSpec: Codable, Hashable {
    var app: String
    var title: String?
    var detail: String?
    var flag: String?
}

/// A window on the pretend desktop. One window per app.
struct StageWindow: Identifiable, Equatable {
    var app: String
    var title: String
    var detail: String?
    var flag: String?

    var id: String { app }
    var frame: CGRect { StageApps.frame(app) }
}

/// A macOS-style notification banner.
struct StageNote: Equatable {
    var app: String
    var title: String
    var body: String
}

enum StageOverlay: Equatable {
    case intro
    case transition(String)
    case end
}

/// Where the pretend cursor points: a fixed spot, or a named control.
enum CursorSpot: Equatable {
    case point(CGPoint)
    case target(String)
}

/// One press of the right arrow.
struct Beat {
    let label: String
    let run: @MainActor (StageDirector) async -> Void
}

// MARK: - Director

/// Plays a persona's day on the pretend desktop, one beat per key press.
/// The real engine decides what happens; the director only stages it.
@MainActor
final class StageDirector: ObservableObject {
    static let shared = StageDirector()
    static let canvas = CGSize(width: 1440, height: 900)
    static let restPoint = CGPoint(x: 1150, y: 660)

    let demo = PersonaDemo.shared
    var model: AppModel { demo.model }

    @Published private(set) var personaIndex = 0
    @Published var windows: [StageWindow] = []
    @Published var note: StageNote?
    @Published var cursor: CursorSpot = .point(StageDirector.restPoint)
    @Published var cursorPressed = false
    @Published var menuOpen = false
    @Published var overlay: StageOverlay? = .intro
    @Published var captionsOn = true
    @Published var hintsOn = true
    @Published var caption: String?
    @Published var dockAdded: [String] = []
    @Published var bouncing: String?
    @Published private(set) var beatIndex = 0
    @Published private(set) var busy = false
    @Published private(set) var results: [StepOutcome] = []

    private var queue: [Beat] = []
    private(set) var animated = true

    var persona: Persona? { demo.persona }
    var beatCount: Int { queue.count }
    var atEnd: Bool { beatIndex >= queue.count }
    var currentBeatLabel: String { beatIndex < queue.count ? queue[beatIndex].label : "" }

    /// Testing aid: plays every beat instantly, without animation.
    func setInstant(_ on: Bool) { animated = !on }

    // MARK: Loading and moving

    func load(_ index: Int) {
        guard demo.personas.indices.contains(index) else { return }
        personaIndex = index
        demo.select(demo.personas[index])
        note = nil
        menuOpen = false
        caption = nil
        dockAdded = []
        bouncing = nil
        cursor = .point(Self.restPoint)
        cursorPressed = false
        results = []
        windows = persona?.steps.first?.scene?.map(Self.window) ?? []
        overlay = .intro
        buildQueue()
        beatIndex = 0
    }

    func next() async {
        guard !busy, beatIndex < queue.count else { return }
        busy = true
        await queue[beatIndex].run(self)
        beatIndex += 1
        busy = false
    }

    /// Going back replays the day from the start, instantly, up to one beat earlier.
    func back() async {
        guard !busy, beatIndex > 0 else { return }
        await replay(to: beatIndex - 1)
    }

    func replay(to target: Int) async {
        busy = true
        animated = false
        load(personaIndex)
        while beatIndex < target, beatIndex < queue.count {
            await queue[beatIndex].run(self)
            beatIndex += 1
        }
        animated = true
        busy = false
    }

    private func buildQueue() {
        queue = []
        guard let persona else { return }
        for (index, step) in persona.steps.enumerated() {
            queue += beats(for: step, index: index)
        }
        queue.append(Beat(label: "end") { d in
            withAnimation(d.anim(.easeInOut(duration: 0.4))) {
                d.menuOpen = false
                d.overlay = .end
            }
        })
    }

    private func insertNext(_ beats: [Beat]) {
        queue.insert(contentsOf: beats, at: min(beatIndex + 1, queue.count))
    }

    // MARK: Beats for each kind of moment

    private func beats(for step: PersonaStep, index: Int) -> [Beat] {
        switch step.type {
        case .calendar:
            return [
                Beat(label: "scene") { d in await d.setScene(step, index) },
                Beat(label: "notification") { d in d.notify(step) },
                Beat(label: "react") { d in await d.reactToEvent(step, index) },
            ]
        case .appSwitch:
            return [
                Beat(label: "scene") { d in await d.setScene(step, index) },
                Beat(label: "switching") { d in await d.switchApps(step) },
                Beat(label: "react") { d in await d.reactToSwitching(step, index) },
            ]
        case .callStart:
            return [
                Beat(label: "scene") { d in await d.setScene(step, index) },
                Beat(label: "call") { d in d.startCall(step) },
            ]
        case .callEnd:
            return [Beat(label: "leave call") { d in await d.endCall(step, index) }]
        case .nextMorning:
            return [Beat(label: "next morning") { d in await d.nextMorning(step, index) }]
        }
    }

    private func setScene(_ step: PersonaStep, _ index: Int) async {
        Clock.set(demo.date(day: step.day ?? 0, time: step.at))
        demo.refreshUpcoming(from: index)
        withAnimation(anim(.spring(response: 0.5, dampingFraction: 0.86))) {
            overlay = nil
            note = nil
            menuOpen = false
            caption = nil
            if let scene = step.scene { windows = scene.map(Self.window) }
        }
        await moveCursor(to: Self.restPoint)
    }

    private func notify(_ step: PersonaStep) {
        let start = startDate(step)
        var body = Timing.phrase(until: start)
        if body.hasPrefix("is ") { body.removeFirst(3) }
        withAnimation(anim(.spring(response: 0.45, dampingFraction: 0.8))) {
            note = StageNote(app: "calendar", title: step.title ?? "Event", body: body.capitalizedFirst)
        }
    }

    private func reactToEvent(_ step: PersonaStep, _ index: Int) async {
        guard let persona else { return }
        let title = step.title ?? "Untitled event"
        let (kind, detectedBy) = await model.detector.classify(title)
        withAnimation(anim(.easeOut(duration: 0.25))) { note = nil }
        await wait(0.3)
        guard let kind else {
            model.addActivity(symbol: "calendar", title: "\u{201C}\(title)\u{201D}", detail: "Read by \(detectedBy.label) as personal. Stayed quiet.")
            results.append(StepOutcome(text: "Quiet: personal", tone: .quiet))
            caption = step.narration
            insertNext(peekBeats())
            return
        }
        let moment = Moment(id: "stage:\(persona.id):\(index)", kind: kind, source: .calendar, title: title, startDate: startDate(step), detectedBy: detectedBy)
        let result = withAnimation(anim(.spring(response: 0.5, dampingFraction: 0.82))) {
            model.handle(moment, simulated: false)
        }
        caption = step.narration
        followUp(result, step)
    }

    private func switchApps(_ step: PersonaStep) async {
        guard windows.count >= 2, let target = windows.last?.app else { return }
        let other = windows[windows.count - 2].app
        let switches = max(2, step.switches ?? 3)
        for i in 0..<switches {
            let app = i % 2 == 0 ? other : target
            await moveCursor(to: "dock-\(app)")
            await click()
            withAnimation(anim(.easeInOut(duration: 0.25))) { bringToFront(app) }
            await wait(0.35)
        }
        if windows.last?.app != target {
            await moveCursor(to: "dock-\(target)")
            await click()
            withAnimation(anim(.easeInOut(duration: 0.25))) { bringToFront(target) }
        }
        model.setFrontmost(step.bundleID)
        await moveCursor(to: Self.restPoint)
    }

    private func reactToSwitching(_ step: PersonaStep, _ index: Int) async {
        guard let persona else { return }
        let name = step.title ?? "an app"
        let moment = Moment(
            id: "stage:\(persona.id):\(index)",
            kind: step.moment ?? .design,
            source: .activeApp,
            title: name,
            startDate: nil,
            detectedBy: .appRules,
            context: "You've switched to \(name) \(step.switches ?? 3) times in the last 15 minutes."
        )
        let result = withAnimation(anim(.spring(response: 0.5, dampingFraction: 0.82))) {
            model.handle(moment, simulated: false)
        }
        caption = step.narration
        followUp(result, step)
    }

    private func startCall(_ step: PersonaStep) {
        model.setFrontmost(step.bundleID ?? "us.zoom.xos")
        model.addActivity(symbol: "video", title: step.title ?? "On a call", detail: "Cards wait until the call ends.")
        withAnimation(anim(.spring(response: 0.5, dampingFraction: 0.85))) {
            windows.removeAll { $0.app == "zoom" }
            windows.append(StageWindow(app: "zoom", title: step.title ?? "Zoom Meeting", detail: "Sam,Priya,Jordan"))
        }
        caption = step.narration
        results.append(StepOutcome(text: "On a call", tone: .info))
    }

    private func endCall(_ step: PersonaStep, _ index: Int) async {
        Clock.set(demo.date(day: step.day ?? 0, time: step.at))
        demo.refreshUpcoming(from: index)
        caption = nil
        await moveCursor(to: "zoom-leave")
        await click()
        withAnimation(anim(.easeInOut(duration: 0.3))) { windows.removeAll { $0.app == "zoom" } }
        await wait(0.5)
        let hadCard = model.panel != nil
        withAnimation(anim(.spring(response: 0.5, dampingFraction: 0.82))) { model.setFrontmost(nil) }
        caption = step.narration
        if !hadCard, case .card(let s) = model.panel {
            results.append(StepOutcome(text: "Showed the waiting card", tone: .card))
            insertNext(clickBeats(s, step.click))
        } else {
            results.append(StepOutcome(text: "Nothing was waiting", tone: .info))
        }
        await moveCursor(to: Self.restPoint)
    }

    private func nextMorning(_ step: PersonaStep, _ index: Int) async {
        withAnimation(anim(.easeInOut(duration: 0.5))) {
            overlay = .transition("Next morning")
            note = nil
            menuOpen = false
            caption = nil
        }
        await wait(1.2)
        Clock.set(demo.date(day: step.day ?? 1, time: step.at))
        demo.refreshUpcoming(from: index)
        windows = step.scene?.map(Self.window) ?? []
        withAnimation(anim(.easeInOut(duration: 0.5))) { overlay = nil }
        await wait(0.7)
        withAnimation(anim(.spring(response: 0.5, dampingFraction: 0.82))) { model.tick() }
        caption = step.narration
        if case .card(let s) = model.panel {
            results.append(StepOutcome(text: "Showed the waiting card", tone: .card))
            insertNext(clickBeats(s, step.click))
        } else {
            results.append(StepOutcome(text: "Nothing was waiting", tone: .info))
        }
    }

    // MARK: Follow-up beats

    private func followUp(_ result: HandleResult, _ step: PersonaStep) {
        switch result {
        case .shown(let s):
            results.append(StepOutcome(text: s.kind == .coach ? "Coached" : "Suggested", tone: .card))
            insertNext(clickBeats(s, step.click))
        case .held:
            results.append(StepOutcome(text: "Held", tone: .held))
            insertNext(peekBeats())
        case .quiet:
            results.append(StepOutcome(text: "Quiet", tone: .quiet))
            insertNext(peekBeats())
        case .duplicate:
            break
        }
    }

    /// The cursor clicks what the presenter is meant to click on the card.
    private func clickBeats(_ s: Suggestion, _ click: PresenterClick?) -> [Beat] {
        switch click ?? .close {
        case .setUp where s.kind == .setUp:
            return [
                Beat(label: "click Set it up") { d in await d.press("card-primary") { d.model.accept(s) } },
                Beat(label: "run setup") { d in
                    await d.press("setup-run") { d.model.runSetup(s) }
                    await d.wait(1.5)
                },
                Beat(label: "finish setup") { d in await d.press("setup-done") { d.model.finishSetup(s) } },
                Beat(label: "got it") { d in await d.press("walkthrough-done") { d.model.finishWalkthrough(s) } },
                Beat(label: "open the tool") { d in await d.openTool(s) },
            ]
        case .setUp:
            return [
                Beat(label: "click Show me how") { d in await d.press("card-primary") { d.model.accept(s) } },
                Beat(label: "got it") { d in await d.press("walkthrough-done") { d.model.finishWalkthrough(s) } },
                Beat(label: "open the tool") { d in await d.openTool(s) },
            ]
        case .notForMe:
            return [Beat(label: "click Not for me") { d in
                await d.press("card-notforme") { d.model.never(s) }
                await d.moveCursor(to: Self.restPoint)
            }]
        case .later:
            return [Beat(label: "click Later") { d in
                await d.press("card-later") { d.model.later(s) }
                await d.moveCursor(to: Self.restPoint)
            }]
        case .close:
            return [Beat(label: "close the card") { d in
                await d.press("panel-close") { d.model.dismiss() }
                await d.moveCursor(to: Self.restPoint)
            }]
        }
    }

    /// For quiet and held moments: open the real menu to show what it noticed.
    private func peekBeats() -> [Beat] {
        [
            Beat(label: "open the menu") { d in
                await d.moveCursor(to: "menubar-sparkle")
                await d.click()
                withAnimation(d.anim(.easeOut(duration: 0.18))) { d.menuOpen = true }
            },
            Beat(label: "close the menu") { d in
                withAnimation(d.anim(.easeIn(duration: 0.15))) { d.menuOpen = false }
                await d.moveCursor(to: Self.restPoint)
            },
        ]
    }

    private func openTool(_ s: Suggestion) async {
        await press("done-close") { model.closePanel() }
        let window = Self.toolWindow(for: s)
        if !dockKeys.contains(window.app) { dockAdded.append(window.app) }
        await moveCursor(to: "dock-\(window.app)")
        await click()
        withAnimation(anim(.interpolatingSpring(stiffness: 300, damping: 12))) { bouncing = window.app }
        await wait(0.45)
        withAnimation(anim(.spring(response: 0.5, dampingFraction: 0.86))) {
            bouncing = nil
            windows.removeAll { $0.app == window.app }
            windows.append(window)
        }
        await moveCursor(to: Self.restPoint)
    }

    // MARK: Cursor

    func moveCursor(to target: String) async {
        withAnimation(anim(.easeInOut(duration: 0.55))) { cursor = .target(target) }
        await wait(0.6)
    }

    func moveCursor(to point: CGPoint) async {
        withAnimation(anim(.easeInOut(duration: 0.5))) { cursor = .point(point) }
        await wait(0.3)
    }

    func click() async {
        withAnimation(anim(.easeOut(duration: 0.08))) { cursorPressed = true }
        await wait(0.12)
        withAnimation(anim(.easeOut(duration: 0.12))) { cursorPressed = false }
        await wait(0.08)
    }

    func press(_ target: String, _ action: () -> Void) async {
        await moveCursor(to: target)
        await click()
        withAnimation(anim(.spring(response: 0.42, dampingFraction: 0.86))) { action() }
        await wait(0.2)
    }

    // MARK: Helpers

    func anim(_ animation: Animation) -> Animation? { animated ? animation : nil }

    func wait(_ seconds: Double) async {
        guard animated else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func bringToFront(_ app: String) {
        guard let i = windows.firstIndex(where: { $0.app == app }) else { return }
        let w = windows.remove(at: i)
        windows.append(w)
    }

    private func startDate(_ step: PersonaStep) -> Date {
        demo.date(day: step.startsDay ?? step.day ?? 0, time: step.startsAt ?? step.at)
    }

    var frontAppName: String {
        guard let app = windows.last?.app else { return "Finder" }
        return StageApps.info(app).name
    }

    /// Dock: Finder, the persona's apps, Calendar and Safari, then anything set up today.
    var dockKeys: [String] {
        var keys = ["finder"]
        for app in persona?.apps ?? [] {
            if let key = StageApps.key(forPersonaApp: app.name) { keys.append(key) }
        }
        keys += ["calendar", "safari"]
        keys += windows.map(\.app)
        keys += dockAdded
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    /// Calendar events for the pretend day the clock is on.
    func calendarEvents() -> [(title: String, start: Date, minutes: Int)] {
        guard let persona else { return [] }
        var events: [(String, Date, Int)] = []
        for step in persona.steps {
            switch step.type {
            case .calendar:
                let title = step.title ?? ""
                let due = title.lowercased().contains("due")
                events.append((title, startDate(step), due ? 30 : 45))
            case .callStart:
                events.append((step.title ?? "Call", demo.date(day: step.day ?? 0, time: step.at), 30))
            default:
                break
            }
        }
        return events.filter { Calendar.current.isDate($0.1, inSameDayAs: Clock.now) }.map { (title: $0.0, start: $0.1, minutes: $0.2) }
    }

    static func window(_ spec: SceneWindowSpec) -> StageWindow {
        StageWindow(app: spec.app, title: spec.title ?? StageApps.info(spec.app).name, detail: spec.detail, flag: spec.flag)
    }

    /// What opens on the desktop once a suggestion is set up or coached.
    static func toolWindow(for s: Suggestion) -> StageWindow {
        switch s.tool.id {
        case "granola":
            return StageWindow(app: "granola", title: "Granola", detail: s.moment.title, flag: "live")
        case "chatgpt-mock-interview":
            return StageWindow(app: "chatgpt", title: "ChatGPT", detail: "Interview me for my OCS mock interview, one question at a time. Push back when I'm vague.", flag: "voice")
        case "chatgpt-study-mode", "chatgpt-projects", "chatgpt-app":
            return StageWindow(app: "chatgpt", title: "ChatGPT", detail: "Quiz me on this, one question at a time, and give hints instead of answers.", flag: nil)
        case "claude-projects":
            return StageWindow(app: "claude", title: "Claude", detail: "What's the main argument of each reading, in two sentences? Quote the passage you're relying on.", flag: "project:ARCH 2810 Seminar")
        case "claude-mock-interview", "claude-learning-mode", "claude-app":
            return StageWindow(app: "claude", title: "Claude", detail: "Here's my draft. Which sentences could be in anyone's cover letter? Don't rewrite them.", flag: nil)
        case "gemini-guided-learning", "gemini-deep-research", "gemini-live-interview":
            return StageWindow(app: "gemini", title: "Gemini", detail: "Quiz me on the PSYC 2300 midterm topics, one question at a time.", flag: "guided")
        case "figma-make":
            return StageWindow(app: "figma", title: "Studio review boards", detail: nil, flag: "make")
        case "cursor":
            return StageWindow(app: "cursor", title: "analysis.py", detail: nil, flag: "agent")
        case "grammarly":
            return StageWindow(app: "word", title: "Cover letter - Jane Street.docx", detail: "coverJaneStreet", flag: "grammarly")
        case "notebooklm":
            return StageWindow(app: "safari", title: "Gemini Notebook", detail: "notebook", flag: nil)
        default:
            return StageWindow(app: "safari", title: s.tool.name, detail: "site:\(s.tool.id)", flag: nil)
        }
    }
}

// MARK: - App registry

struct StageAppInfo {
    let name: String
    let bundleIDs: [String]
    let symbol: String
    let tint: Color
}

@MainActor
enum StageApps {
    private static var iconCache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func info(_ key: String) -> StageAppInfo {
        switch key {
        case "finder": return StageAppInfo(name: "Finder", bundleIDs: ["com.apple.finder"], symbol: "face.smiling", tint: .blue)
        case "calendar": return StageAppInfo(name: "Calendar", bundleIDs: ["com.apple.iCal"], symbol: "calendar", tint: .red)
        case "safari": return StageAppInfo(name: "Safari", bundleIDs: ["com.apple.Safari"], symbol: "safari", tint: .blue)
        case "word": return StageAppInfo(name: "Microsoft Word", bundleIDs: ["com.microsoft.Word"], symbol: "doc.text", tint: Color(red: 0.16, green: 0.34, blue: 0.64))
        case "powerpoint": return StageAppInfo(name: "Microsoft PowerPoint", bundleIDs: ["com.microsoft.Powerpoint"], symbol: "rectangle.on.rectangle", tint: Color(red: 0.77, green: 0.29, blue: 0.17))
        case "keynote": return StageAppInfo(name: "Keynote", bundleIDs: ["com.apple.iWork.Keynote"], symbol: "play.rectangle", tint: .blue)
        case "zoom": return StageAppInfo(name: "zoom.us", bundleIDs: ["us.zoom.xos"], symbol: "video.fill", tint: Color(red: 0.05, green: 0.45, blue: 0.95))
        case "figma": return StageAppInfo(name: "Figma", bundleIDs: ["com.figma.Desktop"], symbol: "paintpalette", tint: .black)
        case "vscode": return StageAppInfo(name: "Code", bundleIDs: ["com.microsoft.VSCode"], symbol: "chevron.left.forwardslash.chevron.right", tint: Color(red: 0.0, green: 0.48, blue: 0.8))
        case "cursor": return StageAppInfo(name: "Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"], symbol: "cursorarrow.rays", tint: .black)
        case "granola": return StageAppInfo(name: "Granola", bundleIDs: ["com.granola.app"], symbol: "waveform", tint: Color(red: 0.36, green: 0.55, blue: 0.2))
        case "chatgpt": return StageAppInfo(name: "ChatGPT", bundleIDs: ["com.openai.codex", "com.openai.chat"], symbol: "bubble.left.and.text.bubble.right", tint: .black)
        case "claude": return StageAppInfo(name: "Claude", bundleIDs: ["com.anthropic.claudefordesktop"], symbol: "asterisk", tint: Color(red: 0.85, green: 0.47, blue: 0.34))
        case "gemini": return StageAppInfo(name: "Gemini", bundleIDs: ["com.google.GeminiMacOS"], symbol: "sparkle", tint: Color(red: 0.26, green: 0.45, blue: 0.95))
        case "grammarly": return StageAppInfo(name: "Grammarly", bundleIDs: [], symbol: "checkmark.circle.fill", tint: Color(red: 0.08, green: 0.6, blue: 0.45))
        case "notion": return StageAppInfo(name: "Notion", bundleIDs: ["notion.id"], symbol: "n.square", tint: .black)
        default: return StageAppInfo(name: key, bundleIDs: [], symbol: "app", tint: .gray)
        }
    }

    static func key(forPersonaApp name: String) -> String? {
        switch name {
        case "ChatGPT", "ChatGPT Classic": return "chatgpt"
        case "Claude": return "claude"
        case "Gemini": return "gemini"
        case "Microsoft Word": return "word"
        case "Microsoft PowerPoint": return "powerpoint"
        case "Keynote": return "keynote"
        case "zoom.us": return "zoom"
        case "Figma": return "figma"
        case "Visual Studio Code": return "vscode"
        case "Cursor": return "cursor"
        case "Granola": return "granola"
        case "Grammarly Desktop": return "grammarly"
        case "Notion": return "notion"
        default: return nil
        }
    }

    /// The real app icon when this Mac has the app. Only the icon is read.
    static func icon(_ key: String) -> NSImage? {
        if let cached = iconCache[key] { return cached }
        if missing.contains(key) { return nil }
        for id in info(key).bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let image = NSWorkspace.shared.icon(forFile: url.path)
                iconCache[key] = image
                return image
            }
        }
        missing.insert(key)
        return nil
    }

    nonisolated static func frame(_ key: String) -> CGRect {
        switch key {
        case "calendar": return CGRect(x: 80, y: 62, width: 760, height: 610)
        case "word": return CGRect(x: 250, y: 48, width: 800, height: 710)
        case "powerpoint", "keynote": return CGRect(x: 180, y: 54, width: 930, height: 650)
        case "zoom": return CGRect(x: 140, y: 46, width: 1080, height: 720)
        case "figma": return CGRect(x: 100, y: 44, width: 1060, height: 730)
        case "vscode", "cursor": return CGRect(x: 120, y: 54, width: 1010, height: 690)
        case "safari": return CGRect(x: 300, y: 66, width: 890, height: 680)
        case "granola": return CGRect(x: 300, y: 84, width: 780, height: 620)
        case "chatgpt", "claude", "gemini": return CGRect(x: 230, y: 62, width: 840, height: 670)
        default: return CGRect(x: 200, y: 80, width: 800, height: 600)
        }
    }
}

// MARK: - Window and keys

final class StageNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows the stage full screen and maps keys to the director.
@MainActor
final class StageController {
    static let shared = StageController()
    private var window: StageNSWindow?
    private var monitor: Any?
    private(set) var fullScreen = true

    func show() {
        let director = StageDirector.shared
        let w = StageNSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentViewController = NSHostingController(rootView: StageView(director: director, model: director.model))
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.collectionBehavior = [.fullScreenAuxiliary]
        window = w
        setFullScreen(true)
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    func setFullScreen(_ on: Bool) {
        guard let w = window, let screen = NSScreen.main else { return }
        fullScreen = on
        if on {
            w.styleMask = [.borderless]
            w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            w.setFrame(screen.frame, display: true)
        } else {
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.title = "Persona demo (press Esc for full screen)"
            w.level = .normal
            let visible = screen.visibleFrame
            let width = min(1152, visible.width - 80)
            let height = width * 900 / 1440 + 28
            w.setFrame(NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height), display: true)
        }
        w.makeKeyAndOrderFront(nil)
    }

    private func handle(_ event: NSEvent) -> Bool {
        let director = StageDirector.shared
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "q" {
            NSApp.terminate(nil)
            return true
        }
        switch event.keyCode {
        case 124, 49:
            Task { @MainActor in await director.next() }
            return true
        case 123:
            Task { @MainActor in await director.back() }
            return true
        case 53:
            setFullScreen(!fullScreen)
            return true
        default:
            break
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "1", "2", "3", "4", "5":
            if let n = Int(key), !director.busy { director.load(n - 1) }
        case "n":
            director.captionsOn.toggle()
        case "h":
            director.hintsOn.toggle()
        case "r":
            if !director.busy { director.load(director.personaIndex) }
        case "f":
            setFullScreen(!fullScreen)
        default:
            return false
        }
        return true
    }
}

import AppKit
import Combine
import SwiftUI

@main
struct RecommenderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarIcon(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarIcon: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.isPaused {
            Image(systemName: "pause.circle")
        } else if model.pending != nil {
            Image(systemName: "sparkles")
        } else {
            Image(systemName: "sparkle")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshots.renderAll(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
            return
        }
        if args.contains("--selftest") {
            Task { @MainActor in
                await SelfTest.run()
                NSApp.terminate(nil)
            }
            return
        }
        if args.contains("--persona-test") {
            let dir = args.firstIndex(of: "--render").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil }
            Task { @MainActor in
                await PersonaDemo.shared.runHeadless(renderTo: dir)
                NSApp.terminate(nil)
            }
            return
        }
        if args.contains("--stage-test") {
            let dir = args.firstIndex(of: "--render").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil }
            let clean = args.contains("--clean")
            Task { @MainActor in
                await StageTest.run(renderTo: dir, clean: clean)
                NSApp.terminate(nil)
            }
            return
        }
        if args.contains("--stage") {
            // The full-screen pretend Mac. The floating card isn't used; the
            // same card is drawn inside the stage instead.
            StageDirector.shared.load(0)
            StageController.shared.show()
            return
        }
        if args.contains("--personas") {
            let model = AppModel.shared
            WindowManager.shared.bind(model)
            let demo = PersonaDemo.shared
            if let first = demo.personas.first { demo.select(first) }
            WindowManager.shared.showPersonaDemo(demo, model: model)
            return
        }

        let model = AppModel.shared
        model.start()
        WindowManager.shared.bind(model)
        if !model.prefs.onboarded {
            WindowManager.shared.showOnboarding(model)
        }
        if let i = args.firstIndex(of: "--simulate"), i + 1 < args.count,
           let demo = AppModel.demos.first(where: { $0.id == args[i + 1] }) {
            model.simulate(demo)
            if args.contains("--autoplay") { Self.autoplay(model) }
        }
    }

    /// Testing aid: steps the card through setup, walkthrough and done every
    /// 3 seconds, so the panel's resizing can be checked without clicking.
    @MainActor
    static func autoplay(_ model: AppModel) {
        let steps: [(AppModel) -> Void] = [
            { m in if case .card(let s) = m.panel { m.accept(s) } },
            { m in if case .setup(let s) = m.panel { m.runSetup(s) } },
            { m in if case .setup(let s) = m.panel { m.finishSetup(s) } },
            { m in if case .walkthrough(let s) = m.panel { m.finishWalkthrough(s) } },
            { m in m.closePanel() },
        ]
        for (i, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i + 1) * 3) {
                step(model)
                print("autoplay step \(i + 1): \(String(describing: model.panel).prefix(40))")
                fflush(stdout)
            }
        }
    }
}

// MARK: - Windows

/// A panel that can take clicks without pulling focus from what you're doing.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var panel: FloatingPanel?
    private var onboarding: NSWindow?
    private var settings: NSWindow?
    private var personaWindow: NSWindow?
    private var bag = Set<AnyCancellable>()

    func bind(_ model: AppModel) {
        model.$panel
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                if state == nil { self?.hidePanel() } else { self?.showPanel(model) }
            }
            .store(in: &bag)
    }

    func showPanel(_ model: AppModel) {
        if panel == nil {
            let p = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingController(rootView: PanelView(model: model))
            host.sizingOptions = [.preferredContentSize]
            p.contentViewController = host
            NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: p, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.positionPanel() }
            }
            panel = p
        }
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    private func positionPanel() {
        guard let p = panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = p.frame.size
        p.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 12))
    }

    func showOnboarding(_ model: AppModel) {
        if onboarding == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: OnboardingView(model: model, close: { [weak self] in
                self?.onboarding?.close()
            }))
            w.center()
            onboarding = w
        }
        NSApp.activate()
        onboarding?.makeKeyAndOrderFront(nil)
    }

    /// The presenter's window sits on the left, so it never covers the card
    /// in the top-right corner.
    func showPersonaDemo(_ demo: PersonaDemo, model: AppModel) {
        if personaWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: PersonaDemoView.width, height: PersonaDemoView.height),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Background AI Coach: Persona demo"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: PersonaDemoView(demo: demo, model: model))
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                let height = min(PersonaDemoView.height, visible.height - 40)
                w.setFrame(NSRect(x: visible.minX + 40, y: visible.maxY - height - 20, width: PersonaDemoView.width, height: height), display: false)
            }
            personaWindow = w
        }
        NSApp.activate()
        personaWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings(_ model: AppModel) {
        if settings == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Background AI Coach Settings"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            w.center()
            settings = w
        }
        NSApp.activate()
        settings?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Snapshots

/// `--snapshot <folder>` renders every screen to PNG files, so the UI can be
/// checked without clicking through it. Run with RECOMMENDER_DATA_DIR set to
/// a scratch folder so real preferences aren't touched.
@MainActor
enum Snapshots {
    static func renderAll(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel.shared
        let catalog = model.catalog

        func suggestion(_ toolID: String, _ bucketID: String, _ kind: MomentKind, _ title: String, minutes: Double?, as type: SuggestionKind, context: String? = nil) -> Suggestion? {
            guard let tool = catalog.tool(toolID), let bucket = catalog.bucket(bucketID) else { return nil }
            let start = minutes.map { Date().addingTimeInterval($0 * 60) }
            let moment = Moment(id: "snap", kind: kind, source: start == nil ? .activeApp : .calendar, title: title, startDate: start, detectedBy: start == nil ? .appRules : .onDeviceModel, context: context)
            let headline = GapEngine.headline(moment, timing: start.map { Timing.phrase(until: $0) } ?? "")
            let detail = type == .coach ? (tool.coachLine ?? "") : bucket.gapLine
            return Suggestion(moment: moment, bucket: bucket, tool: tool, kind: type, headline: headline, detail: detail)
        }

        var states: [(String, PanelState)] = []
        if let s = suggestion("granola", "meeting-notes", .networking, "Coffee chat w/ Priya (Goldman Sachs)", minutes: 15, as: .setUp) {
            states += [("card", .card(s)), ("setup", .setup(s)), ("walkthrough", .walkthrough(s)), ("done", .done(s))]
        }
        if let s = suggestion("chatgpt-study-mode", "study", .exam, "ECON 1150 midterm", minutes: 2 * 24 * 60, as: .coach) {
            states.append(("coach", .card(s)))
        }
        if let s = suggestion("figma-mcp", "design-ai", .design, "Figma", minutes: nil, as: .setUp, context: "You've switched to Figma 4 times in the last 15 minutes.") {
            states.append(("figma-setup", .setup(s)))
        }
        states.append(("quiet", .quiet(title: "\u{201C}Coffee chat w/ Priya (Goldman Sachs)\u{201D}", reason: "You already use Granola for this.")))

        for (name, state) in states {
            model.panel = state
            render(PanelView(model: model), width: 380, to: dir.appendingPathComponent("panel-\(name).png"))
            render(PanelView(model: model), width: 380, dark: true, to: dir.appendingPathComponent("panel-\(name)-dark.png"))
        }
        model.panel = nil

        model.addActivity(symbol: "cup.and.saucer", title: "\u{201C}Coffee chat w/ Priya\u{201D}", detail: "Read as a coffee chat by Apple's on-device model. Suggesting Granola.")
        model.addActivity(symbol: "checklist", title: "\u{201C}ECON 1150 midterm\u{201D}", detail: "Read as an exam by Apple's on-device model. Stayed quiet. You already use Gemini Notebook for this.")
        render(MenuContentView(model: model), width: 360, to: dir.appendingPathComponent("menu.png"))
        render(MenuContentView(model: model), width: 360, dark: true, to: dir.appendingPathComponent("menu-dark.png"))
        render(SettingsView(model: model), width: 520, height: 1900, to: dir.appendingPathComponent("settings.png"))
        for page in 0..<OnboardingView.pageCount {
            render(OnboardingView(model: model, startPage: page, close: {}), width: 580, height: 600, to: dir.appendingPathComponent("onboarding-\(page).png"))
        }
    }

    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, dark: Bool = false, to url: URL) {
        let root = view
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: height == nil)
            .background(Color(nsColor: .underPageBackgroundColor))
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height ?? 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        let size = height.map { NSSize(width: width, height: $0) } ?? host.fittingSize
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}

import AppKit

/// `--selftest` prints what the app sees on this Mac and what it would decide
/// for each demo moment, without showing any windows. It changes demo
/// settings while it runs, so it only runs against a scratch data folder.
@MainActor
enum SelfTest {
    static let extraTitles = [
        "Lunch w/ mom",
        "PLSC 2500 section",
        "Superday - Evercore",
        "Bain case interview prep",
        "Team sync - YUCG",
        "Gym",
        "Flight to SFO",
        "Office hours with Prof. Zhang",
        "Goldman summer analyst app due",
        "Read ch. 4-6 for ENGL seminar",
        "Coffee w/ Yale alum at BCG",
        "Pitch practice for hackathon",
    ]

    static func run() async {
        guard ProcessInfo.processInfo.environment["RECOMMENDER_DATA_DIR"] != nil else {
            print("Set RECOMMENDER_DATA_DIR to a scratch folder before running --selftest.")
            return
        }
        let model = AppModel.shared
        print("Catalog: \(model.catalog.version), \(model.catalog.buckets.count) buckets, \(model.catalog.tools.count) tools")
        if let error = model.catalogError { print("Catalog error: \(error)") }
        print("Detector: \(model.detector.statusText)")
        print("Inventory: \(model.inventory.apps.count) apps, MCP servers \(model.inventory.mcpServers.sorted()), commands \(model.inventory.commands.sorted())")

        print("\nBucket states on this Mac:")
        for bucket in model.catalog.buckets {
            print("  \(bucket.name): \(describe(model.bucketStates[bucket.id] ?? .empty)) (\(model.coverageLine(for: bucket)))")
        }

        print("\nReading event titles:")
        let titles = AppModel.demos.compactMap { $0.startDate == nil ? nil : $0.title } + extraTitles
        var mismatches = 0
        for title in titles {
            let start = Date()
            let (kind, by) = await model.detector.classify(title)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let rules = MomentDetector.rules(title)
            if rules != kind { mismatches += 1 }
            print("  \(title) -> \(kind?.rawValue ?? "none") [\(by.rawValue), \(ms) ms] rules said \(rules?.rawValue ?? "none")")
        }
        print("  Model and rules disagreed on \(mismatches) of \(titles.count).")

        for fresh in [false, true] {
            model.prefs.demo.freshMac = fresh
            print("\nDecisions \(fresh ? "pretending this is a fresh Mac" : "with this Mac's real apps"):")
            for demo in AppModel.demos {
                let moment: Moment
                if case .app(let kind, let context) = demo.when {
                    moment = Moment(id: "t", kind: kind, source: .simulated, title: demo.title, startDate: nil, detectedBy: .appRules, context: context)
                } else {
                    let (kind, by) = await model.detector.classify(demo.title)
                    guard let kind else {
                        print("  \(demo.label): quiet, not a work moment")
                        continue
                    }
                    moment = Moment(id: "t", kind: kind, source: .simulated, title: demo.title, startDate: demo.startDate, detectedBy: by)
                }
                let timing = moment.startDate.map { Timing.phrase(until: $0) } ?? ""
                switch model.engine.decide(for: moment, timing: timing) {
                case .suggest(let s):
                    print("  \(demo.label): \(s.kind == .coach ? "coach on" : "set up") \(s.tool.name) [\(s.bucket.id)]")
                    print("    \(s.headline) \(s.detail)")
                case .quiet(let reason):
                    print("  \(demo.label): quiet. \(reason)")
                }
            }
        }
        model.prefs.demo.freshMac = false
        await flowTest(model)
    }

    /// Clicks through the card flow in code and checks each state.
    static func flowTest(_ model: AppModel) async {
        print("\nFlow test:")
        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            print("  \(ok ? "pass" : "FAIL"): \(label)")
            if !ok { failures += 1 }
        }

        model.prefs.demo = DemoSettings(freshMac: true, dryRun: true, ignoreCap: true)
        model.prefs.notForMe = []
        model.prefs.pausedUntil = nil
        model.closePanel()

        let coffee = Moment(id: "flow:coffee", kind: .networking, source: .calendar, title: "Coffee chat w/ Priya", startDate: Date().addingTimeInterval(900), detectedBy: .onDeviceModel)
        model.handle(coffee, simulated: false)
        guard case .card(let s) = model.panel else {
            check(false, "a calendar moment with a gap shows a card")
            return
        }
        check(s.tool.id == "granola", "the card suggests Granola (got \(s.tool.id))")
        model.handle(coffee, simulated: false)
        check(model.log.events.filter { $0.event == "shown" && $0.tool == "granola" }.count == 1, "the same calendar event isn't handled twice")

        model.accept(s)
        check(model.panel == .setup(s), "Set it up opens guided setup")
        model.runSetup(s)
        try? await Task.sleep(for: .seconds(1.6))
        check(model.setup.succeeded == true, "a dry-run install finishes without installing anything")
        check(model.setup.output.contains("brew install --cask granola"), "setup shows the Homebrew command it would run")
        model.finishSetup(s)
        check(model.panel == .walkthrough(s), "finishing setup opens the walkthrough")
        model.finishWalkthrough(s)
        check(model.panel == .done(s), "Got it shows the done card")
        model.closePanel()
        check(model.panel == nil, "Close hides the panel")

        let events = model.log.events.map(\.event)
        for expected in ["shown", "setup_started", "setup_run", "setup_done", "walkthrough_done"] {
            check(events.contains(expected), "outcome log has \(expected)")
        }

        // Not for me turns the bucket off, and the next moment stays quiet.
        let pitch = Moment(id: "flow:pitch", kind: .presentation, source: .simulated, title: "Pitch practice", startDate: Date().addingTimeInterval(1500), detectedBy: .onDeviceModel)
        model.handle(pitch, simulated: true)
        if case .card(let p) = model.panel {
            model.never(p)
            check(model.prefs.notForMe.contains("slides"), "Not for me turns off slide tools")
        } else {
            check(false, "a presentation moment shows a card")
        }
        model.handle(pitch, simulated: true)
        if case .quiet = model.panel { check(true, "after Not for me, the same moment stays quiet") } else { check(false, "after Not for me, the same moment stays quiet") }
        model.closePanel()

        // The daily limit holds a suggestion instead of showing it.
        model.prefs.demo.ignoreCap = false
        let exam = Moment(id: "flow:exam", kind: .exam, source: .calendar, title: "ECON 1150 midterm", startDate: Date().addingTimeInterval(1200), detectedBy: .onDeviceModel)
        model.handle(exam, simulated: false)
        check(model.panel == nil && model.pending != nil, "over the daily limit, a suggestion waits instead of popping up")

        // Later puts it back in the queue for two hours.
        if let waiting = model.pending {
            model.present(waiting)
            model.later(waiting)
            check(model.panel == nil && model.pending != nil, "Later hides the card and keeps it for later")
        }

        // Pausing holds everything.
        model.prefs.demo.ignoreCap = true
        model.pause(hours: 1)
        let interview = Moment(id: "flow:interview", kind: .interview, source: .calendar, title: "OCS mock interview", startDate: Date().addingTimeInterval(1200), detectedBy: .onDeviceModel)
        model.handle(interview, simulated: false)
        check(model.panel == nil, "while paused, nothing pops up")
        model.resume()

        print("  \(failures == 0 ? "All flow checks passed." : "\(failures) flow checks failed.")")
        model.resetAll()
    }

    static func describe(_ state: BucketState) -> String {
        switch state {
        case .empty: return "gap"
        case .unused: return "unused"
        case .inUse: return "covered"
        case .notForMe: return "off"
        }
    }
}

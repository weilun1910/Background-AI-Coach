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
        await screenTest(model)
    }

    /// Runs the screen pipeline on pictures of the demo's pretend windows:
    /// the never-read list, reading, labels, habits, tips, careers and learning.
    static func screenTest(_ model: AppModel) async {
        print("\nScreen test:")
        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            print("  \(ok ? "pass" : "FAIL"): \(label)")
            if !ok { failures += 1 }
        }
        model.resetAll()
        model.prefs.onboarded = true
        model.prefs.mainHub = "chatgpt"
        model.prefs.screenLooksEnabled = true
        model.prefs.windowTitlesEnabled = true
        model.prefs.demo = DemoSettings(freshMac: true, dryRun: true, ignoreCap: true)
        model.prefs.newToolsPerWeek = 1

        let director = StageDirector.shared
        func picture(_ window: StageWindow) -> CGImage? {
            Snapshots.image(StageWindowView(window: window, director: director), width: window.frame.width, height: window.frame.height)
        }
        func timedLook(_ window: StageWindow, app: String, bundleID: String) async -> (ScreenOutcome, Int) {
            let start = Date()
            let outcome = await model.lookAt(image: picture(window), app: app, bundleID: bundleID, title: window.title, dwell: 120)
            return (outcome, Int(Date().timeIntervalSince(start) * 1000))
        }

        // Never read: no picture is taken and nothing is kept.
        let before = model.journal.entries.count
        if case .skipped = await model.lookAt(image: nil, app: "Passwords", bundleID: "com.apple.Passwords", title: "Passwords", dwell: 120) {
            check(model.journal.entries.count == before, "Passwords is never read, and nothing is kept")
        } else {
            check(false, "Passwords is never read")
        }
        check(NeverRead.reason(bundleID: "com.apple.Safari", app: "Safari", title: "Private Browsing", extra: []) != nil, "a private browsing window is never read")
        check(NeverRead.reason(bundleID: "com.apple.Safari", app: "Safari", title: "Chase Online Banking", extra: []) != nil, "a banking window is never read")
        check(NeverRead.reason(bundleID: "com.example.notes", app: "Notes", title: "Draft", extra: ["com.example.notes"]) != nil, "apps the student adds are never read")

        // Reading real pictures of windows.
        let letter = StageWindow(app: "word", title: "Cover letter - McKinsey.docx", detail: "coverMcKinsey", flag: nil)
        let (o1, ms1) = await timedLook(letter, app: "Microsoft Word", bundleID: "com.microsoft.Word")
        if case .read(let e, _) = o1 {
            print("    letter -> \(e.kind.rawValue), \(e.organization ?? "no org"), \"\(e.label)\" [\(e.readBy.rawValue), \(ms1) ms]")
            check(e.kind == .drafting && OrgNames.orgKey(e.organization ?? "") == "mckinsey", "a cover letter in Word reads as writing for McKinsey")
            check(ms1 < 2000, "one look takes under 2 seconds (\(ms1) ms)")
        } else { check(false, "the letter was read") }

        let profile = StageWindow(app: "safari", title: "Safari", detail: "profile:Alex Chen|Engagement Manager at McKinsey & Company|Washington, DC|linkedin.com/in/alexchen-yale", flag: nil)
        let (o2, ms2) = await timedLook(profile, app: "Safari", bundleID: "com.apple.Safari")
        if case .read(let e, _) = o2 {
            print("    profile -> \(e.kind.rawValue), \(e.organization ?? "no org"), \"\(e.label)\" [\(ms2) ms]")
            check(e.kind == .profile, "a LinkedIn page reads as a profile")
            check(!e.label.contains("Alex"), "the kept label leaves out the person's name")
        } else { check(false, "the profile was read") }

        let posting = StageWindow(app: "safari", title: "Safari", detail: "posting:McKinsey & Company|Business Analyst Intern, Summer 2027|Washington, DC|mckinsey.com/careers", flag: nil)
        let (o3, ms3) = await timedLook(posting, app: "Safari", bundleID: "com.apple.Safari")
        if case .read(let e, let result) = o3 {
            print("    posting -> \(e.kind.rawValue), \(e.organization ?? "no org"), \"\(e.label)\" [\(ms3) ms]")
            check(e.kind == .jobPosting, "a careers page reads as a job posting")
            if case .shown(let s) = result {
                check(s.kind == .tip && s.workflow?.id == "posting-check", "a posting after a letter for the same company gives the posting-check tip")
                check(s.prompt?.contains("McKinsey") == true, "the tip's prompt is filled in with McKinsey")
                check(s.tool.id == "chatgpt-app", "the tip runs in the student's main AI app")
            } else { check(false, "a posting after a letter for the same company shows a tip") }
        } else { check(false, "the posting was read") }
        model.closePanel()

        // Privacy of what's kept.
        let saved = (try? String(contentsOf: model.journal.url, encoding: .utf8)) ?? ""
        check(!saved.contains("eviction") && !saved.contains("Engagement Manager at") && !saved.contains("Qualifications"), "the journal file holds labels only, none of the window text")
        check(Redact.clean("emailing jo@yale.edu at 203-555-0199 about 12345678") == "emailing at about", "labels lose emails, phone numbers and long numbers")

        // Switching between ChatGPT and Word, and the tip that follows.
        let now = Clock.now
        for i in 0..<6 {
            let chat = i % 2 == 0
            model.focus.record(bundleID: chat ? "com.openai.chat" : "com.microsoft.Word", app: chat ? "ChatGPT" : "Microsoft Word", title: chat ? "ChatGPT" : "Cover letter - McKinsey.docx", at: now.addingTimeInterval(Double(i - 6) * 120))
        }
        model.setFrontmost("com.openai.chat")
        let shuttle = model.checkSwitchingHabits()
        if case .shown(let s)? = shuttle {
            check(s.workflow?.id == "feedback-in-one-go", "pasting back and forth gives the one-go feedback tip")
            check(s.prompt?.contains("cover letter for McKinsey") == true, "the prompt uses what the look kept (\(s.prompt?.prefix(48) ?? ""))")
            model.copyPrompt(s)
            check(model.log.events.last?.event == "prompt_copied", "Copy prompt is logged")
            model.never(s)
            check(model.prefs.notForMeWorkflows.contains("feedback-in-one-go"), "Not for me turns off that tip")
        } else {
            check(false, "pasting back and forth shows a tip")
        }
        check(model.checkSwitchingHabits().map { if case .duplicate = $0 { return true } else { return false } } ?? true, "the same habit isn't raised twice in a day")

        // Careers change the prompt.
        model.prefs.careers = ["consulting"]
        let match = HabitMatch(habit: .coffeeChatPrep, noticed: "test", organization: "McKinsey & Company", role: "Engagement Manager", key: "t")
        if let w = model.catalog.workflow("coffee-chat-questions") {
            let prompt = model.engine.fill(w, match)
            check(prompt.contains("an engagement manager at McKinsey") && prompt.contains("staffed"), "a consulting student's coffee chat prompt asks about staffing")
        }
        model.prefs.careers = []

        // Nothing to run it in: one new app, then the weekly budget says no.
        model.prefs.mainHub = "none"
        let fresh = HabitMatch(habit: .postingAfterDraft, noticed: "test", organization: "Bain", key: "t2")
        let moment = Moment(id: "t2", kind: .writing, source: .screen, title: "test", startDate: nil, detectedBy: .habitRules)
        if case .suggest(let s) = model.engine.decide(habit: fresh, moment: moment, how: "") {
            check(s.kind == .setUp, "with no AI app, it falls back to one new app (\(s.tool.name))")
        } else { check(false, "with no AI app, it falls back to a new app") }
        model.prefs.demo.ignoreCap = false
        model.log.append(OutcomeEvent(date: Clock.now, event: "shown", tool: "grammarly", bucket: "writing-feedback", moment: "writing", source: "screen", kind: "setUp"))
        if case .quiet = model.engine.decide(habit: fresh, moment: moment, how: "") {
            check(true, "after one new app this week, it stays quiet instead of adding another")
        } else { check(false, "the weekly new-app budget holds") }
        model.prefs.mainHub = "chatgpt"

        // Learning when not to interrupt.
        model.resetLearning()
        for _ in 0..<2 {
            model.log.append(OutcomeEvent(date: Clock.now, event: "later", tool: "chatgpt-app", bucket: "", moment: "", source: "screen", app: "com.microsoft.Word"))
        }
        model.refreshLearned()
        check(model.learned.holdApps["com.microsoft.Word"] == 2, "two cards put off in Word teach it to wait in Word")
        model.prefs.dailyCap = 5
        model.setFrontmost("com.microsoft.Word")
        check(!model.canShow(), "cards wait while Word is in front")
        model.setFrontmost("com.apple.Safari")
        check(model.canShow(), "cards can show once you leave Word")
        model.resetLearning()
        check(model.learned.holdApps.isEmpty, "Forget what I learned clears it")

        print("  \(failures == 0 ? "All screen checks passed." : "\(failures) screen checks failed.")")
        model.resetAll()
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
        // This checks the daily limit. The weekly new-app limit has its own check below.
        model.prefs.newToolsPerWeek = 0
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

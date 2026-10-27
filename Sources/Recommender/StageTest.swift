import AppKit
import SwiftUI

/// `--stage-test [--render <folder>]` plays every persona's full-screen demo
/// instantly, prints what's on screen after each beat, and can render each
/// beat to PNG so the stage can be checked without clicking through it.
@MainActor
enum StageTest {
    static func run(renderTo dir: URL?) async {
        let director = StageDirector.shared
        director.setInstant(true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        if let error = director.demo.loadError { print(error) }

        for index in director.demo.personas.indices {
            director.load(index)
            guard let persona = director.persona else { continue }
            print("\n\(persona.name): \(persona.tagline)")
            if let dir { render(director, dir.appendingPathComponent("\(persona.id)-00-intro.png")) }
            var n = 1
            while !director.atEnd {
                let label = director.currentBeatLabel
                await director.next()
                // Let background updates (like the menu's Coming up list) land.
                for _ in 0..<8 { await Task.yield() }
                let windows = director.windows.map(\.app).joined(separator: ",")
                print("  \(String(format: "%02d", n)) \(label)  [windows: \(windows)] [card: \(describe(director.model.panel))]\(director.menuOpen ? " [menu open]" : "")\(director.note != nil ? " [notification]" : "")")
                if let dir {
                    let name = "\(persona.id)-\(String(format: "%02d", n))-\(label.replacingOccurrences(of: " ", with: "-")).png"
                    render(director, dir.appendingPathComponent(name))
                }
                n += 1
            }
            let shown = director.results.filter { $0.tone == .card }.count
            let held = director.results.filter { $0.tone == .held }.count
            let quiet = director.results.filter { $0.tone == .quiet }.count
            print("  Summary: \(shown) shown, \(held) held, \(quiet) quiet")
        }
        director.setInstant(false)
    }

    private static func describe(_ panel: PanelState?) -> String {
        switch panel {
        case .none: return "none"
        case .card(let s): return "\(s.kind == .coach ? "coach" : "suggest") \(s.tool.name)"
        case .setup(let s): return "setup \(s.tool.name)"
        case .walkthrough(let s): return "walkthrough \(s.tool.name)"
        case .done(let s): return "done \(s.tool.name)"
        case .quiet: return "quiet"
        }
    }

    private static func render(_ director: StageDirector, _ url: URL) {
        Snapshots.render(StageView(director: director, model: director.model), width: StageDirector.canvas.width, height: StageDirector.canvas.height, to: url)
    }
}

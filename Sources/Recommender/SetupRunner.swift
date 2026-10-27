import AppKit

/// Does the parts of setup the platform allows: Homebrew installs, adding an
/// MCP server to Claude Code, or opening the right page. Everything else is a
/// checklist the user ticks off.
@MainActor
final class SetupRunner: ObservableObject {
    @Published private(set) var output = ""
    @Published private(set) var running = false
    @Published private(set) var succeeded: Bool?

    private var process: Process?

    static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func reset() {
        process?.terminate()
        process = nil
        output = ""
        running = false
        succeeded = nil
    }

    func canAutomate(_ tool: Tool) -> Bool {
        switch tool.setup.method {
        case .brewCask: return Self.brewPath != nil && Self.validCask(tool.setup.brewCask)
        case .claudeMCP: return Self.validMCPCommand(tool.setup.command)
        case .openURL: return false
        }
    }

    func automateLabel(_ tool: Tool) -> String {
        switch tool.setup.method {
        case .brewCask: return "Install it for me"
        case .claudeMCP: return "Add it to Claude Code"
        case .openURL: return "Open \(Self.host(tool.setup.url))"
        }
    }

    func run(_ tool: Tool, dryRun: Bool) {
        reset()
        let recipe = tool.setup
        switch recipe.method {
        case .openURL:
            open(recipe.url)
            succeeded = true
        case .brewCask:
            guard let brew = Self.brewPath, let cask = recipe.brewCask, Self.validCask(cask) else {
                open(recipe.url)
                output = "Homebrew isn't installed, so I opened the download page instead.\n"
                succeeded = true
                return
            }
            launch(executable: brew, arguments: ["install", "--cask", cask], display: "brew install --cask \(cask)", dryRun: dryRun) { [weak self] ok in
                if ok { self?.openApp(tool) }
            }
        case .claudeMCP:
            guard let command = recipe.command, Self.validMCPCommand(command) else { return }
            launch(executable: "/bin/zsh", arguments: ["-lc", command], display: command, dryRun: dryRun, completion: nil)
        }
    }

    private func launch(executable: String, arguments: [String], display: String, dryRun: Bool, completion: ((Bool) -> Void)?) {
        running = true
        output = "$ \(display)\n"
        if dryRun {
            output += "Demo mode is on, so nothing was installed.\n"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.running = false
                self?.succeeded = true
            }
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.output += text }
        }
        p.terminationHandler = { proc in
            let status = proc.terminationStatus
            Task { @MainActor [weak self] in
                pipe.fileHandleForReading.readabilityHandler = nil
                guard let self else { return }
                self.running = false
                let ok = status == 0
                self.succeeded = ok
                self.output += ok ? "\nDone.\n" : "\nThat didn't work (exit code \(status)). You can still use the steps below.\n"
                completion?(ok)
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            running = false
            succeeded = false
            output += "Couldn't start: \(error.localizedDescription)\n"
        }
    }

    func open(_ string: String?) {
        guard let string, let url = URL(string: string) else { return }
        if AppModel.personaLaunch {
            // The persona demo never opens real pages or apps.
            output += "Demo: would open \(url.host ?? string)\n"
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openApp(_ tool: Tool) {
        if AppModel.personaLaunch { return }
        for name in tool.detect.appNames ?? [] {
            for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
                let url = URL(fileURLWithPath: "\(dir)/\(name).app")
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    return
                }
            }
        }
    }

    // Catalog entries can only trigger these two shapes of command.
    static func validCask(_ s: String?) -> Bool {
        guard let s else { return false }
        return s.range(of: "^[a-z0-9][a-z0-9@._-]*$", options: .regularExpression) != nil
    }

    static func validMCPCommand(_ s: String?) -> Bool {
        guard let s else { return false }
        return s.hasPrefix("claude mcp add ") && s.range(of: "[;&|`$<>\\\\]", options: .regularExpression) == nil
    }

    static func host(_ s: String?) -> String {
        guard let s, let host = URL(string: s)?.host else { return "the website" }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

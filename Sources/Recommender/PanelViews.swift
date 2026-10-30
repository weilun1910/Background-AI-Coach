import SwiftUI

/// The floating card in the top-right corner. It never blocks the screen and
/// steps through: card -> setup -> walkthrough -> done.
struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        content
            .frame(width: 380, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch model.panel {
        case .card(let s): SuggestionCardView(model: model, s: s)
        case .setup(let s): SetupStepView(model: model, runner: model.setup, s: s)
        case .walkthrough(let s): WalkthroughView(model: model, s: s)
        case .done(let s): DoneView(model: model, s: s)
        case .quiet(let title, let reason): QuietView(model: model, title: title, reason: reason)
        case .none: EmptyView()
        }
    }
}

struct PanelTop: View {
    let symbol: String
    let label: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .stageTarget("panel-close")
        }
    }
}

struct SuggestionCardView: View {
    @ObservedObject var model: AppModel
    let s: Suggestion

    private var sourceLabel: String {
        switch s.moment.source {
        case .calendar: return "\(s.moment.kind.label), from your calendar"
        case .activeApp: return "\(s.moment.kind.label), from the app you're using"
        case .simulated: return "\(s.moment.kind.label), demo moment"
        case .screen: return s.kind == .tip ? "A tip, from how you work" : "\(s.moment.kind.label), from how you work"
        }
    }

    var body: some View {
        if s.kind == .tip {
            TipCardView(model: model, s: s)
        } else {
            toolCard
        }
    }

    private var toolCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTop(symbol: s.moment.kind.symbol, label: sourceLabel, onClose: { model.dismiss() })

            VStack(alignment: .leading, spacing: 4) {
                Text(s.headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                ToolIcon(symbol: s.tool.symbol, image: model.appIcon(for: s.tool))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(s.tool.name).font(.title3.weight(.semibold)).lineLimit(1)
                        if s.kind == .coach { Chip(text: "You have this", color: Theme.accent) }
                    }
                    Text(s.tool.cost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                InfoLine(symbol: "lightbulb", text: s.tool.why, color: Theme.accent)
                InfoLine(symbol: "eye", text: "It can see: " + s.tool.dataAccess)
            }

            if let consent = s.tool.consentNote {
                InfoLine(symbol: "exclamationmark.bubble", text: consent, color: Theme.warn)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 6) {
                Chip(text: s.tool.evidence.label, color: Theme.quiet, symbol: s.tool.evidence.symbol)
                Chip(text: s.kind == .coach ? "1 min rundown" : "About \(s.tool.setup.minutes) min to set up", color: Theme.quiet, symbol: "clock")
            }

            HStack(spacing: 8) {
                Button(s.kind == .coach ? "Show me how" : "Set it up") { model.accept(s) }
                    .buttonStyle(PrimaryButtonStyle())
                    .stageTarget("card-primary")
                Button("Later") { model.later(s) }
                    .buttonStyle(SecondaryButtonStyle())
                    .stageTarget("card-later")
                Spacer()
                Button("Not for me") { model.never(s) }
                    .buttonStyle(QuietButtonStyle())
                    .help("Never suggest \(s.bucket.plural)")
                    .stageTarget("card-notforme")
            }
        }
        .padding(16)
    }
}

struct SetupStepView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var runner: SetupRunner
    let s: Suggestion
    @State private var checked: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTop(symbol: "wrench.and.screwdriver", label: "Guided setup", onClose: { model.closePanel() })

            Text("Setting up \(s.tool.name)")
                .font(.headline)

            if model.prefs.demo.dryRun && runner.canAutomate(s.tool) {
                Chip(text: "Demo mode: nothing gets installed", color: Theme.warn, symbol: "theatermasks")
            }

            HStack(spacing: 8) {
                if runner.canAutomate(s.tool) {
                    Button(runner.running ? "Working..." : runner.automateLabel(s.tool)) { model.runSetup(s) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(runner.running || runner.succeeded == true)
                        .stageTarget("setup-run")
                    if let url = s.tool.setup.url {
                        Button("Download page") { runner.open(url) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                } else {
                    Button(runner.automateLabel(s.tool)) { model.runSetup(s) }
                        .buttonStyle(PrimaryButtonStyle())
                        .stageTarget("setup-run")
                }
            }

            if !runner.output.isEmpty {
                ScrollView {
                    Text(runner.output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 96)
                .padding(8)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Steps")
                ForEach(Array(s.tool.setup.steps.enumerated()), id: \.offset) { index, step in
                    Button {
                        if checked.contains(index) { checked.remove(index) } else { checked.insert(index) }
                    } label: {
                        NumberedStep(number: index + 1, text: step, done: checked.contains(index))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Button("Done, show me how to use it") { model.finishSetup(s) }
                    .buttonStyle(PrimaryButtonStyle())
                    .stageTarget("setup-done")
                Button("Cancel") { model.closePanel() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
    }
}

struct WalkthroughView: View {
    @ObservedObject var model: AppModel
    let s: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTop(symbol: "play.circle", label: "Quick rundown", onClose: { model.closePanel() })

            HStack(spacing: 10) {
                ToolIcon(symbol: s.tool.symbol, image: model.appIcon(for: s.tool), size: 32)
                Text(s.workflow.map { "\($0.name), in \(s.tool.name)" } ?? "Using \(s.tool.name) for \(s.moment.kind.phrase)")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array((s.steps.isEmpty ? s.tool.walkthrough(for: s.moment.kind) : s.steps).enumerated()), id: \.offset) { index, step in
                    NumberedStep(number: index + 1, text: step)
                }
            }

            if let prompt = s.prompt {
                PromptBox(model: model, s: s, prompt: prompt)
            }

            if s.kind != .tip, let avoid = s.tool.avoidIf {
                InfoLine(symbol: "hand.raised", text: "Skip it if \(avoid)")
            }

            Button("Got it") { model.finishWalkthrough(s) }
                .buttonStyle(PrimaryButtonStyle())
                .stageTarget("walkthrough-done")
        }
        .padding(16)
    }
}

struct DoneView: View {
    @ObservedObject var model: AppModel
    let s: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                Text("You're set with \(s.tool.name).")
                    .font(.headline)
            }
            Text("I'll note on this Mac whether you open it again this week. That's how the next suggestion gets better. Nothing is uploaded.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Close") { model.closePanel() }
                .buttonStyle(SecondaryButtonStyle())
                .stageTarget("done-close")
        }
        .padding(16)
        .task {
            try? await Task.sleep(for: .seconds(8))
            if case .done = model.panel { model.closePanel() }
        }
    }
}

struct QuietView: View {
    @ObservedObject var model: AppModel
    let title: String
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTop(symbol: "moon.zzz", label: "Staying quiet", onClose: { model.closePanel() })
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(reason)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("No gap means no card. In real use you wouldn't see this at all.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }
}

/// A tip: what the app noticed about how the student works, and a workflow
/// for an app they already have. No install, so no setup step.
struct TipCardView: View {
    @ObservedObject var model: AppModel
    let s: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTop(symbol: "lightbulb", label: "A tip, from how you work", onClose: { model.dismiss() })

            VStack(alignment: .leading, spacing: 4) {
                Text(s.headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                ToolIcon(symbol: s.tool.symbol, image: model.appIcon(for: s.tool))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(s.workflow?.name ?? s.tool.name).font(.body.weight(.semibold)).lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Text("In \(s.tool.name)").font(.caption).foregroundStyle(.secondary)
                        Chip(text: "You have this", color: Theme.accent)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                if let why = s.workflow?.why { InfoLine(symbol: "lightbulb", text: why, color: Theme.accent) }
                if let how = s.how { InfoLine(symbol: "eye", text: how) }
                if let learned = s.learned { InfoLine(symbol: "sparkles", text: learned) }
            }

            HStack(spacing: 6) {
                Chip(text: "Prompt ready to paste", color: Theme.quiet, symbol: "text.quote")
                Chip(text: "Nothing to install", color: Theme.quiet, symbol: "checkmark")
            }

            HStack(spacing: 8) {
                Button("Show me") { model.accept(s) }
                    .buttonStyle(PrimaryButtonStyle())
                    .stageTarget("card-primary")
                Button("Later") { model.later(s) }
                    .buttonStyle(SecondaryButtonStyle())
                    .stageTarget("card-later")
                Spacer()
                Button("Not for me") { model.never(s) }
                    .buttonStyle(QuietButtonStyle())
                    .help("Never suggest this tip again")
                    .stageTarget("card-notforme")
            }
        }
        .padding(16)
    }
}

/// The prompt, filled in on this Mac, with a button that copies it.
struct PromptBox: View {
    @ObservedObject var model: AppModel
    let s: Suggestion
    let prompt: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Your prompt")
                Spacer()
                Button {
                    model.copyPrompt(s)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(SecondaryButtonStyle())
                .stageTarget("prompt-copy")
            }
            Text(prompt)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(copied ? Theme.accent : Theme.hairline))
        }
        .onChange(of: s.id) { _, _ in copied = false }
    }
}

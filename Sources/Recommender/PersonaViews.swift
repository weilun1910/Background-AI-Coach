import SwiftUI

/// The presenter's window: pick a persona, see their pretend Mac, and click
/// through their day. The real card shows up in the top-right corner.
struct PersonaDemoView: View {
    @ObservedObject var demo: PersonaDemo
    @ObservedObject var model: AppModel

    static let width: CGFloat = 470
    static let height: CGFloat = 820

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            picker
            if let persona = demo.persona {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            personaCard(persona)
                            coverage
                            timeline(persona)
                        }
                        .padding(.trailing, 4)
                    }
                    .onChange(of: demo.nextIndex) { _, index in
                        withAnimation { proxy.scrollTo("step-\(max(0, index - 1))", anchor: .center) }
                    }
                }
                narration
                footer(persona)
            } else {
                Spacer()
                Text(demo.loadError ?? "Pick a persona to start their day.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(18)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(Theme.surface)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Persona demo")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("The same app on a pretend Mac. Nothing on this Mac is read, and nothing gets installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach(demo.personas) { persona in
                Button {
                    demo.select(persona)
                } label: {
                    VStack(spacing: 4) {
                        Avatar(persona: persona, size: 34)
                        Text(persona.name)
                            .font(.caption.weight(demo.persona == persona ? .semibold : .regular))
                            .foregroundStyle(demo.persona == persona ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous)
                            .fill(demo.persona == persona ? Theme.accent.opacity(0.10) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func personaCard(_ p: Persona) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Avatar(persona: p, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.title3.weight(.semibold))
                    Text(p.tagline).font(.callout).foregroundStyle(.secondary)
                }
            }
            Text(p.about)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("On their Mac")
                FlowLayout(spacing: 6) {
                    ForEach(p.apps, id: \.self) { app in
                        Chip(text: "\(displayName(app.name)), \(lastUsedText(app.daysSinceUsed))",
                             color: (app.daysSinceUsed ?? 0) > 30 ? Theme.warn : Theme.quiet)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                factLine("Main AI app", hubName(p.prefs.mainHub))
                factLine("Money", p.prefs.freeOnly ? "Free tools only" : "Will pay for something good")
                factLine("Cards a day", "\(p.prefs.dailyCap)")
                if !p.prefs.selfReported.isEmpty {
                    factLine("Uses on the web", p.prefs.selfReported.compactMap { model.catalog.tool($0)?.name }.joined(separator: ", "))
                }
                if !p.prefs.notForMe.isEmpty {
                    factLine("Not for me", p.prefs.notForMe.compactMap { model.catalog.bucket($0)?.name }.joined(separator: ", "))
                }
            }

            InfoLine(symbol: "lightbulb", text: "What this day shows: \(p.shows)", color: Theme.accent)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Their AI coverage right now")
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(model.catalog.buckets) { bucket in
                    HStack(spacing: 6) {
                        Text(bucket.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        StateChip(state: model.bucketStates[bucket.id] ?? .empty)
                    }
                    .padding(.trailing, 8)
                }
            }
        }
    }

    private func timeline(_ p: Persona) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Their day")
                Spacer()
                Label(demo.clockLabel, systemImage: "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            ForEach(Array(p.steps.enumerated()), id: \.offset) { index, step in
                stepRow(step, index: index)
                    .id("step-\(index)")
            }
        }
    }

    /// What to point out about the moment just played. Pinned above the buttons.
    @ViewBuilder private var narration: some View {
        if let (step, _) = demo.lastPlayed {
            VStack(alignment: .leading, spacing: 6) {
                InfoLine(symbol: "text.bubble", text: step.narration, color: Theme.accent)
                if let click = step.click, model.panel != nil {
                    Text("Try clicking: \(clickLabel(click))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            InfoLine(symbol: "hand.point.right", text: "Click Next moment to start the day. Cards show up in the top-right corner, just like real use.", color: Theme.accent)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func stepRow(_ step: PersonaStep, index: Int) -> some View {
        let played = demo.outcomes[index]
        let isNext = index == demo.nextIndex
        return HStack(alignment: .top, spacing: 10) {
            Text(demo.timeLabel(step))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            Circle()
                .fill(played != nil ? Theme.accent : (isNext ? Theme.accent.opacity(0.35) : Color.primary.opacity(0.15)))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(demo.stepLabel(step))
                    .font(.callout.weight(isNext ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                if let played {
                    Text(played.text)
                        .font(.caption)
                        .foregroundStyle(color(for: played.tone))
                        .fixedSize(horizontal: false, vertical: true)
                } else if isNext {
                    Text("Up next")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isNext ? Theme.accent.opacity(0.06) : Color.clear)
        )
    }

    private func footer(_ p: Persona) -> some View {
        HStack(spacing: 8) {
            Button("Restart day") { demo.restart() }
                .buttonStyle(SecondaryButtonStyle())
            Spacer()
            Text("\(min(demo.nextIndex, p.steps.count)) of \(p.steps.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button(demo.isFinished ? "Day's done" : (demo.running ? "Working..." : "Next moment")) {
                Task { await demo.next() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(demo.isFinished || demo.running)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    // MARK: Helpers

    private func factLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func color(for tone: OutcomeTone) -> Color {
        switch tone {
        case .card: return Theme.accent
        case .held: return Theme.warn
        case .quiet: return .secondary
        case .info: return Theme.gap
        }
    }

    private func clickLabel(_ click: PresenterClick) -> String {
        switch click {
        case .setUp:
            if case .card(let s) = model.panel, s.kind == .coach { return "Show me how" }
            return "Set it up"
        case .notForMe: return "Not for me"
        case .later: return "Later"
        case .close: return "the close button"
        }
    }

    private func hubName(_ id: String) -> String {
        Preferences.hubs.first { $0.id == id }?.name ?? id
    }

    private func displayName(_ app: String) -> String {
        app == "zoom.us" ? "Zoom" : app
    }

    private func lastUsedText(_ days: Int?) -> String {
        guard let days else { return "never opened" }
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2...29: return "\(days) days ago"
        default: return "\(days / 30) months ago"
        }
    }
}

struct Avatar: View {
    let persona: Persona
    var size: CGFloat = 36

    private var color: Color {
        switch persona.color {
        case "gap": return Theme.gap
        case "warn": return Theme.warn
        case "purple": return Color(red: 0.49, green: 0.33, blue: 0.82)
        case "pink": return Color(red: 0.84, green: 0.29, blue: 0.53)
        default: return Theme.accent
        }
    }

    var body: some View {
        Text(String(persona.name.prefix(1)))
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }
}

/// Lays children out left to right and wraps to a new row when full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

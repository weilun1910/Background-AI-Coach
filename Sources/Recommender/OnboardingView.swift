import SwiftUI

/// First-run setup: what it does, your AI setup, your career goals, what's
/// off limits, what it looks at, then your coverage.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var page: Int
    let close: () -> Void

    static let pageCount = 6

    init(model: AppModel, startPage: Int = 0, close: @escaping () -> Void) {
        self.model = model
        self._page = State(initialValue: startPage)
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch page {
                    case 0: welcome
                    case 1: yourSetup
                    case 2: careers
                    case 3: notForMe
                    case 4: permissions
                    default: summary
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 20)
            }
            Divider()
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(0..<Self.pageCount, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Theme.accent : Color.primary.opacity(0.15))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Back") { page -= 1 }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button(page == Self.pageCount - 1 ? "Start watching" : "Next") {
                    if page == Self.pageCount - 1 {
                        model.prefs.onboarded = true
                        close()
                    } else {
                        page += 1
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 580, height: 640)
        .background(Theme.surface)
    }

    private func title(_ text: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            ToolIcon(symbol: "sparkles", size: 56)
            title("The right AI tool, when you need it",
                  "I sit in your menu bar and notice moments like a coffee chat, a mock interview or an application deadline.")
            VStack(alignment: .leading, spacing: 12) {
                InfoLine(symbol: "square.dashed", text: "If you don't have a good tool for that moment, I suggest one and help you set it up.", color: Theme.accent)
                InfoLine(symbol: "hand.wave", text: "If you have one but haven't used it, I show you how in a minute.", color: Theme.accent)
                InfoLine(symbol: "moon.zzz", text: "If you're already covered, I stay quiet. At most one suggestion a day.", color: Theme.accent)
                InfoLine(symbol: "lightbulb", text: "If you turn it on, I also notice how you work and suggest better ways to use apps you already have.", color: Theme.accent)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield").font(.title3).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your stuff stays on this Mac").font(.callout.weight(.semibold))
                    Text("Your calendar, your app activity and anything I read on your screen are read here, by Apple's on-device model when your Mac has it. I download a public list of tools once a day. Nothing about you is uploaded.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
        }
    }

    private var yourSetup: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Your AI setup", "So I don't suggest things you already have.")

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Which AI app do you use most?")
                Picker("", selection: $model.prefs.mainHub) {
                    ForEach(Preferences.hubs, id: \.id) { hub in
                        Text(hub.name).tag(hub.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Money")
                Toggle("Only suggest tools with a free plan", isOn: $model.prefs.freeOnly)
                    .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Which of these do you already use?")
                Text("I can see the apps on your Mac, but not websites or features inside other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                toolGrid("Websites", model.catalog.tools.filter { $0.kind == .web })
                toolGrid("Features inside apps", model.catalog.tools.filter { $0.kind == .feature })
            }
        }
    }

    private func toolGrid(_ heading: String, _ tools: [Tool]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading).font(.callout.weight(.semibold)).padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(tools) { tool in
                    Toggle(isOn: model.membership(\.selfReported, tool.id)) {
                        Text(tool.name).lineLimit(1)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var careers: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("What are you working toward?",
                  "Pick any that fit. Tips for your field rank higher, and some prompts have a version for it, like case questions for consulting.")
            CareerPicker(model: model)
            Toggle("I'm recruiting right now", isOn: $model.prefs.recruitingNow)
                .toggleStyle(.checkbox)
        }
    }

    private var notForMe: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Anything you'd rather do yourself?",
                  "Some people like taking their own notes or writing every word. Tick those and I'll never suggest tools for them.")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.catalog.buckets) { bucket in
                    Toggle(isOn: model.membership(\.notForMe, bucket.id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bucket.name)
                            Text(bucket.job).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("What I look at", "Two things to start. Two more if you want tips about how you work. You can turn any of them off later.")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar").font(.title3).foregroundStyle(Theme.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your calendar").font(.callout.weight(.semibold))
                        Text("Event titles and times, to spot meetings, interviews and deadlines.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    switch model.calendarAccess {
                    case .granted: Chip(text: "Connected", color: Theme.accent, symbol: "checkmark")
                    case .notDetermined:
                        Button("Allow") { model.requestCalendar() }
                            .buttonStyle(PrimaryButtonStyle())
                    case .denied: Chip(text: "Off in System Settings", color: Theme.warn)
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "macwindow").font(.title3).foregroundStyle(Theme.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Which app is in front").font(.callout.weight(.semibold))
                        Text("For moments like going back and forth to Figma. No window titles and no screen recording.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Chip(text: "No prompt needed", color: Theme.quiet)
                }
            }
            .padding(14)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                ScreenSignalRows(model: model)
            }
            .padding(14)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))

            InfoLine(symbol: "cpu", text: "Event titles are read by \(model.detector.statusText.hasPrefix("Apple") ? "Apple's on-device model, right on this Mac" : model.detector.statusText.lowercased()).", color: Theme.accent)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Here's your AI coverage", "Gaps are where I might speak up. Covered areas stay quiet.")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.catalog.buckets) { bucket in
                    HStack(spacing: 10) {
                        Image(systemName: bucket.symbol).foregroundStyle(.secondary).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bucket.name).font(.callout)
                            Text(model.coverageLine(for: bucket)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        StateChip(state: model.bucketStates[bucket.id] ?? .empty)
                    }
                }
            }
            .padding(14)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
        }
    }
}

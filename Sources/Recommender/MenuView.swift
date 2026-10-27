import SwiftUI

/// What you see when you click the menu-bar icon.
struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let error = model.catalogError {
                InfoLine(symbol: "exclamationmark.triangle", text: error, color: Theme.warn)
            }
            if let pending = model.pending { pendingRow(pending) }
            comingUp
            coverage
            noticed
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Background AI Coach").font(.headline)
                Text(model.detector.activeDetector == .onDeviceModel ? "Using Apple's on-device model" : "Using keyword rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(model.detector.statusText)
            }
            Spacer()
            if model.isPaused {
                Chip(text: "Paused", color: Theme.quiet, symbol: "pause.fill")
            } else {
                Chip(text: "Watching", color: Theme.accent, symbol: "eye")
            }
        }
    }

    private func pendingRow(_ s: Suggestion) -> some View {
        HStack(spacing: 10) {
            ToolIcon(symbol: s.tool.symbol, image: model.appIcon(for: s.tool), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("A suggestion is waiting").font(.callout.weight(.medium))
                Text("\(s.tool.name) for \(s.moment.kind.phrase)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Show") { model.present(s) }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(10)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
    }

    private var comingUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Coming up")
            switch model.calendarAccess {
            case .granted:
                if !model.prefs.calendarEnabled {
                    Text("Calendar is turned off in Settings.").font(.caption).foregroundStyle(.secondary)
                } else if model.upcoming.isEmpty {
                    Text("Nothing in the next day and a half.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(model.upcoming.prefix(4)) { item in upcomingRow(item) }
                }
            case .notDetermined:
                HStack {
                    Text("Connect your calendar so I can spot meetings and deadlines.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Connect") { model.requestCalendar() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            case .denied:
                Text("Calendar access is off. Turn it on in System Settings, under Privacy & Security, then Calendars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func upcomingRow(_ item: UpcomingItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind?.symbol ?? "calendar")
                .foregroundStyle(item.kind == nil ? Color.secondary : Theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.callout).lineLimit(1)
                Text("\(Timing.short(item.start)), \(item.kind?.label.lowercased() ?? "not a work moment")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let state = model.primaryState(for: item.kind) { StateChip(state: state) }
        }
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Your AI coverage")
            ForEach(model.catalog.buckets) { bucket in
                HStack(spacing: 10) {
                    Image(systemName: bucket.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bucket.name).font(.callout)
                        Text(model.coverageLine(for: bucket))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    StateChip(state: model.bucketStates[bucket.id] ?? .empty)
                }
            }
        }
    }

    private var noticed: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("What I noticed")
            if model.activity.isEmpty {
                Text("Nothing yet. Try a moment below to see how it decides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.activity.prefix(3)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(item.title).font(.callout).lineLimit(1)
                                Spacer()
                                Text(item.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Label("Nothing about you leaves this Mac.", systemImage: "lock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 12) {
                Menu {
                    ForEach(AppModel.demos) { demo in
                        Button(demo.label) { model.simulate(demo) }
                    }
                } label: {
                    Label("Try a moment", systemImage: "wand.and.stars")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Menu {
                    if model.isPaused {
                        Button("Resume now") { model.resume() }
                    } else {
                        Button("Pause for an hour") { model.pause(hours: 1) }
                        Button("Pause until tomorrow morning") { model.pause(hours: nil) }
                    }
                } label: {
                    Image(systemName: model.isPaused ? "play.circle" : "pause.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(model.isPaused ? "Resume" : "Pause")

                Button {
                    WindowManager.shared.showSettings(model)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quit")
            }
        }
    }
}

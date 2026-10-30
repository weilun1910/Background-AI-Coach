import Combine
import SwiftUI

// Controls for career goals, screen reading, the never-read list, what it
// learned and what it noticed. Onboarding and Settings share them.

extension AppModel {
    func careerBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { self.prefs.careers.contains(id) },
            set: { on in
                if on {
                    if !self.prefs.careers.contains(id) { self.prefs.careers.append(id) }
                } else {
                    self.prefs.careers.removeAll { $0 == id }
                }
            }
        )
    }
}

/// Careers as tickable chips, two columns.
struct CareerPicker: View {
    @ObservedObject var model: AppModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(Careers.all, id: \.id) { career in
                Toggle(career.name, isOn: model.careerBinding(career.id))
                    .toggleStyle(.checkbox)
            }
        }
    }
}

/// The two screen signals, each with its own switch and macOS permission.
struct ScreenSignalRows: View {
    @ObservedObject var model: AppModel
    /// Re-reads the permission state now and then, since macOS doesn't announce changes.
    @State private var tick = 0
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(
                symbol: "macwindow",
                title: "Window titles",
                detail: "The name of the window you're in, like \u{201C}Cover letter - McKinsey.docx\u{201D}. Helps me notice habits like pasting back and forth.",
                isOn: $model.prefs.windowTitlesEnabled,
                granted: ScreenPermissions.accessibility,
                permission: "Accessibility",
                ask: { ScreenPermissions.askAccessibility() },
                pane: "Privacy_Accessibility"
            )
            Divider()
            row(
                symbol: "eye",
                title: "An occasional look at the window",
                detail: "After you've stayed in a window for a minute, I read its text on this Mac and keep one short line, like \u{201C}writing a cover letter for McKinsey in Word\u{201D}. Never the picture, never the text. At most 12 times an hour.",
                isOn: $model.prefs.screenLooksEnabled,
                granted: ScreenPermissions.accessibility,
                permission: "Accessibility",
                ask: { ScreenPermissions.askAccessibility() },
                pane: "Privacy_Accessibility"
            )
            if model.prefs.screenLooksEnabled {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "rectangle.dashed.badge.record").foregroundStyle(.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen Recording (optional)").font(.callout.weight(.semibold))
                        Text("Only for apps that don't share their text, like some PDF viewers. macOS will ask you again every so often while it's on.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    permissionButton(granted: ScreenPermissions.screen, ask: { ScreenPermissions.askScreen() }, pane: "Privacy_ScreenCapture")
                }
            }
            if let last = model.lastLook {
                InfoLine(symbol: "clock", text: "Last look at \(last.date.formatted(date: .omitted, time: .shortened)). Kept \u{201C}\(last.text)\u{201D}.")
            }
        }
        .id(tick)
        .onReceive(timer) { _ in tick &+= 1 }
    }

    private func row(symbol: String, title: String, detail: String, isOn: Binding<Bool>, granted: Bool, permission: String, ask: @escaping () -> Void, pane: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: isOn) {
                    Text(title).font(.callout.weight(.semibold))
                }
                .toggleStyle(.switch)
                Text(detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isOn.wrappedValue {
                    HStack(spacing: 8) {
                        Text("Needs \(permission)").font(.caption.weight(.medium))
                        permissionButton(granted: granted, ask: ask, pane: pane)
                    }
                }
            }
        }
    }

    @ViewBuilder private func permissionButton(granted: Bool, ask: @escaping () -> Void, pane: String) -> some View {
        if granted {
            Chip(text: "Allowed", color: Theme.accent, symbol: "checkmark")
        } else {
            HStack(spacing: 6) {
                Button("Allow") { ask() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Open Settings") { ScreenPermissions.openSettings(pane) }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }
}

/// Apps it never reads, and never interrupts.
struct NeverReadEditor: View {
    @ObservedObject var model: AppModel

    private var running: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .filter { app in !NeverRead.apps.contains { $0.id == app.bundleIdentifier } && !model.prefs.neverRead.contains(app.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Always: " + NeverRead.apps.map(\.name).joined(separator: ", ") + ", calls, password fields, and windows whose title mentions banking, health or private browsing.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.prefs.neverRead.sorted(), id: \.self) { id in
                HStack {
                    Text(model.appName(for: id))
                    Spacer()
                    Button("Remove") { model.prefs.neverRead.remove(id) }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            Menu("Add an app that's open") {
                ForEach(running, id: \.processIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier!) { model.prefs.neverRead.insert(app.bundleIdentifier!) }
                }
            }
            .fixedSize()
        }
    }
}

/// What the outcome log taught it, with a way to forget it.
struct LearnedList: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.learned.lines.isEmpty {
                Text("Nothing yet. When you put cards off in an app, or keep using a kind of tip, it shows up here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.learned.lines, id: \.self) { line in
                    InfoLine(symbol: "sparkles", text: line, color: Theme.accent)
                }
                Button("Forget what I learned") { model.resetLearning() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

/// The short labels it kept, newest first.
struct JournalList: View {
    @ObservedObject var model: AppModel
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let entries = Array(model.journal.entries.suffix(12).reversed())
            if entries.isEmpty {
                Text("Nothing kept yet. Labels are deleted after \(Int(ActivityJournal.keepDays)) days.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(alignment: .top) {
                        Text(entry.label).font(.callout)
                        Spacer()
                        Text(entry.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Delete all labels", role: .destructive) {
                    model.clearJournal()
                    tick &+= 1
                }
            }
        }
        .id(tick)
    }
}

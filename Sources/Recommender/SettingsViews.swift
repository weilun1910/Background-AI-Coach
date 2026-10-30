import SwiftUI

// MARK: - Shared pieces

extension AppModel {
    func membership(_ keyPath: WritableKeyPath<Preferences, Set<String>>, _ id: String) -> Binding<Bool> {
        Binding(
            get: { self.prefs[keyPath: keyPath].contains(id) },
            set: { on in
                if on { self.prefs[keyPath: keyPath].insert(id) } else { self.prefs[keyPath: keyPath].remove(id) }
            }
        )
    }

    /// Tools the Mac can't see, so the user ticks the ones they use.
    var selfReportableTools: [Tool] {
        catalog.tools.filter { $0.isSelfReported && $0.hub == nil } +
        catalog.tools.filter { $0.isSelfReported && $0.hub != nil }
    }
}

struct HubPicker: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Picker("Main AI app", selection: $model.prefs.mainHub) {
            ForEach(Preferences.hubs, id: \.id) { hub in
                Text(hub.name).tag(hub.id)
            }
        }
    }
}

struct CalendarStatusRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calendar")
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch model.calendarAccess {
            case .notDetermined:
                Button("Allow access") { model.requestCalendar() }
            case .denied:
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .granted:
                Toggle("", isOn: $model.prefs.calendarEnabled).labelsHidden()
            }
        }
    }

    private var statusText: String {
        switch model.calendarAccess {
        case .granted: return "Event titles and times, read on this Mac."
        case .notDetermined: return "Not connected yet."
        case .denied: return "Access is off in System Settings."
        }
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Your setup") {
                HubPicker(model: model)
                Toggle("Only suggest tools with a free plan", isOn: $model.prefs.freeOnly)
            }

            Section {
                CareerPicker(model: model)
                Toggle("I'm recruiting right now", isOn: $model.prefs.recruitingNow)
            } header: {
                Text("Career goals")
            } footer: {
                Text("Tips and tools for these rank higher, and some prompts have a version for your field. This stays on this Mac.")
            }

            Section {
                ForEach(model.selfReportableTools) { tool in
                    Toggle(isOn: model.membership(\.selfReported, tool.id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.name)
                            Text(tool.vendor).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Tools you already use")
            } footer: {
                Text("Websites and features inside other apps can't be seen from your Mac, so tick the ones you use.")
            }

            Section {
                ForEach(model.catalog.buckets) { bucket in
                    Toggle(isOn: model.membership(\.notForMe, bucket.id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bucket.name)
                            Text(bucket.job).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Not for me")
            } footer: {
                Text("Turn on anything you'd rather do yourself. I'll never suggest tools for it.")
            }

            Section("Suggestions") {
                Stepper("At most \(model.prefs.dailyCap) a day", value: $model.prefs.dailyCap, in: 1...5)
                Stepper(model.prefs.newToolsPerWeek == 0 ? "No limit on new apps" : "At most \(model.prefs.newToolsPerWeek) new app\(model.prefs.newToolsPerWeek == 1 ? "" : "s") a week", value: $model.prefs.newToolsPerWeek, in: 0...5)
                ForEach(model.prefs.notForMeWorkflows.sorted(), id: \.self) { id in
                    HStack {
                        Text("Not for me: \(model.catalog.workflow(id)?.name ?? id)")
                        Spacer()
                        Button("Bring back") { model.prefs.notForMeWorkflows.remove(id) }
                    }
                }
                HStack {
                    Text(model.isPaused ? "Paused" : "Active")
                    Spacer()
                    if model.isPaused {
                        Button("Resume") { model.resume() }
                    } else {
                        Button("Pause for an hour") { model.pause(hours: 1) }
                        Button("Until tomorrow") { model.pause(hours: nil) }
                    }
                }
            }

            Section {
                CalendarStatusRow(model: model)
                Toggle(isOn: $model.prefs.appSensorEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Which app is in front")
                        Text("For moments like going back and forth to Figma. No window titles, no screen recording.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $model.prefs.useOnDeviceModel) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Use Apple's on-device model to read event titles")
                        Text("Now using: \(model.detector.statusText)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("What I look at")
            }

            Section {
                ScreenSignalRows(model: model)
            } header: {
                Text("How you work")
            } footer: {
                Text("Both are off until you turn them on. They let me notice habits, like pasting between ChatGPT and Word, and suggest a better way to use apps you already have.")
            }

            Section("Never read") {
                NeverReadEditor(model: model)
            }

            Section("What I've learned") {
                LearnedList(model: model)
            }

            Section("What I kept from your screen") {
                JournalList(model: model)
            }

            Section {
                Text("Your calendar, your apps, the labels from your screen and your answers here stay on this Mac. I only download a public list of tools. Nothing about you is uploaded.")
                    .font(.callout)
                HStack {
                    Button("Show my data in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.dir])
                    }
                    Spacer()
                    Button("Reset everything", role: .destructive) { model.resetAll() }
                }
            } header: {
                Text("Privacy")
            }

            Section {
                Toggle("Pretend this is a fresh Mac", isOn: $model.prefs.demo.freshMac)
                Toggle("Don't actually install anything", isOn: $model.prefs.demo.dryRun)
                Toggle("Ignore the daily limit", isOn: $model.prefs.demo.ignoreCap)
            } header: {
                Text("Demo")
            } footer: {
                Text("Catalog \(model.catalog.version), \(model.catalog.buckets.count) buckets, \(model.catalog.tools.count) tools and \(model.catalog.workflows?.count ?? 0) workflows.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 600)
    }
}

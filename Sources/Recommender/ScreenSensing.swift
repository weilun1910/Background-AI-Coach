import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ScreenCaptureKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Permissions

/// The two extra macOS permissions screen reading needs. Both are off until
/// the student turns them on, and the app works without them.
enum ScreenPermissions {
    /// Window titles come through Accessibility.
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func askAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Looking at a window needs Screen Recording.
    static var screen: Bool { CGPreflightScreenCaptureAccess() }

    static func askScreen() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// True while a password field has the keyboard. Nothing is read then.
    static var secureInput: Bool { IsSecureEventInputEnabled() }

    static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Window titles

enum WindowTitles {
    /// The title of the focused window of the app in front, or nil.
    static func front(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }
}

// MARK: - Reading a window's text

/// The text an app shares with Accessibility, for its front window. Most apps
/// share it, so this is the first way the app looks: it needs no Screen
/// Recording, which macOS keeps re-asking about. Password fields are skipped.
enum WindowText {
    static func front(pid: pid_t, limit: Int = 2400) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return [] }
        var lines: [String] = []
        var seen = Set<String>()
        var total = 0
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 40, visited < 2000, total < limit else { return }
            visited += 1
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            if (role as? String) == "AXSecureTextField" || (subrole as? String) == "AXSecureTextField" { return }
            for attribute in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                      let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      text.count > 1, seen.insert(text).inserted else { continue }
                for line in text.split(separator: "\n").prefix(40) where total < limit {
                    let piece = String(line.prefix(400))
                    lines.append(piece)
                    total += piece.count
                }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let kids = children as? [AXUIElement] {
                for kid in kids { walk(kid, depth: depth + 1) }
            }
        }
        walk(window as! AXUIElement, depth: 0)
        return lines
    }

    /// True when the focused control is a password field.
    static func focusedIsSecure(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        var role: CFTypeRef?
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSubroleAttribute as CFString, &subrole)
        return (role as? String) == "AXSecureTextField" || (subrole as? String) == "AXSecureTextField"
    }
}

// MARK: - Looking at a window

enum WindowCapture {
    /// A picture of the app's front window, and only that window. It's kept in
    /// memory long enough to read the text in it.
    static func frontWindow(pid: pid_t) async throws -> CGImage? {
        // The window list is ordered front to back, so the first normal window
        // of this app is the one the student is looking at.
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let match = list.first { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid && (info[kCGWindowLayer as String] as? Int) == 0
        }
        guard let number = match?[kCGWindowNumber as String] as? CGWindowID else { return nil }

        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == number }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

// MARK: - Reading the text

enum TextReader {
    /// The lines of text in a picture, top to bottom, using Apple's on-device
    /// text recognition.
    static func lines(in image: CGImage) async -> [String] {
        await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])
            let results = (request.results ?? []).sorted {
                let a = $0.boundingBox, b = $1.boundingBox
                if abs(a.midY - b.midY) > 0.01 { return a.midY > b.midY }
                return a.minX < b.minX
            }
            return results.compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

// MARK: - What the window is

struct ActivityRead {
    var kind: ActivityKind
    var topic: String?
    var organization: String?
    var careerRelated: Bool
    var cues: Set<String>
    var readBy: Detector

    /// A short label for the journal, like "writing a cover letter for McKinsey in Word".
    func label(app: String) -> String {
        let place = app.replacingOccurrences(of: "Microsoft ", with: "")
        let org = organization.map { " for \(OrgNames.shortOrg($0))" } ?? ""
        switch kind {
        case .drafting: return "writing \(article(topic ?? "a document"))\(org) in \(place)"
        case .reading: return "reading \(topic.map(article) ?? "a document") in \(place)"
        case .jobPosting: return "reading a job posting\(org.isEmpty ? "" : " from \(OrgNames.shortOrg(organization!))") in \(place)"
        case .profile: return "looking at a professional profile in \(place)"
        case .aiChat: return "chatting with \(place)\(topic.map { " about \($0)" } ?? "")"
        case .slides: return "working on \(topic.map(article) ?? "a slide deck") in \(place)"
        case .notes: return "taking notes in \(place)"
        case .email: return "writing email in \(place)"
        case .coding: return "coding in \(place)"
        case .design: return "designing in \(place)"
        case .browsing: return "browsing in \(place)"
        case .other: return "using \(place)"
        }
    }

    private func article(_ noun: String) -> String {
        let n = noun.lowercased()
        if n.hasPrefix("a ") || n.hasPrefix("an ") || n.hasPrefix("the ") || n.hasPrefix("your ") { return noun }
        if n.hasSuffix("s") && !n.hasSuffix("ss") { return noun }
        return ("aeiou".contains(n.first ?? "x") ? "an " : "a ") + noun
    }
}

/// Turns a window's title and text into what the student is doing. Apple's
/// on-device model reads it when the Mac has it; keyword rules otherwise.
/// Clear cues, like a job posting's "Qualifications", beat the model.
@MainActor
final class ActivityReader {
    var useModel = true

    func read(app: String, bundleID: String?, title: String, lines: [String]) async -> ActivityRead {
        var result = Self.rules(app: app, bundleID: bundleID, title: title, lines: lines)
        #if canImport(FoundationModels)
        if useModel, #available(macOS 26.0, *), OnDeviceClassifier.isAvailable, !(title.isEmpty && lines.isEmpty) {
            if let guess = try? await OnDeviceActivity.read(app: app, title: title, lines: lines) {
                result = Self.merge(rules: result, model: guess, text: (title + "\n" + lines.joined(separator: "\n")).lowercased())
            }
        }
        #endif
        return result
    }

    /// Kinds the rules are sure about. The model only fills in the rest.
    static let ruleKinds: Set<ActivityKind> = [.aiChat, .profile, .jobPosting, .slides, .drafting, .coding, .design, .email]

    static func merge(rules: ActivityRead, model: ActivityRead, text: String) -> ActivityRead {
        var out = rules
        if !ruleKinds.contains(rules.kind) { out.kind = model.kind }
        if out.topic == nil, let topic = model.topic, !topic.isEmpty { out.topic = topic }
        // Only trust a company name the window actually shows.
        if out.organization == nil, let org = model.organization, !org.isEmpty, text.contains(org.lowercased()) {
            out.organization = org
        }
        out.careerRelated = rules.careerRelated || model.careerRelated
        out.readBy = .onDeviceModel
        return out
    }

    static func rules(app: String, bundleID: String?, title: String, lines: [String]) -> ActivityRead {
        let body = lines.joined(separator: "\n")
        let text = (title + "\n" + body).lowercased()
        func count(_ words: [String]) -> Int { words.filter { text.contains($0) }.count }
        let id = bundleID ?? ""

        var cues = Set<String>()
        if count(["responsibilities", "qualifications", "what you'll do", "about the role", "apply now", "requirements", "job description", "we're looking for", "who you are"]) >= 2 { cues.insert("posting") }
        if text.contains("linkedin") && (text.contains("/in/") || count(["connect", "message", "experience", "followers"]) >= 2) { cues.insert("profile") }
        if count(["education", "experience", "skills", "gpa", "b.a.", "b.s.", "bachelor", "expected graduation", "relevant coursework"]) >= 3 { cues.insert("resume") }
        if text.contains("cover letter") || (text.contains("dear ") && count(["hiring", "recruiting", "team,", "committee"]) >= 1) { cues.insert("cover letter") }
        let words = body.split { $0.isWhitespace }.count
        if HabitApps.slides.contains(id) && (words < 25 || text.contains("click to add title")) { cues.insert("blank") }

        var kind: ActivityKind = .other
        if HabitApps.aiChat[id] != nil || (HabitApps.browsers.contains(id) && ["chatgpt", "claude.ai", "gemini"].contains { title.lowercased().contains($0) }) {
            kind = .aiChat
        } else if cues.contains("profile") {
            kind = .profile
        } else if cues.contains("posting") && !HabitApps.documents.contains(id) {
            kind = .jobPosting
        } else if HabitApps.slides.contains(id) {
            kind = .slides
        } else if HabitApps.documents.contains(id) || title.lowercased().contains("google docs") {
            kind = .drafting
        } else if HabitApps.readers.contains(id) || title.lowercased().hasSuffix(".pdf") {
            kind = .reading
        } else if ["com.microsoft.VSCode", "com.apple.dt.Xcode", "com.todesktop.230313mzl4w4u92", "com.apple.Terminal"].contains(id) {
            kind = .coding
        } else if ["com.figma.Desktop", "com.canva.CanvaDesktop"].contains(id) {
            kind = .design
        } else if ["com.microsoft.Outlook", "com.google.Gmail"].contains(id) || title.lowercased().contains("gmail") {
            kind = .email
        } else if ["com.apple.Notes", "notion.id"].contains(id) {
            kind = .notes
        } else if HabitApps.browsers.contains(id) {
            kind = .browsing
        }

        var topic: String?
        if cues.contains("cover letter") { topic = "cover letter" }
        else if kind == .drafting && cues.contains("resume") { topic = "resume" }
        else if text.contains("personal statement") { topic = "personal statement" }
        else if kind == .drafting && text.contains("essay") { topic = "essay" }
        else if kind == .drafting && text.contains("memo") { topic = "memo" }
        else if kind == .reading { topic = "reading" }
        else if kind == .slides { topic = "slide deck" }
        else if kind == .aiChat && cues.contains("resume") { topic = "your resume" }

        var organization: String?
        var role: String?
        // "Cover letter - McKinsey.docx", "Cover letter: Bain & Company, Associate..."
        if let range = title.range(of: #"(?i)cover letter\s*[-:\u{2013}]\s*"#, options: .regularExpression) {
            let rest = title[range.upperBound...]
            let name = rest.split(whereSeparator: { ",.".contains($0) }).first.map(String.init)?.trimmingCharacters(in: .whitespaces)
            if let name, !name.isEmpty { organization = name }
        }
        // A profile headline or posting line like "Engagement Manager at McKinsey & Company".
        if organization == nil || kind == .profile {
            for line in lines.prefix(20) {
                guard let at = line.range(of: " at ") else { continue }
                let left = line[..<at.lowerBound].trimmingCharacters(in: .whitespaces)
                let right = line[at.upperBound...].trimmingCharacters(in: .whitespaces)
                guard (2...40).contains(left.count), (2...40).contains(right.count),
                      right.first?.isUppercase == true, left.first?.isUppercase == true else { continue }
                role = left
                organization = organization ?? right
                break
            }
        }
        if organization == nil { organization = OrgNames.organization(in: title + "\n" + body) }
        if let role { cues.insert("role:\(role)") }

        let careerRelated = cues.contains("posting") || cues.contains("profile") || cues.contains("cover letter") || cues.contains("resume")
            || organization != nil || count(["interview", "recruiting", "application", "internship"]) > 0
        return ActivityRead(kind: kind, topic: topic, organization: organization, careerRelated: careerRelated, cues: cues, readBy: .rules)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
enum ModelActivity {
    case drafting, reading, jobPosting, profile, aiChat, slides, notes, email, coding, design, browsing, other
}

@available(macOS 26.0, *)
@Generable
struct ScreenGuess {
    @Guide(description: "What the student is doing in this window.")
    var activity: ModelActivity
    @Guide(description: "What the work is about in two to five words, like cover letter or econ problem set. Never include a person's name.")
    var topic: String
    @Guide(description: "The company or organization the work is for, exactly as written in the window, or an empty string.")
    var organization: String
    @Guide(description: "True if this is for a job, internship, fellowship or recruiting.")
    var careerRelated: Bool
}

@available(macOS 26.0, *)
enum OnDeviceActivity {
    static let instructions = """
    You look at the text of one window on a college student's Mac and say what they are doing, so an assistant can offer tips. \
    drafting: writing a document such as a cover letter, essay or memo. reading: reading a paper, article or PDF. \
    jobPosting: reading a job or internship posting. profile: looking at a person's professional profile. \
    aiChat: chatting with an AI assistant. slides: making slides. notes: taking notes. email: reading or writing email. \
    coding, design, browsing, other. Keep the topic short and leave out people's names, grades and numbers.
    """

    /// Keeps well under the model's context window.
    static let maxCharacters = 1800

    static func read(app: String, title: String, lines: [String]) async throws -> ActivityRead {
        var text = lines.joined(separator: "\n")
        if text.count > maxCharacters { text = String(text.prefix(maxCharacters)) }
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "App: \(app)\nWindow title: \(title)\nText in the window:\n\(text)"
        let guess = try await session.respond(to: prompt, generating: ScreenGuess.self).content
        let kind: ActivityKind
        switch guess.activity {
        case .drafting: kind = .drafting
        case .reading: kind = .reading
        case .jobPosting: kind = .jobPosting
        case .profile: kind = .profile
        case .aiChat: kind = .aiChat
        case .slides: kind = .slides
        case .notes: kind = .notes
        case .email: kind = .email
        case .coding: kind = .coding
        case .design: kind = .design
        case .browsing: kind = .browsing
        case .other: kind = .other
        }
        let topic = guess.topic.split(separator: " ").prefix(5).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let org = guess.organization.trimmingCharacters(in: .whitespacesAndNewlines)
        return ActivityRead(kind: kind, topic: topic.isEmpty ? nil : Redact.clean(topic), organization: org.isEmpty ? nil : org, careerRelated: guess.careerRelated, cues: [], readBy: .onDeviceModel)
    }
}
#endif

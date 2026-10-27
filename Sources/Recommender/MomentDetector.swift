import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns a calendar event title into a workflow moment. Uses Apple's
/// on-device model when this Mac has it, and keyword rules otherwise.
/// Either way the title never leaves the Mac.
@MainActor
final class MomentDetector {
    var useModel = true {
        didSet { if useModel != oldValue { cache.removeAll() } }
    }
    private var cache: [String: (MomentKind?, Detector)] = [:]

    var modelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return OnDeviceClassifier.isAvailable }
        #endif
        return false
    }

    /// What's reading titles right now, in plain words.
    var statusText: String {
        if !useModel { return "Keyword rules (you turned the model off)" }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return OnDeviceClassifier.statusText }
        #endif
        return "Keyword rules (this macOS doesn't have Apple's model)"
    }

    var activeDetector: Detector { useModel && modelAvailable ? .onDeviceModel : .rules }

    func classify(_ title: String) async -> (MomentKind?, Detector) {
        let key = title.lowercased()
        if let cached = cache[key] { return cached }
        var result: (MomentKind?, Detector) = (Self.rules(title), .rules)
        #if canImport(FoundationModels)
        if useModel, #available(macOS 26.0, *), OnDeviceClassifier.isAvailable {
            do {
                let kind = try await OnDeviceClassifier.classify(title)
                // Unambiguous keywords ("interview", "midterm", "due") beat the
                // model. In testing it read "Superday - Evercore" as a coffee chat.
                if let ruled = result.0, Self.strongKinds.contains(ruled), ruled != kind {
                    result = (ruled, .rules)
                } else {
                    result = (kind, .onDeviceModel)
                }
            } catch {
                // Guardrail refusals and model updates fall back to the rules.
            }
        }
        #endif
        cache[key] = result
        return result
    }

    static let strongKinds: Set<MomentKind> = [.interview, .exam, .presentation, .writing]

    static func rules(_ title: String) -> MomentKind? {
        let t = " " + title.lowercased() + " "
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }

        if has(["interview", "superday", "phone screen", "recruiter call", "recruiting call"]) { return .interview }
        if has(["midterm", " exam", "final exam", " quiz "]) { return .exam }
        if has(["presentation", " pitch", "demo day", " present "]) { return .presentation }
        if has(["application due", "deadline", "cover letter", "essay due", "draft due", "personal statement", "application", " app due"]) { return .writing }
        if has(["coffee chat", "coffee with", "networking", "informational", "catch up with", "alumni chat"]) { return .networking }
        if has(["reading", "readings", "journal club", "paper discussion"]) { return .reading }
        let courseCode = title.range(of: #"\b[A-Z]{3,4}\s?\d{3,4}\b"#, options: .regularExpression) != nil
        if courseCode || has(["lecture", "seminar", "recitation", " section ", " class "]) { return .lecture }
        if has(["meeting", " sync", "standup", "stand-up", "1:1", "1-1", "office hours", "check-in", "check in", " call", "zoom", " team "]) { return .meeting }
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
enum ModelMoment {
    case meeting, networking, interview, lecture, exam, presentation, writing, reading, none
}

@available(macOS 26.0, *)
@Generable
struct ModelGuess {
    @Guide(description: "The one workflow moment this calendar event most likely is, or none if it is personal or unclear.")
    var moment: ModelMoment
}

@available(macOS 26.0, *)
enum OnDeviceClassifier {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var statusText: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Apple's on-device model"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "Keyword rules (this Mac can't run Apple's model)"
            case .appleIntelligenceNotEnabled: return "Keyword rules (Apple Intelligence is off)"
            case .modelNotReady: return "Keyword rules (Apple's model is still downloading)"
            @unknown default: return "Keyword rules"
            }
        }
    }

    static let instructions = """
    You label calendar events for a college student's assistant. Pick the one workflow moment the event most likely is.
    meeting: a work, club or team meeting, a call, or office hours.
    networking: a coffee chat, informational chat or networking conversation with a professional or alum.
    interview: a job or internship interview, including mock interviews.
    lecture: a class, lecture, seminar or section.
    exam: an exam, midterm, quiz or test.
    presentation: the student presents or pitches something.
    writing: a deadline for writing, such as an application, essay or cover letter.
    reading: time set aside to read papers or course readings.
    none: meals, workouts, travel, social plans, errands, or anything unclear.
    """

    static func classify(_ title: String) async throws -> MomentKind? {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: "Event title: \(title)", generating: ModelGuess.self)
        switch response.content.moment {
        case .meeting: return .meeting
        case .networking: return .networking
        case .interview: return .interview
        case .lecture: return .lecture
        case .exam: return .exam
        case .presentation: return .presentation
        case .writing: return .writing
        case .reading: return .reading
        case .none: return nil
        }
    }
}
#endif

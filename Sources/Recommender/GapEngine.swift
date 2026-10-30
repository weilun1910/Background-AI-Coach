import Foundation

enum Decision {
    case suggest(Suggestion)
    case quiet(String)
}

/// The "worth it" rule: for each bucket a moment touches, an empty bucket
/// gets a new tool, an owned-but-unused bucket gets coaching, and a bucket
/// in use (or turned off) stays quiet.
@MainActor
struct GapEngine {
    let catalog: Catalog
    let prefs: Preferences
    let usage: (Tool) -> ToolUsage
    /// What the outcome log taught it about this student.
    var learned = Learned()
    /// False once this week's new-app budget is used up.
    var newToolAllowed = true

    /// Below this score the engine would rather stay quiet.
    static let minimumScore = 0.5

    func state(of bucket: Bucket) -> BucketState {
        if prefs.notForMe.contains(bucket.id) { return .notForMe }
        var used: [String] = []
        var owned: [String] = []
        for tool in catalog.tools(in: bucket) {
            switch usage(tool) {
            case .inUse: used.append(tool.id)
            case .owned: owned.append(tool.id)
            case .none: break
            }
        }
        if !used.isEmpty { return .inUse(used) }
        if !owned.isEmpty { return .unused(owned) }
        return .empty
    }

    func decide(for moment: Moment, timing: String) -> Decision {
        let buckets = catalog.buckets(for: moment.kind)
        guard !buckets.isEmpty else {
            return .quiet("Nothing in the catalog covers \(moment.kind.label.lowercased()) moments yet.")
        }
        let headline = Self.headline(moment, timing: timing)
        var reasons: [String] = []

        for bucket in buckets {
            switch state(of: bucket) {
            case .notForMe:
                reasons.append("you said \(bucket.plural) aren't for you")
                continue
            case .inUse(let ids):
                reasons.append("you already use \(names(ids)) for this")
                continue
            case .unused(let ids):
                // Coach on something they own. Skip paid features if they only want free tools.
                // A connector needs the app it connects to, like Figma for the Figma connector.
                let coachable = ids.compactMap { catalog.tool($0) }
                    .filter { $0.fits(moment.kind) && requirementsMet($0) }
                    .filter { $0.kind == .app || $0.kind == .cli || !prefs.freeOnly || $0.free }
                    .sorted { rank($0, bucket) > rank($1, bucket) }
                if let tool = coachable.first {
                    let detail = tool.coachLine ?? "You already have \(tool.name), but you haven't used it lately."
                    return .suggest(Suggestion(moment: moment, bucket: bucket, tool: tool, kind: .coach, headline: headline, detail: detail, steps: tool.walkthrough(for: moment.kind, careers: prefs.careers)))
                }
            case .empty:
                break
            }

            let candidates = catalog.tools(in: bucket)
                .filter { $0.kind != .feature && usage($0) == .none && $0.fits(moment.kind) }
                .filter { !prefs.freeOnly || $0.free }
                .filter { requirementsMet($0) }
                .sorted { rank($0, bucket) > rank($1, bucket) }
            if let tool = candidates.first, tool.score(for: bucket.id) >= Self.minimumScore {
                guard newToolAllowed else {
                    reasons.append("you already got a new app this week, and \(bucket.name.lowercased()) can wait")
                    continue
                }
                return .suggest(Suggestion(moment: moment, bucket: bucket, tool: tool, kind: .setUp, headline: headline, detail: bucket.gapLine, steps: tool.walkthrough(for: moment.kind, careers: prefs.careers)))
            }
            reasons.append("no \(prefs.freeOnly ? "free " : "")tool for \(bucket.name) is a strong enough fit")
        }
        return .quiet(reasons.joined(separator: ", and ").capitalizedFirst + ".")
    }

    /// The catalog score, nudged up for tools from the AI app the user lives in
    /// and tools for their career, and scaled by what it learned.
    private func rank(_ tool: Tool, _ bucket: Bucket) -> Double {
        let base = tool.score(for: bucket.id) + (tool.hub != nil && tool.hub == prefs.mainHub ? 0.1 : 0) + careerBoost(tool.careers)
        return base * learned.weight(tool.id)
    }

    private func careerBoost(_ careers: [String]?) -> Double {
        guard let careers, !careers.isEmpty else { return 0 }
        return careers.contains(where: prefs.careers.contains) ? 0.15 : 0
    }

    // MARK: Habits

    /// AI apps a workflow can run in, and the catalog tool that stands for each.
    static let hubTools = ["chatgpt": "chatgpt-app", "claude": "claude-app", "gemini": "gemini-app"]

    /// Tips first: a workflow in an app the student already has. A new app only
    /// when nothing they have can do it, and only within the weekly budget.
    func decide(habit match: HabitMatch, moment: Moment, how: String) -> Decision {
        let workflows = catalog.workflows(for: match.habit).filter { !prefs.notForMeWorkflows.contains($0.id) }
        guard !workflows.isEmpty else {
            return .quiet("Nothing in the catalog helps with this habit yet.")
        }

        var best: (score: Double, workflow: Workflow, tool: Tool)?
        for workflow in workflows {
            guard let tool = runner(for: workflow) else { continue }
            let score = workflow.score * learned.weight(workflow.id) + careerBoost(workflow.careers)
            if best == nil || score > best!.score { best = (score, workflow, tool) }
        }

        if let (_, workflow, tool) = best {
            let bucket = Bucket(id: "workflow:\(workflow.id)", name: workflow.name, plural: "tips like this", job: workflow.summary, gapLine: workflow.summary, moments: [moment.kind], symbol: "lightbulb")
            var learnedLine: String?
            if learned.weight(workflow.id) > 1 { learnedLine = "You've used tips like this before, so it ranked higher." }
            if careerBoost(workflow.careers) > 0 || workflow.careerPrompts?.keys.contains(where: prefs.careers.contains) == true {
                learnedLine = "Picked for \(Careers.list(prefs.careers)), from your career goals."
            }
            return .suggest(Suggestion(
                moment: moment,
                bucket: bucket,
                tool: tool,
                kind: .tip,
                headline: match.noticed,
                detail: workflow.summary,
                workflow: workflow,
                prompt: fill(workflow, match),
                how: how,
                learned: learnedLine,
                steps: workflow.steps
            ))
        }

        // Nothing they have can run it. Fall back to the gap rule for its area.
        for workflow in workflows {
            guard let id = workflow.bucket, let bucket = catalog.bucket(id) else { continue }
            if prefs.notForMe.contains(bucket.id) { return .quiet("You said \(bucket.plural) aren't for you.") }
            guard newToolAllowed else { return .quiet("You already got a new app this week, so I'd rather not add another.") }
            let candidates = catalog.tools(in: bucket)
                .filter { $0.kind != .feature && usage($0) == .none && $0.fits(moment.kind) && requirementsMet($0) }
                .filter { !prefs.freeOnly || $0.free }
                .sorted { rank($0, bucket) > rank($1, bucket) }
            if let tool = candidates.first, tool.score(for: bucket.id) >= Self.minimumScore {
                return .suggest(Suggestion(moment: moment, bucket: bucket, tool: tool, kind: .setUp, headline: match.noticed, detail: "None of your apps can do this yet. \(bucket.gapLine)", how: how, steps: tool.walkthrough(for: moment.kind, careers: prefs.careers)))
            }
        }
        return .quiet("None of your apps can do this, and nothing new is a strong enough fit.")
    }

    /// The app the student has that can run this workflow, main AI app first.
    func runner(for workflow: Workflow) -> Tool? {
        var hubs = workflow.hubs
        if let i = hubs.firstIndex(of: prefs.mainHub) { hubs.insert(hubs.remove(at: i), at: 0) }
        for hub in hubs {
            guard let id = Self.hubTools[hub], let tool = catalog.tool(id) else { continue }
            if hub == prefs.mainHub || usage(tool) != .none { return tool }
        }
        for id in workflow.tools ?? [] {
            if let tool = catalog.tool(id), usage(tool) != .none { return tool }
        }
        return nil
    }

    /// Fills the prompt's blanks with what the app saw, on this Mac.
    func fill(_ workflow: Workflow, _ match: HabitMatch) -> String {
        var prompt = workflow.prompt
        let org = match.organization.map(OrgNames.shortOrg) ?? "the company"
        prompt = prompt.replacingOccurrences(of: "{org}", with: org)
        prompt = prompt.replacingOccurrences(of: "{doc}", with: match.topic ?? "draft")
        prompt = prompt.replacingOccurrences(of: "{topic}", with: match.topic ?? "this")
        let role = match.role.map { r -> String in
            let lower = r.lowercased()
            return ("aeiou".contains(lower.first ?? "x") ? "an " : "a ") + lower
        }
        prompt = prompt.replacingOccurrences(of: "{role}", with: role ?? "someone")
        for career in prefs.careers {
            if let extra = workflow.careerPrompts?[career] {
                prompt += " " + extra.replacingOccurrences(of: "{org}", with: org)
                break
            }
        }
        return prompt
    }

    private func requirementsMet(_ tool: Tool) -> Bool {
        guard let id = tool.requires, let required = catalog.tool(id) else { return true }
        return usage(required) != .none
    }

    private func names(_ ids: [String]) -> String {
        let names = ids.compactMap { catalog.tool($0)?.name }
        if names.count <= 2 { return names.joined(separator: " and ") }
        return names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
    }

    static func headline(_ moment: Moment, timing: String) -> String {
        if moment.startDate == nil, let context = moment.context { return context }
        return "\u{201C}\(moment.title)\u{201D} \(timing)."
    }
}

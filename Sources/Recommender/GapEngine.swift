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
                let coachable = ids.compactMap { catalog.tool($0) }
                    .filter { $0.fits(moment.kind) }
                    .filter { $0.kind == .app || $0.kind == .cli || !prefs.freeOnly || $0.free }
                    .sorted { rank($0, bucket) > rank($1, bucket) }
                if let tool = coachable.first {
                    let detail = tool.coachLine ?? "You already have \(tool.name), but you haven't used it lately."
                    return .suggest(Suggestion(moment: moment, bucket: bucket, tool: tool, kind: .coach, headline: headline, detail: detail))
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
                return .suggest(Suggestion(moment: moment, bucket: bucket, tool: tool, kind: .setUp, headline: headline, detail: bucket.gapLine))
            }
            reasons.append("no \(prefs.freeOnly ? "free " : "")tool for \(bucket.name) is a strong enough fit")
        }
        return .quiet(reasons.joined(separator: ", and ").capitalizedFirst + ".")
    }

    /// The catalog score, nudged up for tools from the AI app the user lives in.
    private func rank(_ tool: Tool, _ bucket: Bucket) -> Double {
        tool.score(for: bucket.id) + (tool.hub != nil && tool.hub == prefs.mainHub ? 0.1 : 0)
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

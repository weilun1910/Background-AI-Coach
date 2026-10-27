import SwiftUI

/// A small design system so the prototype doesn't look like default output.
/// One accent (deep teal), one warning tone (amber), one "gap" tone (blue).
enum Theme {
    static let accent = Color(red: 0.05, green: 0.46, blue: 0.43)
    static let warn = Color(red: 0.78, green: 0.45, blue: 0.04)
    static let gap = Color(red: 0.22, green: 0.40, blue: 0.86)
    static let quiet = Color.secondary

    static let surface = Color(nsColor: .windowBackgroundColor)
    static let raised = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color.primary.opacity(0.08)

    static let radius: CGFloat = 14
    static let innerRadius: CGFloat = 10
}

struct Chip: View {
    let text: String
    let color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.13), in: Capsule())
        .foregroundStyle(color)
    }
}

struct StateChip: View {
    let state: BucketState

    var body: some View {
        switch state {
        case .empty: Chip(text: "Gap", color: Theme.gap)
        case .unused: Chip(text: "Unused", color: Theme.warn)
        case .inUse: Chip(text: "Covered", color: Theme.accent)
        case .notForMe: Chip(text: "Off", color: Theme.quiet)
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(.white)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// An SF Symbol in a soft rounded square, or the real app icon when we have it.
struct ToolIcon: View {
    let symbol: String
    var image: NSImage? = nil
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: size, height: size)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }
}

struct InfoLine: View {
    let symbol: String
    let text: String
    var color: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

struct NumberedStep: View {
    let number: Int
    let text: String
    var done = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ZStack {
                Circle()
                    .fill(done ? Theme.accent : Theme.accent.opacity(0.12))
                    .frame(width: 20, height: 20)
                if done {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
            Text(text)
                .font(.callout)
                .foregroundStyle(done ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

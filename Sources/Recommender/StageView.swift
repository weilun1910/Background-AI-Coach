import SwiftUI

// MARK: - Cursor targets

/// Lets the stage find a control, so the pretend cursor can move to it.
/// It has no effect in the real app.
struct StageTargetKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func stageTarget(_ id: String) -> some View {
        anchorPreference(key: StageTargetKey.self, value: .bounds) { [id: $0] }
    }
}

// MARK: - Stage

/// A persona's whole Mac, drawn at 1440 by 900 and scaled to fit the screen.
struct StageView: View {
    @ObservedObject var director: StageDirector
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            // Never zero: before the window has a size, a zero scale crashes AppKit.
            let scale = max(0.05, min(geo.size.width / StageDirector.canvas.width, geo.size.height / StageDirector.canvas.height))
            ZStack {
                Color.black
                canvas
                    .frame(width: StageDirector.canvas.width, height: StageDirector.canvas.height)
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper(color: avatarColor)

            ForEach(director.windows) { window in
                StageWindowView(window: window, director: director)
                    .frame(width: window.frame.width, height: window.frame.height)
                    .offset(x: window.frame.minX, y: window.frame.minY)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }

            DockView(director: director)
                .frame(width: StageDirector.canvas.width, alignment: .center)
                .offset(y: StageDirector.canvas.height - 84)

            StageMenuBar(director: director, model: model)

            if let note = director.note {
                NotificationBanner(note: note)
                    .offset(x: StageDirector.canvas.width - 372, y: 36)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if model.panel != nil {
                PanelView(model: model)
                    .shadow(color: .black.opacity(0.25), radius: 22, y: 10)
                    .offset(x: StageDirector.canvas.width - 396, y: 36)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if director.menuOpen {
                MenuContentView(model: model)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.12)))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                    .allowsHitTesting(false)
                    .offset(x: StageDirector.canvas.width - 520, y: 30)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            if director.captionsOn, let caption = director.caption, director.overlay == nil {
                // Slides left while the menu is open, so it doesn't cover the menu.
                CaptionBar(text: caption)
                    .frame(width: director.menuOpen ? 880 : StageDirector.canvas.width, alignment: .center)
                    .offset(x: director.menuOpen ? 20 : 0, y: StageDirector.canvas.height - 168)
                    .transition(.opacity)
            }

            if director.hintsOn, director.overlay == nil {
                KeyHints(director: director)
                    .offset(x: 16, y: StageDirector.canvas.height - 30)
            }

            if let overlay = director.overlay {
                OverlayView(overlay: overlay, director: director, model: model)
                    .transition(.opacity)
            }
        }
        .frame(width: StageDirector.canvas.width, height: StageDirector.canvas.height, alignment: .topLeading)
        .clipped()
        .overlayPreferenceValue(StageTargetKey.self) { anchors in
            GeometryReader { proxy in
                PretendCursor(pressed: director.cursorPressed)
                    .position(cursorPoint(anchors, proxy))
                    .opacity(director.overlay == nil ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .light)
    }

    private func cursorPoint(_ anchors: [String: Anchor<CGRect>], _ proxy: GeometryProxy) -> CGPoint {
        switch director.cursor {
        case .point(let p):
            return CGPoint(x: p.x + 9, y: p.y + 12)
        case .target(let id):
            guard let anchor = anchors[id] else { return StageDirector.restPoint }
            let rect = proxy[anchor]
            // The arrow's tip sits on the control's center.
            return CGPoint(x: rect.midX + 9, y: rect.midY + 12)
        }
    }

    private var avatarColor: Color {
        guard let persona = director.persona else { return Theme.accent }
        return PersonaColors.color(persona.color)
    }
}

enum PersonaColors {
    static func color(_ name: String) -> Color {
        switch name {
        case "gap": return Theme.gap
        case "warn": return Theme.warn
        case "purple": return Color(red: 0.49, green: 0.33, blue: 0.82)
        case "pink": return Color(red: 0.84, green: 0.29, blue: 0.53)
        default: return Theme.accent
        }
    }
}

// MARK: - Desktop pieces

struct Wallpaper: View {
    let color: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [color.opacity(0.85), color.opacity(0.45), Color(red: 0.96, green: 0.94, blue: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.white.opacity(0.18)).frame(width: 900).offset(x: 520, y: -260).blur(radius: 60)
            Circle().fill(color.opacity(0.35)).frame(width: 700).offset(x: -420, y: 320).blur(radius: 80)
        }
        .frame(width: StageDirector.canvas.width, height: StageDirector.canvas.height)
    }
}

struct StageMenuBar: View {
    @ObservedObject var director: StageDirector
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo").font(.system(size: 14, weight: .medium))
            Text(director.frontAppName).font(.system(size: 13, weight: .bold))
            ForEach(["File", "Edit", "View", "Window", "Help"], id: \.self) { item in
                Text(item).font(.system(size: 13))
            }
            Spacer()
            ZStack {
                if director.menuOpen {
                    RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.12)).frame(width: 28, height: 20)
                }
                Image(systemName: model.pending != nil ? "sparkles" : "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.pending != nil ? Theme.accent : Color.black.opacity(0.85))
            }
            .frame(width: 28, height: 22)
            .stageTarget("menubar-sparkle")
            Image(systemName: "battery.75percent").font(.system(size: 14))
            Image(systemName: "wifi").font(.system(size: 13, weight: .semibold))
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
            Image(systemName: "switch.2").font(.system(size: 13, weight: .semibold))
            Text(Clock.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.horizontal, 18)
        .frame(width: StageDirector.canvas.width, height: 28)
        .background(Color.white.opacity(0.55))
    }
}

struct AppIcon: View {
    let key: String
    var size: CGFloat = 52

    var body: some View {
        if let image = StageApps.icon(key) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            let info = StageApps.info(key)
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(colors: [info.tint.opacity(0.85), info.tint], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: info.symbol).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white))
                .frame(width: size * 0.86, height: size * 0.86)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
    }
}

struct DockView: View {
    @ObservedObject var director: StageDirector

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(director.dockKeys, id: \.self) { key in
                VStack(spacing: 3) {
                    AppIcon(key: key, size: 54)
                        .offset(y: director.bouncing == key ? -18 : 0)
                        .stageTarget("dock-\(key)")
                    Circle()
                        .fill(Color.black.opacity(director.windows.contains { $0.app == key } ? 0.55 : 0))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 0.8))
    }
}

struct NotificationBanner: View {
    let note: StageNote

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIcon(key: note.app, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(note.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text("now").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(note.body).font(.system(size: 13)).foregroundStyle(.primary.opacity(0.85))
            }
        }
        .padding(12)
        .frame(width: 356)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}

struct CaptionBar: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: 840)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct KeyHints: View {
    @ObservedObject var director: StageDirector

    var body: some View {
        HStack(spacing: 14) {
            Text("\u{2192} next   \u{2190} back   1-5 persona   N notes   H hide keys   R restart   Esc window")
            Text("\(min(director.beatIndex, director.beatCount)) / \(director.beatCount)").monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.35), in: Capsule())
    }
}

struct PretendCursor: View {
    let pressed: Bool

    var body: some View {
        ZStack {
            Image(systemName: "cursorarrow")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(.white)
            Image(systemName: "cursorarrow")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.black)
        }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .scaleEffect(pressed ? 0.82 : 1)
    }
}

// MARK: - Overlays

struct OverlayView: View {
    let overlay: StageOverlay
    @ObservedObject var director: StageDirector
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(overlay == .intro || overlay == .end ? 0.55 : 0.85)
            switch overlay {
            case .intro:
                if let persona = director.persona { intro(persona) }
            case .transition(let text):
                Text(text)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            case .end:
                if let persona = director.persona { end(persona) }
            }
        }
        .frame(width: StageDirector.canvas.width, height: StageDirector.canvas.height)
    }

    private func intro(_ p: Persona) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Avatar(persona: p, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(p.tagline).font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            Text(p.about).font(.system(size: 17)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("On their Mac")
                FlowLayout(spacing: 8) {
                    ForEach(p.apps, id: \.self) { app in
                        HStack(spacing: 6) {
                            if let key = StageApps.key(forPersonaApp: app.name) { AppIcon(key: key, size: 22) }
                            Text(app.name == "zoom.us" ? "Zoom" : app.name).font(.system(size: 14, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
            }
            InfoLine(symbol: "lightbulb", text: "What this day shows: \(p.shows)", color: Theme.accent)
                .font(.system(size: 16))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Text("A made-up student. Their apps, calendar and clock are pretend. The app deciding what to show is the real one.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Click once, then press \u{2192} to start").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(30)
        .frame(width: 700)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
    }

    private func end(_ p: Persona) -> some View {
        let shown = director.results.filter { $0.tone == .card }.count
        let held = director.results.filter { $0.tone == .held }.count
        let quiet = director.results.filter { $0.tone == .quiet }.count
        let nextIndex = director.personaIndex + 1
        let next = director.demo.personas.indices.contains(nextIndex) ? director.demo.personas[nextIndex] : nil
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Avatar(persona: p, size: 52)
                Text("End of \(p.name)'s day").font(.system(size: 30, weight: .semibold, design: .rounded))
            }
            HStack(spacing: 12) {
                stat("\(shown)", shown == 1 ? "card shown" : "cards shown", Theme.accent)
                stat("\(held)", held == 1 ? "card held" : "cards held", Theme.warn)
                stat("\(quiet)", quiet == 1 ? "time it stayed quiet" : "times it stayed quiet", .secondary)
            }
            Text(p.shows).font(.system(size: 17)).fixedSize(horizontal: false, vertical: true)
            if let next {
                Text("Press \(nextIndex + 1) for \(next.name), \(next.tagline.prefix(1).lowercased() + next.tagline.dropFirst()).")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else {
                Text("That's all five. Press 1 to start again.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(30)
        .frame(width: 640, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

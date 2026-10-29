import SwiftUI

// MARK: - Window chrome

struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
        }
    }
}

/// A macOS window frame: title bar, traffic lights, rounded corners, shadow.
struct FakeWindow<Content: View>: View {
    let title: String
    var dark = false
    var titleBar: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                (titleBar ?? (dark ? Color(white: 0.16) : Color(white: 0.94)))
                HStack {
                    TrafficLights()
                    Spacer()
                }
                .padding(.leading, 13)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(dark ? Color.white.opacity(0.8) : Color.black.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(height: 32)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(dark ? Color(white: 0.12) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.black.opacity(0.2), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.28), radius: 26, y: 14)
    }
}

/// Grey bars standing in for text that doesn't need to be read.
struct TextLines: View {
    var count = 3
    var color = Color.black.opacity(0.1)
    var height: CGFloat = 8
    var widths: [CGFloat] = [1, 0.92, 0.75, 0.88, 0.6]

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: height * 0.9) {
                ForEach(0..<count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(color)
                        .frame(width: geo.size.width * widths[i % widths.count], height: height)
                }
            }
        }
        .frame(height: CGFloat(count) * height * 1.9)
    }
}

struct StageWindowView: View {
    let window: StageWindow
    @ObservedObject var director: StageDirector

    var body: some View {
        switch window.app {
        case "calendar": CalendarApp(director: director)
        case "word": WordApp(window: window)
        case "powerpoint", "keynote": SlidesApp(window: window)
        case "zoom": ZoomApp(window: window, persona: director.persona?.name ?? "You")
        case "figma": FigmaApp(window: window)
        case "vscode", "cursor": CodeApp(window: window)
        case "safari": SafariApp(window: window, director: director)
        case "granola": GranolaApp(window: window)
        case "chatgpt", "claude", "gemini": ChatApp(window: window)
        default: FakeWindow(title: window.title) { Color.white }
        }
    }
}

// MARK: - Calendar

struct CalendarApp: View {
    @ObservedObject var director: StageDirector
    private let firstHour = 8
    private let lastHour = 24
    private let hourHeight: CGFloat = 32

    var body: some View {
        FakeWindow(title: "Calendar") {
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(Clock.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.system(size: 22, weight: .bold))
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(["Day", "Week", "Month"], id: \.self) { label in
                                Text(label)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(label == "Day" ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(2)
                        .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    Divider()
                    ScrollView(.vertical, showsIndicators: false) {
                        dayGrid
                    }
                    .disabled(true)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Clock.now.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 13, weight: .semibold))
            miniMonth
            Divider()
            Text("Calendars").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ForEach([("Yale", Color.blue), ("Recruiting", Color.orange), ("Personal", Color.green)], id: \.0) { item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(item.1).frame(width: 12, height: 12)
                    Text(item.0).font(.system(size: 12))
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 180)
        .background(Color(white: 0.965))
    }

    private var miniMonth: some View {
        let cal = Calendar.current
        let today = cal.component(.day, from: Clock.now)
        let range = cal.range(of: .day, in: .month, for: Clock.now) ?? 1..<31
        let first = cal.date(from: cal.dateComponents([.year, .month], from: Clock.now)) ?? Clock.now
        let lead = (cal.component(.weekday, from: first) + 6) % 7
        let cells = Array(repeating: 0, count: lead) + Array(range)
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 3), count: 7), spacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                Text(day == 0 ? "" : "\(day)")
                    .font(.system(size: 10, weight: day == today ? .bold : .regular))
                    .foregroundStyle(day == today ? .white : .primary)
                    .frame(width: 18, height: 18)
                    .background(day == today ? Color.red : Color.clear, in: Circle())
            }
        }
    }

    private var dayGrid: some View {
        let events = director.calendarEvents()
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(firstHour..<lastHour, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 8) {
                        Text(hourLabel(hour))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                            .offset(y: -6)
                        Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                    }
                    .frame(height: hourHeight, alignment: .top)
                }
            }
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                let color: Color = [Color.blue, .orange, .green, .purple][index % 4]
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(event.start.formatted(date: .omitted, time: .shortened)).font(.system(size: 10))
                }
                .foregroundStyle(color.opacity(0.95))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(width: 440, height: max(22, CGFloat(event.minutes) / 60 * hourHeight - 2), alignment: .topLeading)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
                .offset(x: 60, y: y(for: event.start))
            }
            HStack(spacing: 0) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Rectangle().fill(Color.red).frame(height: 1.5)
            }
            .offset(x: 48, y: y(for: Clock.now) - 4)
        }
        .padding(.top, 10)
        .padding(.trailing, 14)
        .offset(y: -max(0, y(for: Clock.now) - 140))
    }

    private func y(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let hour = CGFloat(cal.component(.hour, from: date)) + CGFloat(cal.component(.minute, from: date)) / 60
        return max(0, (hour - CGFloat(firstHour)) * hourHeight)
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 || hour == 24 ? "AM" : "PM")"
    }
}

// MARK: - Word

struct WordApp: View {
    let window: StageWindow
    private let blue = Color(red: 0.16, green: 0.34, blue: 0.64)

    var body: some View {
        FakeWindow(title: window.title, titleBar: blue) {
            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    ForEach(["Home", "Insert", "Draw", "Design", "Layout", "References", "Review", "View"], id: \.self) { tab in
                        Text(tab)
                            .font(.system(size: 12, weight: tab == "Home" ? .semibold : .regular))
                            .foregroundStyle(tab == "Home" ? blue : .primary.opacity(0.8))
                            .overlay(alignment: .bottom) {
                                if tab == "Home" { Rectangle().fill(blue).frame(height: 2).offset(y: 6) }
                            }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                HStack(spacing: 14) {
                    Text("Aptos (Body)").font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 3).background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                    Text("12").font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 3).background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                    ForEach(["bold", "italic", "underline", "text.alignleft", "list.bullet", "paintbrush"], id: \.self) { icon in
                        Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.75))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                Divider()
                HStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        Color(white: 0.93)
                        page.padding(.top, 22)
                    }
                    if window.flag == "grammarly" { grammarlyPanel }
                }
            }
        }
    }

    private var page: some View {
        let doc = StageContent.document(window.detail)
        return VStack(alignment: .leading, spacing: 12) {
            Text(doc.title).font(.system(size: 15, weight: .semibold))
            ForEach(Array(doc.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .underline(window.flag == "grammarly" && (paragraph.contains("very interested") || paragraph.contains("passionate")), color: .red)
            }
            Spacer()
        }
        .padding(46)
        .frame(width: 520, height: 640, alignment: .topLeading)
        .background(Color.white)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private var grammarlyPanel: some View {
        let green = Color(red: 0.08, green: 0.6, blue: 0.45)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(green).font(.system(size: 18))
                Text("Grammarly").font(.system(size: 14, weight: .bold))
                Spacer()
                Text("2 suggestions").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach([("Engagement", "\u{201C}very interested\u{201D} is overused. Say what drew you to trading."),
                     ("Clarity", "\u{201C}passionate about learning\u{201D} is generic. Name something you learned.")], id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(green)
                    Text(item.1).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.08)))
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 230)
        .background(Color(red: 0.95, green: 0.98, blue: 0.97))
        .transition(.move(edge: .trailing))
    }
}

// MARK: - Slides

struct SlidesApp: View {
    let window: StageWindow

    private var isKeynote: Bool { window.app == "keynote" }
    private var accent: Color { isKeynote ? Color(red: 0.1, green: 0.45, blue: 0.95) : Color(red: 0.77, green: 0.29, blue: 0.17) }

    var body: some View {
        FakeWindow(title: window.title, titleBar: isKeynote ? nil : accent) {
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    ForEach(isKeynote ? ["plus.rectangle", "play.fill", "table", "chart.bar", "textformat", "square.on.circle", "photo"] : ["plus.rectangle", "textformat", "square.on.circle", "photo", "chart.bar", "play.fill"], id: \.self) { icon in
                        Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.primary.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color(white: 0.97))
                Divider()
                HStack(spacing: 0) {
                    VStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { n in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white)
                                    .frame(width: 120, height: 68)
                                    .overlay(VStack(alignment: .leading, spacing: 5) {
                                        RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.5)).frame(width: 60, height: 5)
                                        TextLines(count: 2, height: 3)
                                    }.padding(10))
                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(n == 1 ? accent : Color.black.opacity(0.1), lineWidth: n == 1 ? 2 : 1))
                                Text("\(n)").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(14)
                    .frame(width: 160)
                    .background(Color(white: 0.95))
                    ZStack {
                        Color(white: 0.88)
                        slide
                    }
                }
            }
        }
    }

    private var slide: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(window.title.replacingOccurrences(of: ".pptx", with: "").replacingOccurrences(of: ".key", with: ""))
                .font(.system(size: 30, weight: .bold))
            Rectangle().fill(accent).frame(width: 80, height: 4)
            Text(isKeynote ? "Site, massing and the path through the library" : "Why the market is smaller than it looks")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accent.opacity(0.12 + Double(i) * 0.1))
                        .frame(height: 110)
                }
            }
        }
        .padding(36)
        .frame(width: 640, height: 360, alignment: .topLeading)
        .background(Color.white)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}

// MARK: - Zoom

struct ZoomApp: View {
    let window: StageWindow
    let persona: String

    var body: some View {
        let others = (window.detail ?? "Sam,Priya,Jordan").split(separator: ",").map(String.init)
        let people = [persona] + others
        let colors: [Color] = [Color(red: 0.84, green: 0.29, blue: 0.53), .blue, .orange, .teal]
        return FakeWindow(title: "Zoom Meeting", dark: true) {
            VStack(spacing: 0) {
                HStack {
                    Label(window.title, systemImage: "lock.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Label("View", systemImage: "square.grid.2x2").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                TimelineView(.periodic(from: .now, by: 1.6)) { context in
                    let speaker = Int(context.date.timeIntervalSinceReferenceDate / 1.6) % people.count
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Array(people.enumerated()), id: \.offset) { index, name in
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.2))
                                Circle()
                                    .fill(colors[index % colors.count])
                                    .frame(width: 88, height: 88)
                                    .overlay(Text(String(name.prefix(1))).font(.system(size: 38, weight: .semibold)).foregroundStyle(.white))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                HStack(spacing: 4) {
                                    Image(systemName: index == speaker ? "mic.fill" : "mic.slash.fill").font(.system(size: 10))
                                    Text(index == 0 ? "\(name) (me)" : name).font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                            }
                            .frame(height: 248)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(index == speaker ? Color.green : Color.clear, lineWidth: 3))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Spacer(minLength: 0)
                HStack(spacing: 26) {
                    ForEach([("mic.fill", "Mute"), ("video.fill", "Stop Video"), ("person.2.fill", "Participants"), ("message.fill", "Chat"), ("square.and.arrow.up.fill", "Share"), ("record.circle", "Record")], id: \.1) { item in
                        VStack(spacing: 4) {
                            Image(systemName: item.0).font(.system(size: 17))
                            Text(item.1).font(.system(size: 10))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Text("Leave")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 7))
                        .stageTarget("zoom-leave")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Color(white: 0.1))
            }
        }
    }
}

// MARK: - Figma

struct FigmaApp: View {
    let window: StageWindow
    private let purple = Color(red: 0.6, green: 0.35, blue: 0.95)

    var body: some View {
        FakeWindow(title: "\(window.title) - Figma") {
            HStack(spacing: 0) {
                layers
                Divider()
                ZStack {
                    Color(white: 0.9)
                    canvas
                    toolbar
                        .padding(.bottom, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                Divider()
                if window.flag == "make" { makePanel } else { designPanel }
            }
        }
    }

    private var layers: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Layers").font(.system(size: 12, weight: .semibold))
            ForEach(["Board 1: Site", "Board 2: Massing", "Board 3: Section", "Plan / Level 1", "Notes"], id: \.self) { layer in
                HStack(spacing: 6) {
                    Image(systemName: layer.hasPrefix("Board") ? "number" : "square.dashed").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(layer).font(.system(size: 11.5))
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 190)
        .background(Color.white)
    }

    private var canvas: some View {
        HStack(spacing: 28) {
            board(title: "Board 1: Site") {
                ZStack {
                    Rectangle().fill(Color.green.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.75)).frame(width: 90, height: 60).offset(x: -10, y: 8)
                    Path { p in p.move(to: CGPoint(x: 0, y: 150)); p.addLine(to: CGPoint(x: 230, y: 40)) }.stroke(Color.gray, lineWidth: 6)
                    Circle().stroke(Color.orange, lineWidth: 2).frame(width: 40).offset(x: 60, y: -50)
                }
            }
            board(title: "Board 2: Massing") {
                ZStack {
                    Rectangle().fill(Color.white)
                    VStack(spacing: 6) {
                        HStack(spacing: 6) { block(60, 40); block(40, 70) }
                        HStack(spacing: 6) { block(110, 30) }
                    }
                }
            }
        }
        .offset(y: -30)
    }

    private func block(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.25)).frame(width: w, height: h).overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.blue.opacity(0.6)))
    }

    private func board<Inner: View>(title: String, @ViewBuilder inner: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            inner()
                .frame(width: 240, height: 180)
                .clipped()
                .background(Color.white)
                .overlay(Rectangle().strokeBorder(title.hasPrefix("Board 1") ? purple : Color.clear, lineWidth: 1.5))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            ForEach(["cursorarrow", "number", "square", "pencil", "textformat", "bubble.left"], id: \.self) { icon in
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(icon == "cursorarrow" ? .white : .primary.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(icon == "cursorarrow" ? purple : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private var designPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Design").font(.system(size: 12, weight: .semibold))
                Text("Prototype").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(["Frame", "Layout", "Fill", "Stroke", "Effects", "Export"], id: \.self) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section).font(.system(size: 11, weight: .semibold))
                    TextLines(count: 1, height: 14, widths: [0.9])
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 220)
        .background(Color.white)
    }

    private var makePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars").foregroundStyle(purple)
                Text("Figma Make").font(.system(size: 13, weight: .bold))
            }
            Text("Turn Board 1 into a clickable walkthrough: start at the site, then tap through to the massing.")
                .font(.system(size: 12))
                .padding(10)
                .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Building your prototype...").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            RoundedRectangle(cornerRadius: 8)
                .fill(purple.opacity(0.08))
                .frame(height: 160)
                .overlay(VStack(spacing: 8) {
                    Image(systemName: "rectangle.and.hand.point.up.left").font(.system(size: 28)).foregroundStyle(purple)
                    Text("Preview").font(.system(size: 11)).foregroundStyle(.secondary)
                })
            Spacer()
        }
        .padding(14)
        .frame(width: 240)
        .background(Color.white)
        .transition(.move(edge: .trailing))
    }
}

// MARK: - Code editors

struct CodeApp: View {
    let window: StageWindow

    private var isCursor: Bool { window.app == "cursor" }

    var body: some View {
        FakeWindow(title: "\(window.title) - \(isCursor ? "Cursor" : "Visual Studio Code")", dark: true) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(spacing: 18) {
                        ForEach(["doc.on.doc", "magnifyingglass", "arrow.triangle.branch", "play", "square.grid.2x2"], id: \.self) { icon in
                            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(.white.opacity(icon == "doc.on.doc" ? 0.9 : 0.45))
                        }
                        Spacer()
                    }
                    .padding(.top, 14)
                    .frame(width: 44)
                    .background(Color(white: 0.16))
                    explorer
                    editor
                    if window.flag == "agent" { agentPanel }
                }
                HStack(spacing: 14) {
                    Label("main", systemImage: "arrow.triangle.branch")
                    Text("Python 3.12")
                    Spacer()
                    Text("Ln 11, Col 22")
                }
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(isCursor ? Color(white: 0.2) : Color(red: 0.0, green: 0.48, blue: 0.8))
            }
        }
    }

    private var explorer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("EXPLORER").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            ForEach([("folder", "data"), ("doc", "rt_trials.csv"), ("doc.text", "analysis.py"), ("doc.text", "plots.py"), ("doc", "README.md")], id: \.1) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.0).font(.system(size: 11))
                    Text(item.1).font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(item.1 == "analysis.py" ? 0.95 : 0.65))
                .padding(.leading, item.1 == "rt_trials.csv" ? 14 : 0)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 180)
        .background(Color(white: 0.14))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(.yellow)
                Text("analysis.py").font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(white: 0.12))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(StageContent.codeLines(agent: window.flag == "agent").enumerated()), id: \.offset) { index, tokens in
                    HStack(spacing: 0) {
                        Text("\(index + 1)").foregroundStyle(.white.opacity(0.3)).frame(width: 28, alignment: .trailing).padding(.trailing, 14)
                        ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                            Text(token.0).foregroundStyle(color(token.1))
                        }
                    }
                    .font(.system(size: 12.5, design: .monospaced))
                }
                Spacer()
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.11))
    }

    private var agentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agent").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Text("Move the data loading into a function and explain each change.")
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(10)
                .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Label("Read analysis.py", systemImage: "checkmark").foregroundStyle(.green)
                Label("Edited analysis.py (+6, -2)", systemImage: "checkmark").foregroundStyle(.green)
                Text("I moved the CSV loading and the 2000 ms cutoff into load_trials(), so plots.py can reuse it.")
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11.5))
            Spacer()
        }
        .padding(12)
        .frame(width: 250)
        .background(Color(white: 0.15))
        .transition(.move(edge: .trailing))
    }

    private func color(_ tone: CodeTone) -> Color {
        switch tone {
        case .plain: return Color(white: 0.85)
        case .keyword: return Color(red: 0.77, green: 0.53, blue: 0.75)
        case .string: return Color(red: 0.81, green: 0.57, blue: 0.47)
        case .comment: return Color(red: 0.42, green: 0.6, blue: 0.33)
        case .number: return Color(red: 0.71, green: 0.81, blue: 0.66)
        case .function: return Color(red: 0.86, green: 0.86, blue: 0.67)
        }
    }
}

// MARK: - Safari

struct SafariApp: View {
    let window: StageWindow
    @ObservedObject var director: StageDirector

    private var page: String { window.detail ?? "" }

    private var domain: String {
        if page == "notebook" { return "notebook.google.com" }
        if page == "ocs" { return "ocs.yale.edu/interviewing" }
        if page.hasPrefix("article:") { return "canvas.yale.edu/courses/readings" }
        if page.hasPrefix("web:") { return String(page.dropFirst(4).split(separator: "|").first ?? "") }
        if page.hasPrefix("site:"), let tool = director.model.catalog.tool(String(page.dropFirst(5))),
           let host = URL(string: tool.setup.url ?? tool.source)?.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return "yale.edu"
    }

    var body: some View {
        FakeWindow(title: "") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "sidebar.left").foregroundStyle(.secondary)
                    Image(systemName: "chevron.left").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary.opacity(0.5))
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(domain).font(.system(size: 12.5))
                    }
                    .frame(width: 380, height: 26)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    Spacer()
                    Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
                    Image(systemName: "plus").foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .background(Color(white: 0.94))
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if page == "notebook" {
            NotebookPage()
        } else if page == "ocs" {
            SimpleSitePage(brand: "Yale Office of Career Strategies", headline: "Prepare for your interview", blurb: "Practice common questions, research the firm, and book a mock interview with an advisor.", accent: Color(red: 0.0, green: 0.21, blue: 0.42), symbol: "building.columns")
        } else if page.hasPrefix("article:") {
            ArticlePage(title: String(page.dropFirst(8)))
        } else if page.hasPrefix("web:") {
            let parts = page.dropFirst(4).split(separator: "|").map(String.init)
            SimpleSitePage(brand: parts.last ?? "", headline: parts.last ?? "", blurb: "Search results, saved threads and sources.", accent: .teal, symbol: "globe")
        } else if page.hasPrefix("site:"), let tool = director.model.catalog.tool(String(page.dropFirst(5))) {
            ToolSitePage(tool: tool)
        } else {
            Color.white
        }
    }
}

struct ArticlePage: View {
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("COURSE READING").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 26, weight: .semibold, design: .serif)).fixedSize(horizontal: false, vertical: true)
                Text("Posted to Canvas, week 7").font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                ForEach(Array(StageContent.readingParagraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph).font(.system(size: 14, design: .serif)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
                TextLines(count: 5, height: 9)
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 40)
        }
        .disabled(true)
    }
}

struct NotebookPage: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sources").font(.system(size: 13, weight: .semibold))
                ForEach(["Reading 1.pdf", "Reading 2.pdf", "Field study.pdf"], id: \.self) { source in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.square.fill").foregroundStyle(.blue)
                        Image(systemName: "doc.text").foregroundStyle(.red)
                        Text(source).font(.system(size: 12))
                    }
                }
                Spacer()
            }
            .padding(14)
            .frame(width: 200)
            .background(Color(white: 0.97))
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Gemini Notebook").font(.system(size: 18, weight: .semibold))
                Text("3 sources").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("What do these readings disagree about?")
                    .font(.system(size: 13))
                    .padding(10)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("They disagree about whether design principles come before or after the work. Reading 1 says before [1]. Reading 2 says most are written after, to explain choices already made [2].")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(20)
        }
    }
}

struct SimpleSitePage: View {
    let brand: String
    let headline: String
    let blurb: String
    let accent: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(brand).font(.system(size: 14, weight: .semibold))
                Spacer()
                TextLines(count: 1, color: .white.opacity(0.35), height: 8, widths: [1]).frame(width: 220)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(accent)
            VStack(alignment: .leading, spacing: 14) {
                Text(headline).font(.system(size: 30, weight: .bold))
                Text(blurb).font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.12)).frame(height: 90)
                            TextLines(count: 2, height: 7)
                        }
                    }
                }
            }
            .padding(36)
            Spacer()
        }
    }
}

struct ToolSitePage: View {
    let tool: Tool

    var body: some View {
        let accent = PersonaColors.color("accent")
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: tool.symbol).foregroundStyle(accent)
                Text(tool.name).font(.system(size: 15, weight: .bold))
                Spacer()
                Text("Log in").font(.system(size: 12))
                Text("Get started")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accent, in: Capsule())
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            Divider()
            VStack(spacing: 18) {
                Text(tool.id == "big-interview" ? "Practice for your interview" : tool.name)
                    .font(.system(size: 34, weight: .bold))
                Text(tool.why)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
                if tool.id == "big-interview" {
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.15))
                            .frame(width: 340, height: 200)
                            .overlay(VStack(spacing: 8) {
                                Image(systemName: "video.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.8))
                                Text("Recording 0:42").font(.system(size: 12)).foregroundStyle(.red)
                            })
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QUESTION 1 OF 5").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                            Text("Tell me about a time you changed someone's mind.").font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                            Text("Fellowship and research interviews").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .frame(width: 220, alignment: .leading)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 560, height: 220)
                        .overlay(Image(systemName: tool.symbol).font(.system(size: 46)).foregroundStyle(accent))
                }
            }
            .padding(.top, 40)
            Spacer()
        }
    }
}

// MARK: - Granola

struct GranolaApp: View {
    let window: StageWindow
    private let green = Color(red: 0.36, green: 0.55, blue: 0.2)

    var body: some View {
        FakeWindow(title: "Granola") {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Coming up").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text(window.detail ?? "Meeting").font(.system(size: 12.5, weight: .medium)).lineLimit(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    Text("Earlier").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6)
                    TextLines(count: 3, height: 8)
                    Spacer()
                }
                .padding(14)
                .frame(width: 200)
                .background(Color(red: 0.97, green: 0.97, blue: 0.95))
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(window.detail ?? "Meeting").font(.system(size: 22, weight: .semibold))
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text(window.flag == "live" ? "Listening" : "Start").font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(green.opacity(0.15), in: Capsule())
                    }
                    Text("Your notes").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\u{2022} Started on the strategy team after Yale, now in healthcare").font(.system(size: 13))
                        Text("\u{2022} Ask about the case interview format").font(.system(size: 13))
                        Text("\u{2022} Follow up: intro to the recruiting lead").font(.system(size: 13))
                    }
                    Text("Transcript").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 8)
                    TextLines(count: 4, height: 8)
                    Spacer()
                }
                .padding(24)
            }
        }
    }
}

// MARK: - AI chat apps

struct ChatApp: View {
    let window: StageWindow

    private var style: (background: Color, sidebar: Color, accent: Color, name: String) {
        switch window.app {
        case "claude": return (Color(red: 0.98, green: 0.97, blue: 0.95), Color(red: 0.95, green: 0.93, blue: 0.89), Color(red: 0.85, green: 0.47, blue: 0.34), "Claude")
        case "gemini": return (.white, Color(red: 0.95, green: 0.96, blue: 0.99), Color(red: 0.26, green: 0.45, blue: 0.95), "Gemini")
        default: return (.white, Color(white: 0.97), .black, "ChatGPT")
        }
    }

    var body: some View {
        FakeWindow(title: style.name) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                ZStack {
                    style.background
                    if window.flag == "voice" { voice } else { conversation }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("New chat", systemImage: "square.and.pencil").font(.system(size: 12.5, weight: .medium))
            if let project = window.flag, project.hasPrefix("project:") {
                Text("PROJECT").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).padding(.top, 6)
                Label(String(project.dropFirst(8)), systemImage: "folder.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(style.accent)
                ForEach(["Syllabus.pdf", "Reading 1.pdf", "Reading 2.pdf"], id: \.self) { file in
                    Label(file, systemImage: "doc.text").font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.leading, 10)
                }
            }
            Text("Recent").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).padding(.top, 6)
            TextLines(count: 5, height: 8)
            Spacer()
        }
        .padding(14)
        .frame(width: 210)
        .background(style.sidebar)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            if window.flag == "guided" {
                Label("Guided Learning", systemImage: "graduationcap.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(style.accent.opacity(0.1), in: Capsule())
            } else if let connector = window.flag, connector.hasPrefix("connector:") {
                Label("\(connector.dropFirst(10)) connector on", systemImage: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(style.accent.opacity(0.1), in: Capsule())
            }
            Text(window.detail ?? "Hi")
                .font(.system(size: 14))
                .padding(12)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(StageContent.chatReply(window.app, flag: window.flag).enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            if window.flag == "guided" {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["Working memory holds a few items for seconds.", "Long-term memory has no limit at all.", "They're the same system."], id: \.self) { option in
                        Text(option)
                            .font(.system(size: 13))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.1)))
                    }
                }
            }
            Spacer()
            HStack {
                Text("Ask anything").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)).foregroundStyle(style.accent)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.black.opacity(0.12)))
        }
        .padding(26)
    }

    private var voice: some View {
        VStack(spacing: 26) {
            Spacer()
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.6, green: 0.85, blue: 1.0), Color(red: 0.15, green: 0.45, blue: 0.95)], center: .center, startRadius: 10, endRadius: 120))
                    .frame(width: 200, height: 200)
                    .scaleEffect(1 + 0.05 * sin(t * 3))
            }
            Text(window.detail ?? "")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 28) {
                Image(systemName: "mic.fill").font(.system(size: 20)).frame(width: 52, height: 52).background(Color.black.opacity(0.06), in: Circle())
                Image(systemName: "xmark").font(.system(size: 20)).frame(width: 52, height: 52).background(Color.black.opacity(0.06), in: Circle())
            }
            Spacer()
        }
    }
}

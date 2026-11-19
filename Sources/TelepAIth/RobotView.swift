import SwiftUI

// Robot-büyücü: gövdesiz, havada süzülen kafa ve büyücü şapkası.
// Kafa çizim alanı 100 × 110 nokta; tüm konumlar bu alana göre.

struct AvatarView: View {
    @ObservedObject var avatar: RobotAvatar

    var body: some View {
        let frameAlignment: Alignment = avatar.bubbleBelow
            ? (avatar.alignLeft ? .topLeading : .topTrailing)
            : (avatar.alignLeft ? .bottomLeading : .bottomTrailing)
        return ZStack {
            AvatarStage(model: avatar.current, alignLeft: avatar.alignLeft, bubbleBelow: avatar.bubbleBelow)
                .id(avatar.current.source)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
        .padding(Layout.margin)
        .frame(width: Layout.windowSize.width, height: Layout.windowSize.height, alignment: frameAlignment)
    }
}

struct AvatarStage: View {
    @ObservedObject var model: RobotModel
    let alignLeft: Bool
    let bubbleBelow: Bool

    var body: some View {
        VStack(alignment: alignLeft ? .leading : .trailing, spacing: 2) {
            if bubbleBelow {
                head
                bubble
            } else {
                bubble
                head
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.bubbleText)
    }

    @ViewBuilder
    private var bubble: some View {
        if let text = model.bubbleText {
            BubbleView(title: model.theme.displayName,
                       subtitle: model.bubbleSubtitle,
                       text: text,
                       color: Color(nsColor: model.theme.color),
                       tailOnTop: bubbleBelow,
                       tailLeading: alignLeft)
                .transition(.opacity)
        }
    }

    private var head: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            HeadFigure(model: model,
                       time: context.date.timeIntervalSinceReferenceDate,
                       look: alignLeft ? 2.5 : -2.5)
        }
        .frame(width: Layout.headSize.width, height: Layout.headSize.height)
    }
}

// MARK: - Konuşma balonu

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct BubbleView: View {
    let title: String
    let subtitle: String?
    let text: String
    let color: Color
    let tailOnTop: Bool
    let tailLeading: Bool

    private var fill: Color { Color(nsColor: .windowBackgroundColor).opacity(0.97) }

    var body: some View {
        VStack(alignment: tailLeading ? .leading : .trailing, spacing: 0) {
            if tailOnTop {
                tail.rotationEffect(.degrees(180))
            }
            card
            if !tailOnTop {
                tail
            }
        }
        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
    }

    // Kuyruk kafanın ortasını göstersin (kafa merkezi kenardan 50 nokta içeride)
    private var tail: some View {
        BubbleTail()
            .fill(fill)
            .frame(width: 14, height: 8)
            .padding(tailLeading ? .leading : .trailing, 43)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
                if let subtitle = subtitle {
                    Text("· " + subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 220, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Kafa (şapkasız, nokta matris gözlü)

struct HeadFigure: View {
    let model: RobotModel
    let time: TimeInterval
    let look: CGFloat

    var body: some View {
        let state = model.state
        let base = model.theme.color
        let eyeColor = Color(nsColor: base.mix(.white, 0.18))   // gözler uygulamanın renginde
        let accent = Color(nsColor: base.mix(.white, 0.55))
        let hop = hopHeight
        let float = floatOffset(state)
        let shake = shakeOffset
        let skin = SkinStore.shared.image(source: model.source, state: state)
        let lift = hop - float

        return ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.14))
                .frame(width: Swift.max(24, 58 - lift * 1.5), height: 6)
                .position(x: 50, y: 96)

            Group {
                if let skin = skin {
                    Image(nsImage: skin)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 96, height: 90)
                        .position(x: 50, y: 48)
                } else {
                    FaceView(state: state, mood: model.mood, time: time, look: look, eyeColor: eyeColor)
                }
            }
            .rotationEffect(.degrees(headTilt(state)), anchor: UnitPoint(x: 0.5, y: 0.9))
            .offset(x: shake, y: -lift)

            if state == .thinking || state == .delegating || state == .reading || state == .searching {
                WavesView(time: time, color: accent)
                    .offset(x: shake, y: -lift)
            }
            if isCelebrating || state == .editing || model.mood == .party || model.mood == .proud {
                SparklesView(time: time, color: accent, radius: state == .editing ? 40 : 50)
                    .offset(y: -lift)
            }
            if state == .sleeping {
                ZzzView(time: time)
            }
        }
        .frame(width: 100, height: 100)
    }

    // Havada süzülme
    private func floatOffset(_ state: RobotState) -> CGFloat {
        if model.mood == .scared { return CGFloat(sin(time * 40)) * 1.2 }
        switch state {
        case .idle: return CGFloat(sin(time * 1.6)) * 2.5
        case .running: return CGFloat(sin(time * 9)) * 1.5
        case .waiting: return CGFloat(sin(time * 5)) * 3
        case .sleeping: return -2 + CGFloat(sin(time * 0.8)) * 1.2
        case .done, .error: return 0
        default: return CGFloat(sin(time * 3.2)) * 3
        }
    }

    private func headTilt(_ state: RobotState) -> Double {
        switch model.mood {
        case .some(.dizzy): return sin(time * 6) * 9
        case .some(.tired): return 6
        case .some(.pleased): return sin(time * 3) * 4
        default: break
        }
        switch state {
        case .thinking: return sin(time * 1.2) * 5
        case .reading, .searching: return sin(time * 2) * 3
        case .sleeping: return 8
        default: return 0
        }
    }

    private var celebrateElapsed: Double? {
        guard let start = model.celebrateStart else { return nil }
        let t = time - start.timeIntervalSinceReferenceDate
        return (t >= 0 && t <= 1.6) ? t : nil
    }

    private var isCelebrating: Bool { celebrateElapsed != nil }

    private var hopHeight: CGFloat {
        guard let t = celebrateElapsed, t <= 1.3 else { return 0 }
        return CGFloat(abs(sin(t * Double.pi * 2.3))) * 14
    }

    private var shakeOffset: CGFloat {
        guard let start = model.errorStart else { return 0 }
        let t = time - start.timeIntervalSinceReferenceDate
        guard t >= 0 && t <= 0.6 else { return 0 }
        return CGFloat(sin(t * 45) * (1 - t / 0.6)) * 5
    }
}

struct FaceView: View {
    let state: RobotState
    let mood: Mood?
    let time: TimeInterval
    let look: CGFloat
    let eyeColor: Color

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.74, green: 0.71, blue: 0.84)).frame(width: 12, height: 12).position(x: 6, y: 50)
            Circle().fill(Color(red: 0.74, green: 0.71, blue: 0.84)).frame(width: 12, height: 12).position(x: 94, y: 50)
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.97, blue: 0.95),
                                              Color(red: 0.86, green: 0.84, blue: 0.92)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 86, height: 70)
                .position(x: 50, y: 50)
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.16))
                .frame(width: 70, height: 44)
                .position(x: 50, y: 52)
            DotEyes(state: state, mood: mood, look: look, time: time, color: eyeColor)
                .frame(width: 70, height: 44)
                .position(x: 50, y: 52)
            // Alında durum LED'i
            Circle()
                .fill(ledColor.opacity(0.3))
                .frame(width: 11, height: 11)
                .opacity(ledOpacity)
                .position(x: 50, y: 22.5)
            Circle()
                .fill(ledColor)
                .frame(width: 5, height: 5)
                .opacity(ledOpacity)
                .position(x: 50, y: 22.5)
        }
    }

    private var ledColor: Color {
        switch state {
        case .waiting, .error: return Color(red: 0.97, green: 0.44, blue: 0.44)
        case .thinking: return Color(red: 0.98, green: 0.82, blue: 0.3)
        case .sleeping: return Color.gray
        case .idle: return Color(red: 0.75, green: 0.72, blue: 0.85)
        default: return Color(red: 0.2, green: 0.83, blue: 0.6)
        }
    }

    private var ledOpacity: Double {
        switch state {
        case .waiting: return sin(time * 10) > 0 ? 1 : 0.25
        case .thinking: return 0.55 + 0.45 * sin(time * 4)
        case .sleeping: return 0.4
        case .idle, .done, .error: return 1
        default: return 0.6 + 0.4 * sin(time * 7)
        }
    }
}

/// LED nokta matrisi gözler: her göz 7 × 9 minik noktadan oluşur.
/// Yanan noktaların deseni duruma ve ruh hâline göre değişir.
struct DotEyes: View {
    let state: RobotState
    let mood: Mood?
    let look: CGFloat
    let time: TimeInterval
    let color: Color

    private static let cols = 7
    private static let rows = 9
    private static let spacing: CGFloat = 3.5
    private static let dot: CGFloat = 2.4

    // Kalp deseni (memnun)
    private static let heart: [String] = [
        ".......",
        ".##.##.",
        "#######",
        "#######",
        "#######",
        ".#####.",
        "..###..",
        "...#...",
        ".......",
    ]

    var body: some View {
        Canvas { context, size in
            let tint = (state == .error && mood == nil) ? Color(red: 1, green: 0.42, blue: 0.42) : color
            let centers: [CGFloat] = [size.width / 2 - 14, size.width / 2 + 14]
            for (eye, cx) in centers.enumerated() {
                for r in 0..<DotEyes.rows {
                    for c in 0..<DotEyes.cols {
                        let x = cx + (CGFloat(c) - 3) * DotEyes.spacing
                        let y = size.height / 2 + (CGFloat(r) - 4) * DotEyes.spacing
                        let rect = CGRect(x: x - DotEyes.dot / 2, y: y - DotEyes.dot / 2, width: DotEyes.dot, height: DotEyes.dot)
                        let b = brightness(c: Double(c), r: Double(r), eye: eye)
                        if b > 0.05 {
                            context.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(tint.opacity(0.22 * b)))
                            context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(b)))
                        } else {
                            context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.1)))
                        }
                    }
                }
            }
        }
    }

    private var blinking: Bool {
        state != .waiting && mood == nil && time.truncatingRemainder(dividingBy: 4.2) < 0.12
    }

    /// Bir noktanın parlaklığı (0…1)
    private func brightness(c: Double, r: Double, eye: Int) -> Double {
        let lookShift = Double(look) / 2.5   // ekranın ortasına doğru bak
        if let mood = mood {
            switch mood {
            case .pleased: return bitmap(DotEyes.heart, c: c, r: r) * (0.8 + 0.2 * sin(time * 6))
            case .shocked: return capsule(c, r, cx: 3, cy: 4, rx: 2.9, ry: 4.2)
            case .nervous: return capsule(c, r, cx: 3 + sin(time * 14) * 1.1, cy: 4.5, rx: 1.2, ry: 2)
            case .scared: return capsule(c, r, cx: 3 + sin(time * 40) * 0.4, cy: 4, rx: 1.4, ry: 3.8)
            case .proud, .party: return arc(c, r, cx: 3, cy: 6.2, radius: 2.7)
            case .tired: return capsule(c, r, cx: 3, cy: 5.2, rx: 2.1, ry: 1.1) * 0.8
            case .dizzy: return spiral(c, r, eye: eye)
            case .denied: return capsule(c, r, cx: 3, cy: 6, rx: 1.7, ry: 1.3)
            }
        }
        if blinking { return capsule(c, r, cx: 3 + lookShift, cy: 4.5, rx: 2, ry: 0.6) }
        switch state {
        case .done:
            return arc(c, r, cx: 3, cy: 6.2, radius: 2.7)
        case .error:
            return cross(c, r)
        case .sleeping:
            return (abs(r - 6) < 0.5 && abs(c - 3) <= 2) ? 0.5 : 0
        case .thinking:
            return capsule(c, r, cx: 3 + 0.9, cy: 2.8, rx: 1.5, ry: 2.6)
        case .reading, .searching:
            return capsule(c, r, cx: 3 + sin(time * 3) * 1.5, cy: 4.4, rx: 1.5, ry: 2.3)
        case .editing:
            return capsule(c, r, cx: 3 + lookShift * 0.5, cy: 5, rx: 1.9, ry: 1.5)
        case .running, .delegating:
            let shimmer = 0.75 + 0.25 * sin(time * 18 + c * 1.3 + r * 0.7)
            return capsule(c, r, cx: 3, cy: 4, rx: 1.6, ry: 2.8) * shimmer
        case .waiting:
            return capsule(c, r, cx: 3, cy: 4, rx: 2.5, ry: 3.9) * (0.75 + 0.25 * sin(time * 6))
        case .idle:
            return capsule(c, r, cx: 3 + lookShift, cy: 4, rx: 1.7, ry: 3.3)
        }
    }

    private func capsule(_ c: Double, _ r: Double, cx: Double, cy: Double, rx: Double, ry: Double) -> Double {
        let dx = (c - cx) / rx
        let dy = (r - cy) / ry
        let d = dx * dx + dy * dy
        if d <= 1 { return 1 }
        if d <= 1.35 { return 0.35 }
        return 0
    }

    /// ^ biçimi (mutlu)
    private func arc(_ c: Double, _ r: Double, cx: Double, cy: Double, radius: Double) -> Double {
        guard r <= cy else { return 0 }
        let d = ((c - cx) * (c - cx) + (r - cy) * (r - cy)).squareRoot()
        return abs(d - radius) < 0.6 ? 1 : 0
    }

    private func cross(_ c: Double, _ r: Double) -> Double {
        let x = c - 3
        let y = r - 4
        guard abs(x) <= 2.5 && abs(y) <= 2.5 else { return 0 }
        return (abs(x - y) < 0.5 || abs(x + y) < 0.5) ? 1 : 0
    }

    /// Dönen halka (başı dönmüş)
    private func spiral(_ c: Double, _ r: Double, eye: Int) -> Double {
        let x = c - 3
        let y = r - 4
        let d = (x * x + y * y).squareRoot()
        guard abs(d - 2.4) < 0.7 else { return d < 0.6 ? 1 : 0 }
        let angle = atan2(y, x)
        let phase = time * (eye == 0 ? 6 : -6)
        return 0.35 + 0.65 * max(0, cos(angle - phase))
    }

    private func bitmap(_ rows: [String], c: Double, r: Double) -> Double {
        let ri = Int(r)
        let ci = Int(c)
        guard ri >= 0, ri < rows.count else { return 0 }
        let row = Array(rows[ri])
        guard ci >= 0, ci < row.count else { return 0 }
        return row[ci] == "#" ? 1 : 0
    }
}

/// Telepati dalgaları: düşünürken başından halkalar yayılır.
struct WavesView: View {
    let time: TimeInterval
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(color, lineWidth: 1.3)
                    .frame(width: size(i), height: size(i))
                    .opacity(opacity(i))
                    .position(x: 50, y: 50)
            }
        }
    }

    private func progress(_ i: Int) -> Double {
        (time * 0.7 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
    }

    private func size(_ i: Int) -> CGFloat {
        CGFloat(96 + progress(i) * 50)
    }

    private func opacity(_ i: Int) -> Double {
        (1 - progress(i)) * 0.5
    }
}

struct SparklesView: View {
    let time: TimeInterval
    let color: Color
    let radius: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(color)
                    .opacity(0.5 + 0.5 * sin(time * 5 + Double(i)))
                    .position(point(i))
            }
        }
    }

    private func point(_ i: Int) -> CGPoint {
        let angle = time * 2 + Double(i) * 2.09
        return CGPoint(x: 50 + CGFloat(cos(angle)) * radius, y: 50 + CGFloat(sin(angle)) * radius * 0.6)
    }
}

struct ZzzView: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Text("z")
                    .font(.system(size: 10 + CGFloat(i) * 2, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .opacity(1 - progress(i))
                    .position(x: 82 + CGFloat(progress(i)) * 12, y: 22 - CGFloat(progress(i)) * 22)
            }
        }
    }

    private func progress(_ i: Int) -> Double {
        (time * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
    }
}

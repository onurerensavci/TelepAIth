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

// MARK: - Kafa

struct HeadFigure: View {
    let model: RobotModel
    let time: TimeInterval
    let look: CGFloat

    var body: some View {
        let state = model.state
        let base = model.theme.color
        let hatColor = Color(nsColor: base)
        let brimColor = Color(nsColor: base.mix(.black, 0.22))
        let accent = Color(nsColor: base.mix(.white, 0.55))
        let hop = hopHeight
        let float = floatOffset(state)
        let shake = shakeOffset
        let skin = SkinStore.shared.image(source: model.source, state: state)
        let lift = hop - float

        return ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.14))
                .frame(width: Swift.max(24, 56 - lift * 1.5), height: 6)
                .position(x: 50, y: 107)

            Group {
                if let skin = skin {
                    Image(nsImage: skin)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 100, height: 104)
                        .position(x: 50, y: 52)
                } else {
                    ZStack {
                        FaceView(state: state, time: time, look: look)
                        HatView(state: state, time: time, color: hatColor, brim: brimColor, accent: accent)
                            .rotationEffect(.degrees(hatTilt(state)), anchor: UnitPoint(x: 0.5, y: 0.42))
                    }
                }
            }
            .rotationEffect(.degrees(headTilt(state)), anchor: UnitPoint(x: 0.5, y: 0.9))
            .offset(x: shake, y: -lift)

            if state == .thinking || state == .delegating || state == .reading || state == .searching {
                WavesView(time: time, color: accent)
                    .offset(x: shake, y: -lift)
            }
            if isCelebrating || state == .editing {
                SparklesView(time: time, color: accent, radius: state == .editing ? 36 : 48)
                    .offset(y: -lift)
            }
            if state == .sleeping {
                ZzzView(time: time)
            }
        }
        .frame(width: 100, height: 110)
    }

    // Havada süzülme
    private func floatOffset(_ state: RobotState) -> CGFloat {
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
        switch state {
        case .thinking: return sin(time * 1.2) * 5
        case .reading, .searching: return sin(time * 2) * 3
        case .sleeping: return 8
        default: return 0
        }
    }

    private func hatTilt(_ state: RobotState) -> Double {
        if isCelebrating { return sin(time * 14) * 8 }
        switch state {
        case .running: return sin(time * 9) * 4
        case .waiting: return sin(time * 6) * 6
        case .sleeping: return -12
        case .error: return -6
        default: return sin(time * 1.6) * 2
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

struct WizardHatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + h))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.72, y: rect.minY),
                       control: CGPoint(x: rect.minX + w * 0.32, y: rect.minY + h * 0.35))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w, y: rect.minY + h),
                       control: CGPoint(x: rect.minX + w * 0.86, y: rect.minY + h * 0.55))
        p.closeSubpath()
        return p
    }
}

struct HappyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                       control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6))
        return p
    }
}

struct HatView: View {
    let state: RobotState
    let time: TimeInterval
    let color: Color
    let brim: Color
    let accent: Color

    var body: some View {
        ZStack {
            WizardHatShape()
                .fill(color)
                .frame(width: 56, height: 42)
                .position(x: 53, y: 25)
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(accent)
                .position(x: 50, y: 32)
            Ellipse()
                .fill(brim)
                .frame(width: 92, height: 15)
                .position(x: 50, y: 46)
            Circle()
                .fill(orbColor.opacity(0.25))
                .frame(width: 20, height: 20)
                .opacity(orbOpacity)
                .position(x: 65, y: 5)
            Circle()
                .fill(orbColor)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                .opacity(orbOpacity)
                .position(x: 65, y: 5)
        }
    }

    // Şapkanın ucundaki küre durum ışığı
    private var orbColor: Color {
        switch state {
        case .waiting, .error: return Color(red: 0.97, green: 0.44, blue: 0.44)
        case .thinking: return Color(red: 0.98, green: 0.82, blue: 0.3)
        case .sleeping: return Color.gray
        case .idle: return Color(red: 1.0, green: 0.88, blue: 0.48)
        default: return Color(red: 0.2, green: 0.83, blue: 0.6)
        }
    }

    private var orbOpacity: Double {
        switch state {
        case .waiting: return sin(time * 10) > 0 ? 1 : 0.25
        case .thinking: return 0.55 + 0.45 * sin(time * 4)
        case .sleeping: return 0.4
        case .idle, .done, .error: return 1
        default: return 0.6 + 0.4 * sin(time * 7)
        }
    }
}

struct FaceView: View {
    let state: RobotState
    let time: TimeInterval
    let look: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.74, green: 0.71, blue: 0.84)).frame(width: 11, height: 11).position(x: 9, y: 76)
            Circle().fill(Color(red: 0.74, green: 0.71, blue: 0.84)).frame(width: 11, height: 11).position(x: 91, y: 76)
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.97, blue: 0.95),
                                              Color(red: 0.86, green: 0.84, blue: 0.92)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 78, height: 58)
                .position(x: 50, y: 75)
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.16))
                .frame(width: 62, height: 32)
                .position(x: 50, y: 77)
            EyesView(state: state, look: look, time: time)
        }
    }
}

struct EyesView: View {
    let state: RobotState
    let look: CGFloat
    let time: TimeInterval

    var body: some View {
        let color = state == .error
            ? Color(red: 1, green: 0.55, blue: 0.55)
            : Color(red: 0.56, green: 0.96, blue: 1)
        return ZStack {
            eye(x: 40, color: color)
            eye(x: 60, color: color)
        }
    }

    @ViewBuilder
    private func eye(x: CGFloat, color: Color) -> some View {
        if state == .done {
            HappyEyeShape()
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 11, height: 6)
                .position(x: x + look * 0.5, y: 79)
        } else if state == .sleeping {
            Capsule()
                .fill(color.opacity(0.6))
                .frame(width: 11, height: 2.5)
                .position(x: x, y: 79)
        } else if state == .error {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(color)
                .position(x: x, y: 77)
        } else {
            ZStack {
                Capsule()
                    .fill(color.opacity(0.18))
                    .frame(width: eyeWidth + 6, height: (blinking ? 2 : eyeHeight) + 6)
                    .position(x: x + look + eyeDX, y: 77 + eyeDY)
                Capsule()
                    .fill(color)
                    .frame(width: eyeWidth, height: blinking ? 2 : eyeHeight)
                    .position(x: x + look + eyeDX, y: 77 + eyeDY)
            }
        }
    }

    private var blinking: Bool {
        state != .waiting && time.truncatingRemainder(dividingBy: 4.2) < 0.12
    }

    private var eyeWidth: CGFloat {
        switch state {
        case .thinking: return 9
        case .waiting: return 12
        default: return 10
        }
    }

    private var eyeHeight: CGFloat {
        switch state {
        case .thinking: return 15
        case .reading, .searching: return 10
        case .editing: return 8
        case .running, .delegating: return 12
        case .waiting: return 19
        default: return 17
        }
    }

    private var eyeDX: CGFloat {
        switch state {
        case .thinking: return 2
        case .reading, .searching: return CGFloat(sin(time * 3)) * 3
        default: return 0
        }
    }

    private var eyeDY: CGFloat {
        switch state {
        case .thinking: return -3
        case .editing: return 2
        case .waiting: return CGFloat(sin(time * 6)) * 1
        default: return 0
        }
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
                    .position(x: 50, y: 70)
            }
        }
    }

    private func progress(_ i: Int) -> Double {
        (time * 0.7 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
    }

    private func size(_ i: Int) -> CGFloat {
        CGFloat(80 + progress(i) * 50)
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
        return CGPoint(x: 50 + CGFloat(cos(angle)) * radius, y: 62 + CGFloat(sin(angle)) * radius * 0.6)
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
                    .position(x: 80 + CGFloat(progress(i)) * 12, y: 40 - CGFloat(progress(i)) * 24)
            }
        }
    }

    private func progress(_ i: Int) -> Double {
        (time * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
    }
}

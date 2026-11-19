import SwiftUI

// Robot-büyücü çizimi. Çizim alanı 90 × 124 nokta; tüm konumlar bu alana göre.

struct RobotContainerView: View {
    @ObservedObject var model: RobotModel

    var body: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            if let text = model.bubbleText {
                BubbleView(title: model.theme.displayName,
                           subtitle: model.bubbleSubtitle,
                           text: text,
                           color: Color(nsColor: model.theme.color))
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                RobotFigure(model: model, time: context.date.timeIntervalSinceReferenceDate)
            }
            .frame(width: Layout.robotSize.width, height: Layout.robotSize.height)
        }
        .frame(width: Layout.windowSize.width, height: Layout.windowSize.height, alignment: .bottom)
        .animation(.easeInOut(duration: 0.18), value: model.bubbleText)
    }
}

struct BubbleView: View {
    let title: String
    let subtitle: String?
    let text: String
    let color: Color

    var body: some View {
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
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}

struct RobotFigure: View {
    let model: RobotModel
    let time: TimeInterval

    var body: some View {
        let state = model.state
        let base = model.theme.color
        let main = Color(nsColor: base)
        let dark = Color(nsColor: base.mix(.black, 0.25))
        let accent = Color(nsColor: base.mix(.white, 0.5))
        let walking = model.isWalking
        let phase: Double = walking ? time * stepRate(state) : 0
        let bob = CGFloat(walking ? abs(sin(phase)) * 1.5 : 0)
        let hop = hopHeight
        let lean: Double = walking ? Double(model.facing) * 4 : 0
        let skin = SkinStore.shared.image(source: model.source, state: state)

        return ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: Swift.max(20, 50 - hop * 1.5), height: 6)
                .position(x: 45, y: 118)

            if let skin = skin {
                Image(nsImage: skin)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 90, height: 118)
                    .scaleEffect(x: model.facing < 0 ? -1 : 1, y: 1)
                    .rotationEffect(.degrees(lean), anchor: .bottom)
                    .offset(y: -(bob + hop))
                    .position(x: 45, y: 59)
            } else {
                ZStack {
                    FeetView(phase: phase, color: dark)
                    ArmsView(state: state, phase: phase, time: time, celebrating: isCelebrating, color: dark)
                    RobeView(state: state, color: main, trim: accent)
                    HeadView(color: main, bolt: dark)
                    EyesView(state: state, look: model.facing * 2.5, time: time)
                    HatView(state: state, time: time, color: dark, accent: accent)
                }
                .rotationEffect(.degrees(lean), anchor: .bottom)
                .offset(y: -(bob + hop))
            }

            if state == .thinking || state == .delegating || state == .reading || state == .searching {
                WavesView(time: time, color: accent)
                    .offset(y: -(bob + hop))
            }
            if isCelebrating || state == .editing {
                SparklesView(time: time, color: accent, radius: state == .editing ? 26 : 38)
                    .offset(y: -(bob + hop))
            }
            if state == .sleeping {
                ZzzView(time: time)
            }
        }
        .frame(width: 90, height: 124)
    }

    private func stepRate(_ state: RobotState) -> Double {
        switch state {
        case .running: return 16
        case .searching, .delegating: return 11
        default: return 8
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
}

// MARK: - Parçalar

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

struct RobeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: rect.minX + w * 0.2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.8, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w, y: rect.minY + h),
                       control: CGPoint(x: rect.minX + w * 0.88, y: rect.minY + h * 0.55))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + h),
                       control: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h * 1.08))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.2, y: rect.minY),
                       control: CGPoint(x: rect.minX + w * 0.12, y: rect.minY + h * 0.55))
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
    let accent: Color

    var body: some View {
        ZStack {
            WizardHatShape()
                .fill(color)
                .frame(width: 40, height: 30)
                .position(x: 45, y: 24)
            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(accent)
                .position(x: 42, y: 29)
            Ellipse()
                .fill(color)
                .frame(width: 64, height: 10)
                .position(x: 45, y: 39)
            Circle()
                .fill(orbColor)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                .opacity(orbOpacity)
                .position(x: 54, y: 8)
        }
    }

    // Şapkanın ucundaki küre durum ışığı
    private var orbColor: Color {
        switch state {
        case .waiting, .error: return Color(red: 0.97, green: 0.44, blue: 0.44)
        case .thinking: return Color(red: 0.98, green: 0.75, blue: 0.14)
        case .sleeping: return Color.gray
        case .idle: return Color(red: 0.85, green: 0.9, blue: 1.0)
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

struct HeadView: View {
    let color: Color
    let bolt: Color

    var body: some View {
        ZStack {
            Circle().fill(bolt).frame(width: 7, height: 7).position(x: 17, y: 56)
            Circle().fill(bolt).frame(width: 7, height: 7).position(x: 73, y: 56)
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(width: 54, height: 34)
                .position(x: 45, y: 55)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.14))
                .frame(width: 42, height: 18)
                .position(x: 45, y: 57)
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
            : Color(red: 0.86, green: 0.97, blue: 1)
        return ZStack {
            eye(x: 37, color: color)
            eye(x: 53, color: color)
        }
    }

    @ViewBuilder
    private func eye(x: CGFloat, color: Color) -> some View {
        if state == .done {
            HappyEyeShape()
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 9, height: 5)
                .position(x: x + look * 0.5, y: 58)
        } else if state == .sleeping {
            Capsule()
                .fill(color.opacity(0.6))
                .frame(width: 9, height: 2)
                .position(x: x, y: 58)
        } else if state == .error {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(color)
                .position(x: x, y: 57)
        } else {
            Capsule()
                .fill(color)
                .frame(width: eyeWidth, height: blinking ? 1.5 : eyeHeight)
                .position(x: x + look + eyeDX, y: 57 + eyeDY)
        }
    }

    private var blinking: Bool {
        state != .waiting && time.truncatingRemainder(dividingBy: 4.2) < 0.12
    }

    private var eyeWidth: CGFloat {
        switch state {
        case .thinking: return 7
        case .waiting: return 10
        default: return 8
        }
    }

    private var eyeHeight: CGFloat {
        switch state {
        case .thinking: return 9
        case .reading, .searching: return 6
        case .editing: return 5
        case .running, .delegating: return 7
        case .waiting: return 11
        default: return 10
        }
    }

    private var eyeDX: CGFloat {
        switch state {
        case .thinking: return 1.5
        case .reading, .searching: return CGFloat(sin(time * 3)) * 2.5
        default: return 0
        }
    }

    private var eyeDY: CGFloat {
        switch state {
        case .thinking: return -2.5
        case .editing: return 1.5
        case .waiting: return CGFloat(sin(time * 6)) * 0.8
        default: return 0
        }
    }
}

struct RobeView: View {
    let state: RobotState
    let color: Color
    let trim: Color

    var body: some View {
        ZStack {
            RobeShape()
                .fill(color)
                .frame(width: 58, height: 38)
                .position(x: 45, y: 92)
            RoundedRectangle(cornerRadius: 2)
                .fill(trim.opacity(0.85))
                .frame(width: 50, height: 3)
                .position(x: 45, y: 108)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.14))
                .frame(width: 18, height: 12)
                .position(x: 45, y: 88)
            Image(systemName: state.symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(trim)
                .position(x: 45, y: 88)
        }
    }
}

struct ArmsView: View {
    let state: RobotState
    let phase: Double
    let time: TimeInterval
    let celebrating: Bool
    let color: Color

    var body: some View {
        ZStack {
            arm(x: 22, angle: angles.left)
            arm(x: 68, angle: angles.right)
        }
    }

    private func arm(x: CGFloat, angle: Double) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 10, height: 24)
            .rotationEffect(.degrees(angle), anchor: .top)
            .position(x: x, y: 88)
    }

    // Pozitif açı: kol saat yönünde döner (sol kol dışa açılır)
    private var angles: (left: Double, right: Double) {
        if celebrating {
            let w = sin(time * 14) * 10
            return (150 + w, -150 - w)
        }
        switch state {
        case .waiting:
            return (10, -145 + sin(time * 9) * 22)        // el sallıyor
        case .editing:
            let k = sin(time * 20) * 9
            return (-35 + k, 35 - k)                      // büyü yazıyor
        case .thinking:
            return (8, -95 + sin(time * 2) * 8)
        case .error, .sleeping:
            return (3, -3)
        default:
            let swing = sin(phase) * (state == .running ? 28 : 14)
            return (8 + swing, -8 + swing)
        }
    }
}

struct FeetView: View {
    let phase: Double
    let color: Color

    var body: some View {
        let left = CGFloat(Swift.max(0, sin(phase))) * 4
        let right = CGFloat(Swift.max(0, sin(phase + Double.pi))) * 4
        return ZStack {
            Capsule().fill(color).frame(width: 14, height: 7).position(x: 36, y: 113 - left)
            Capsule().fill(color).frame(width: 14, height: 7).position(x: 54, y: 113 - right)
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
                    .stroke(color, lineWidth: 1.2)
                    .frame(width: size(i), height: size(i))
                    .opacity(opacity(i))
                    .position(x: 45, y: 55)
            }
        }
    }

    private func progress(_ i: Int) -> Double {
        (time * 0.7 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
    }

    private func size(_ i: Int) -> CGFloat {
        CGFloat(44 + progress(i) * 44)
    }

    private func opacity(_ i: Int) -> Double {
        (1 - progress(i)) * 0.55
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
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(color)
                    .opacity(0.5 + 0.5 * sin(time * 5 + Double(i)))
                    .position(point(i))
            }
        }
    }

    private func point(_ i: Int) -> CGPoint {
        let angle = time * 2 + Double(i) * 2.09
        return CGPoint(x: 45 + CGFloat(cos(angle)) * radius, y: 70 + CGFloat(sin(angle)) * radius * 0.6)
    }
}

struct ZzzView: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Text("z")
                    .font(.system(size: 9 + CGFloat(i) * 2, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .opacity(1 - progress(i))
                    .position(x: 70 + CGFloat(progress(i)) * 12, y: 30 - CGFloat(progress(i)) * 22)
            }
        }
    }

    private func progress(_ i: Int) -> Double {
        (time * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
    }
}

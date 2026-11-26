import SwiftUI

/// Efektlerin çizimi (Windows'ta RobotView.DrawEffect, aynı şekiller). Alan 140 × 150: kafa alanına göre -20, -25'ten başlar.
/// energy (0…1): robot ses çıkaran bir an yaşayınca yükselir, efekt büyür ve parlar.
struct EffectView: View {
    let id: String
    let time: TimeInterval
    let energy: Double

    var body: some View {
        Canvas { ctx, _ in
            ctx.translateBy(x: 20, y: 25)
            EffectView.draw(id, in: ctx, t: time, e: energy)
        }
        .frame(width: 140, height: 150)
        .position(x: 50, y: 50)
        .allowsHitTesting(false)
    }

    private static func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(red: r, green: g, blue: b).opacity(Swift.max(0, Swift.min(1, a)))
    }

    /// Robotun penceresi kafanın her yanında ancak ~14 nokta yer bırakıyor: efektler -12…112 içinde kalır,
    /// kenarlara yaklaşınca yumuşakça söner (sert kesik görünmesin)
    private static func edge(_ x: Double, _ y: Double) -> Double {
        func c(_ v: Double) -> Double { Swift.max(0, Swift.min(1, v)) }
        return c((x + 12) / 10) * c((112 - x) / 10) * c((y + 12) / 10) * c((112 - y) / 16)
    }

    private static func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private static func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        return p
    }

    static func draw(_ id: String, in ctx: GraphicsContext, t: Double, e: Double) {
        let tau = Double.pi * 2
        let round = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
        func stroke(_ p: Path, _ color: Color, _ w: Double) {
            var s = round
            s.lineWidth = w
            ctx.stroke(p, with: .color(color), style: s)
        }
        switch id {
        case "sun":
            let cx = 50.0, cy = 48.0, r = 50 + 6 * e
            ctx.fill(circle(cx, cy, r), with: .radialGradient(
                Gradient(colors: [c(1, 0.86, 0.35, 0.42 + 0.3 * e), c(1, 0.75, 0.3, 0)]),
                center: CGPoint(x: cx, y: cy), startRadius: 30, endRadius: r))
            for i in 0..<12 {
                let a = t * 0.25 + Double(i) * tau / 12
                let r1 = 44.0, r2 = 50 + 5 * e + 2 * sin(t * 2 + Double(i))
                stroke(line(cx + cos(a) * r1, cy + sin(a) * r1, cx + cos(a) * r2, cy + sin(a) * r2),
                       c(1, 0.8, 0.3, 0.45 + 0.35 * e), i % 2 == 1 ? 2 : 3)
            }
        case "rainbow":
            let colors: [(Double, Double, Double)] = [(1, 0.35, 0.35), (1, 0.62, 0.25), (1, 0.88, 0.3),
                                                      (0.4, 0.85, 0.45), (0.35, 0.65, 1), (0.65, 0.45, 1)]
            for (i, k) in colors.enumerated() {
                let r = 58 - Double(i) * 3.2 + 2 * e
                var p = Path()
                for s in 0...32 {
                    let a = Double.pi * (1.04 + 0.92 * Double(s) / 32)
                    let pt = CGPoint(x: 50 + cos(a) * r, y: 64 + sin(a) * r)
                    if s == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                stroke(p, c(k.0, k.1, k.2, (0.5 + 0.35 * e) * (0.85 + 0.15 * sin(t * 2 + Double(i)))), 3.2)
            }
        case "aurora":
            // Kafanın üstünde kavis yapan ışık şeritleri; uçlarda saydamlaşır
            let colors: [(Double, Double, Double)] = [(0.3, 1, 0.6), (0.3, 0.85, 1), (0.75, 0.45, 1)]
            for k in 0..<3 {
                var p = Path()
                var x = -10.0
                while x <= 110 {
                    let y = 6 + Double(k) * 6 + 0.0045 * (x - 50) * (x - 50)
                        + sin(x * 0.07 + t * (0.8 + 0.25 * Double(k)) + Double(k) * 1.3) * (2.5 + 3 * e)
                    if x == -10 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    x += 4
                }
                let col = colors[k]
                func band(_ a: Double) -> GraphicsContext.Shading {
                    .linearGradient(Gradient(stops: [.init(color: c(col.0, col.1, col.2, 0), location: 0),
                                                     .init(color: c(col.0, col.1, col.2, a), location: 0.22),
                                                     .init(color: c(col.0, col.1, col.2, a), location: 0.78),
                                                     .init(color: c(col.0, col.1, col.2, 0), location: 1)]),
                                    startPoint: CGPoint(x: -10, y: 0), endPoint: CGPoint(x: 110, y: 0))
                }
                var wide = round
                wide.lineWidth = 9 + 3 * e
                ctx.stroke(p, with: band(0.14 * (1 + 0.9 * e)), style: wide)
                var thin = round
                thin.lineWidth = 3.5 + 1.5 * e
                ctx.stroke(p, with: band(0.34 * (1 + 0.9 * e)), style: thin)
            }
        case "stars":
            for i in 0..<9 {
                let a = (Double(i) * 40 + 10) * .pi / 180, r = 52 + Double(i % 3) * 3
                let x = 50 + cos(a) * r, y = 48 + sin(a) * r * 0.92
                let s = 0.5 + 0.5 * sin(t * (1.5 + Double(i) * 0.3) + Double(i) * 2)
                let size = (1.8 + 1.6 * s) * (1 + 0.7 * e)
                var p = Path()
                let mid = CGPoint(x: x, y: y)
                p.move(to: CGPoint(x: x, y: y - size))
                p.addQuadCurve(to: CGPoint(x: x + size, y: y), control: mid)
                p.addQuadCurve(to: CGPoint(x: x, y: y + size), control: mid)
                p.addQuadCurve(to: CGPoint(x: x - size, y: y), control: mid)
                p.addQuadCurve(to: CGPoint(x: x, y: y - size), control: mid)
                ctx.fill(p, with: .color(c(1, 0.95, 0.7, (0.35 + 0.65 * s) * edge(x, y))))
            }
        case "hearts":
            for i in 0..<7 {
                let ph = (t * 0.13 + Double(i) / 7).truncatingRemainder(dividingBy: 1)
                let y = 104 - ph * 112, x = 8 + Double(i * 37 % 84) + sin(t * 1.2 + Double(i)) * 6
                let s = (3 + 1.2 * Double(i % 3)) * (1 + 0.6 * e)
                var p = Path()
                p.move(to: CGPoint(x: x, y: y + s * 0.9))
                p.addCurve(to: CGPoint(x: x, y: y - s * 0.35), control1: CGPoint(x: x - s * 1.4, y: y - s * 0.1),
                           control2: CGPoint(x: x - s * 0.7, y: y - s * 1.1))
                p.addCurve(to: CGPoint(x: x, y: y + s * 0.9), control1: CGPoint(x: x + s * 0.7, y: y - s * 1.1),
                           control2: CGPoint(x: x + s * 1.4, y: y - s * 0.1))
                ctx.fill(p, with: .color(c(1, 0.42, 0.62, sin(ph * .pi) * (0.55 + 0.4 * e) * edge(x, y))))
            }
        case "bubbles":
            for i in 0..<8 {
                let ph = (t * 0.11 + Double(i) / 8).truncatingRemainder(dividingBy: 1)
                let y = 104 - ph * 112, x = 6 + Double(i * 41 % 88) + sin(t * 1.5 + Double(i) * 2) * 5
                let r = (1.8 + Double(i % 3)) * (1 + 0.5 * e)
                let a = sin(ph * .pi) * (0.55 + 0.4 * e) * edge(x, y)
                ctx.fill(circle(x, y, r), with: .color(c(0.7, 0.9, 1, a * 0.18)))
                stroke(circle(x, y, r), c(0.85, 0.95, 1, a), 0.8)
                ctx.fill(circle(x - r * 0.35, y - r * 0.35, r * 0.25), with: .color(c(1, 1, 1, a * 0.9)))
            }
        case "fireflies":
            for i in 0..<8 {
                let d = Double(i)
                let x = 50 + cos(t * 0.4 * (1 + Double(i % 3) * 0.3) + d * 1.7) * 56
                let y = 50 + sin(t * 0.5 * (1 + Double(i % 2) * 0.4) + d * 2.3) * 50
                let b = (0.5 + 0.5 * sin(t * 3 + d * 1.3)) * edge(x, y)
                ctx.fill(circle(x, y, 4 + 2 * e), with: .color(c(0.8, 1, 0.4, 0.18 * b * (1 + 1.2 * e))))
                ctx.fill(circle(x, y, 1.2 + 0.5 * e), with: .color(c(0.9, 1, 0.55, 0.45 + 0.55 * b)))
            }
        case "rain":
            for i in 0..<14 {
                let y = (t * 75 + Double(i * 29)).truncatingRemainder(dividingBy: 124) - 12
                let x = 4 + Double(i * 41 % 108) - (y + 12) * 0.12
                let len = 5 + 3 * e
                stroke(line(x, y, x - len * 0.12, y + len), c(0.6, 0.8, 1, (0.45 + 0.35 * e) * edge(x, y + len)), 1.1)
            }
        case "leaves":
            let colors: [(Double, Double, Double)] = [(0.95, 0.5, 0.2), (0.85, 0.3, 0.2), (0.95, 0.75, 0.25)]
            for i in 0..<8 {
                let d = Double(i)
                let y = (t * (10 + Double(i % 3) * 3) + d * 43).truncatingRemainder(dividingBy: 124) - 12
                let x = Double(i * 47 % 108) - 4 + sin(t * 1.1 + d) * 5 * (1 + 0.6 * e)
                let rot = sin(t * 1.5 + d) * 0.8 + d
                let s = 1 + 0.4 * e
                var p = Path()
                p.move(to: CGPoint(x: -3.2 * s, y: 0))
                p.addQuadCurve(to: CGPoint(x: 3.2 * s, y: 0), control: CGPoint(x: 0, y: -2.4 * s))
                p.addQuadCurve(to: CGPoint(x: -3.2 * s, y: 0), control: CGPoint(x: 0, y: 2.4 * s))
                let k = colors[i % 3]
                ctx.fill(p.applying(CGAffineTransform(rotationAngle: rot).concatenating(CGAffineTransform(translationX: x, y: y))),
                         with: .color(c(k.0, k.1, k.2, 0.85 * edge(x, y))))
            }
        case "confetti":
            let colors: [(Double, Double, Double)] = [(1, 0.4, 0.45), (1, 0.8, 0.3), (0.4, 0.8, 1), (0.5, 0.9, 0.5), (0.8, 0.5, 1)]
            for i in 0..<14 {
                let d = Double(i)
                let y = (t * (18 + Double(i % 4) * 4) + d * 31).truncatingRemainder(dividingBy: 124) - 12
                let x = Double(i * 59 % 110) - 5 + sin(t * 2 + d) * 4
                let rot = t * (2 + Double(i % 3)) + d
                let s = 1 + 0.5 * e
                let p = Path(CGRect(x: -1.3 * s, y: -0.7 * s, width: 2.6 * s, height: 1.4 * s))
                let k = colors[i % 5]
                ctx.fill(p.applying(CGAffineTransform(rotationAngle: rot.truncatingRemainder(dividingBy: tau))
                    .concatenating(CGAffineTransform(translationX: x, y: y))),
                         with: .color(c(k.0, k.1, k.2, 0.9 * edge(x, y))))
            }
        default:
            break
        }
    }
}

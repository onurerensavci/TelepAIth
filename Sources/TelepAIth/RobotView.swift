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
            AvatarStage(model: avatar.current, alignLeft: avatar.alignLeft, bubbleBelow: avatar.bubbleBelow,
                        health: avatar.health, locked: avatar.locked, minis: avatar.minis, focus: avatar.focus,
                        approval: avatar.approval, pointer: avatar.pointer, extras: avatar.extras,
                        extrasPoppedAt: avatar.extrasPoppedAt, chatList: avatar.chatList,
                        usage: avatar.usage, paused: avatar.paused, calm: avatar.calm)
                .id(avatar.current.source)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
        .padding(Layout.baseMargin)
        .frame(width: Layout.baseWindowSize.width, height: Layout.baseWindowSize.height, alignment: frameAlignment)
        .coordinateSpace(name: "avatar")
        .onPreferenceChange(BubbleFrameKey.self) { frame in avatar.bubbleFrame = frame }
        .onPreferenceChange(ApprovalFramesKey.self) { frames in avatar.approvalFrames = frames }
        .onPreferenceChange(MiniFramesKey.self) { frames in avatar.miniFrames = frames }
        .onPreferenceChange(ChatRowFramesKey.self) { frames in avatar.chatRowFrames = frames }
        // Robot %100 boyutta çizilir, ayardaki boyuta göre ölçeklenir
        .scaleEffect(avatar.scale, anchor: .topLeading)
        .frame(width: Layout.baseWindowSize.width * avatar.scale, height: Layout.baseWindowSize.height * avatar.scale,
               alignment: .topLeading)
    }
}

/// Onay düğmelerinin pencere içindeki yeri (tıklamayı yakalamak için AppKit tarafına iletilir).
struct ApprovalFramesKey: PreferenceKey {
    static var defaultValue: [ApprovalChoice: CGRect] = [:]
    static func reduce(value: inout [ApprovalChoice: CGRect], nextValue: () -> [ApprovalChoice: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Sohbet listesindeki satırların pencere içindeki yeri (tıklayınca o sohbete gitmek için AppKit tarafına iletilir).
struct ChatRowFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Minik kafaların pencere içindeki yeri (AI adına göre; tıklayınca o AI'a geçmek için AppKit tarafına iletilir).
struct MiniFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Balonun pencere içindeki yeri (tıklamayı yakalamak için AppKit tarafına iletilir).
struct BubbleFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct AvatarStage: View {
    @ObservedObject var model: RobotModel
    let alignLeft: Bool
    let bubbleBelow: Bool
    let health: Health
    let locked: Bool
    let minis: [RobotModel.MiniSession]
    let focus: Bool
    var approval: ApprovalPrompt? = nil
    var pointer: PointerTracker? = nil
    var extras: [RobotState] = []
    var extrasPoppedAt: Date = .distantPast
    var chatList: [RobotModel.ChatRow]? = nil
    /// Kullanım sınırları (halkalar, sohbet listesinin başı)
    var usage: [UsageWindow] = []
    /// Sakin çizim: hiçbir şey olmuyorken kafa yeniden çizilmez
    var paused = false
    var calm = CalmState()

    /// Odak modunda sadece seni bekleyen, hata veren ya da robotun kendi söylediği şeyler görünür
    private var urgent: Bool { model.state == .waiting || model.state == .error || model.bubbleIsExplicit }

    var body: some View {
        VStack(alignment: alignLeft ? .leading : .trailing, spacing: 2) {
            if bubbleBelow {
                headRow
                bubble
            } else {
                bubble
                headRow
            }
        }
        .opacity(focus && !urgent ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.18), value: model.bubbleText)
        .animation(.easeInOut(duration: 0.3), value: focus)
    }

    @ViewBuilder
    private var bubble: some View {
        if let rows = chatList, !rows.isEmpty {
            ChatListBubble(rows: rows, color: Color(nsColor: model.theme.color), tailOnTop: bubbleBelow, tailLeading: alignLeft,
                           usage: usage,
                           hoverIndex: { [weak avatar = pointer?.avatar] in avatar?.chatRowIndex(at: NSEvent.mouseLocation) })
                .background(GeometryReader { g in
                    Color.clear.preference(key: BubbleFrameKey.self, value: g.frame(in: .named("avatar")))
                })
                .transition(.opacity)
        } else if let text = model.bubbleText, !focus || urgent {
            BubbleView(title: model.theme.displayName,
                       subtitle: model.bubbleSubtitle,
                       text: text,
                       color: Color(nsColor: model.theme.color),
                       tailOnTop: bubbleBelow,
                       tailLeading: alignLeft,
                       clickable: !(model.target?.isEmpty ?? true),
                       approval: approval)
                .background(GeometryReader { g in
                    Color.clear.preference(key: BubbleFrameKey.self, value: g.frame(in: .named("avatar")))
                })
                .transition(.opacity)
        }
    }

    /// Kafa ve yanında (pencerenin içine doğru) diğer oturumların minik kafaları
    private var headRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if alignLeft {
                head
                minisView
            } else {
                minisView
                head
            }
        }
    }

    @ViewBuilder
    private var minisView: some View {
        if Preferences.miniHeads && !minis.isEmpty {
            MiniHeadsView(minis: minis)
                .padding(.bottom, 14)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var head: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
            HeadFigure(model: model,
                       time: context.date.timeIntervalSinceReferenceDate,
                       stillness: calm.stillness(at: context.date.timeIntervalSinceReferenceDate),
                       usage: usage,
                       look: alignLeft ? 2.5 : -2.5,
                       health: health,
                       pointer: pointer,
                       bubbleBelow: bubbleBelow,
                       extras: extras,
                       extrasPoppedAt: extrasPoppedAt)
        }
        .frame(width: Layout.baseHeadSize.width, height: Layout.baseHeadSize.height)
        .overlay(alignment: .topTrailing) {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 0.55, green: 0.52, blue: 0.66))
                    .padding(4)
                    .background(Circle().fill(Color(red: 0.97, green: 0.96, blue: 0.94)))
                    .offset(x: -2, y: 8)
            }
        }
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
    var clickable = false
    var approval: ApprovalPrompt? = nil

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

    @ViewBuilder
    private var card: some View {
        if let approval = approval, let info = approval.card {
            approvalCard(approval, info)
        } else {
            plainCard
        }
    }

    /// Onay balonu (Windows'ta DrawApprovalBubble): "‘shop’ seni bekliyor", "Bash kullanmak istiyor",
    /// kod kutusunda komut (en fazla iki satır), eşit genişlikte büyük düğmeler.
    private func approvalCard(_ approval: ApprovalPrompt, _ info: ApprovalCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(info.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(height: 15)
            Text(info.action)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.primary.opacity(0.92))
                .lineLimit(1)
                .padding(.leading, 14)
                .frame(height: 14)
            if let code = info.code {
                Text(code)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                    .padding(.top, 5)
            }
            ApprovalButtons(approval: approval, color: color)
                .padding(.top, 7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 248, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
    }

    private var plainCard: some View {
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
                if clickable {
                    Spacer(minLength: 4)
                    // Tıklayınca o pencereye gider
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            Text(text)
                .font(.system(size: approval != nil ? 10.5 : 11))
                .foregroundColor(.primary)
                .lineLimit(approval != nil ? 3 : 6)
                .fixedSize(horizontal: false, vertical: true)
            if let approval = approval {
                ApprovalButtons(approval: approval, color: color)
                    .padding(.top, 5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: approval != nil ? 248 : 220, alignment: .leading)   // düğme satırı sığsın
        .background(RoundedRectangle(cornerRadius: 12).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Sohbet listesi (kafaya tıklayınca)

/// Sohbetler: her satırda AI rengi, sohbetin adı ve "çalışıyor · 3 dk" gibi durum. Satıra tıklayınca o sohbete gidilir.
/// (Windows'taki DrawChatList'in aynısı; pencereye sığsın diye en fazla 4 satır.)
struct ChatListBubble: View {
    let rows: [RobotModel.ChatRow]
    let color: Color
    let tailOnTop: Bool
    let tailLeading: Bool
    /// Kullanım sınırları: listenin başında "Oturum %42 · 16:40'ta dolar"
    var usage: [UsageWindow] = []
    /// Farenin üstünde olduğu satır (koyulaşsın)
    var hoverIndex: () -> Int? = { nil }

    static let maxRows = 4
    private var fill: Color { Color(nsColor: .windowBackgroundColor).opacity(0.97) }

    var body: some View {
        VStack(alignment: tailLeading ? .leading : .trailing, spacing: 0) {
            if tailOnTop { tail.rotationEffect(.degrees(180)) }
            card
            if !tailOnTop { tail }
        }
        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
    }

    private var tail: some View {
        BubbleTail()
            .fill(fill)
            .frame(width: 14, height: 8)
            .padding(tailLeading ? .leading : .trailing, 43)
    }

    private var card: some View {
        // Fare üstündeki satırı izlemek için kendi saati (balon kafanın saatinin dışında)
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { _ in
            cardContent(hover: hoverIndex())
        }
    }

    private func cardContent(hover: Int?) -> some View {
        let shown = Array(rows.prefix(ChatListBubble.maxRows))
        return VStack(alignment: .leading, spacing: 0) {
            Text(loc("Sohbetler", "Chats") + (rows.count > shown.count ? " · +\(rows.count - shown.count)" : ""))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 3)
                .padding(.leading, 6)
            ForEach(usage, id: \.kind) { w in
                HStack(spacing: 6) {
                    Text(UsageLimits.line(w, now: Date()))
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.25))
                        Capsule().fill(UsageRing.tint(w.percent, normal: color)).frame(width: 34 * CGFloat(w.percent) / 100)
                    }
                    .frame(width: 34, height: 4)
                }
                .padding(.horizontal, 6)
                .frame(height: 14)
            }
            ForEach(Array(shown.enumerated()), id: \.element.sessionID) { index, row in
                let aiColor = Color(nsColor: Themes.shared.theme(for: row.source).color)
                let hovered = hover == index
                HStack(spacing: 6) {
                    Circle()
                        .fill(aiColor)
                        .frame(width: 6, height: 6)
                    Text(row.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    Text(row.status)
                        .font(.system(size: 9.5))
                        .foregroundColor(statusColor(row))
                        .lineLimit(1)
                        .fixedSize()
                }
                .opacity(hovered ? 0.82 : 1)
                .padding(.horizontal, 6)
                .frame(height: 20)
                // AI renginde hafif zemin (Claude turuncu, GPT mavi); fare üstündeyken biraz koyulaşır
                .background(RoundedRectangle(cornerRadius: 6).fill(aiColor.opacity(hovered ? 0.28 : 0.13)).padding(.vertical, 1))
                .contentShape(Rectangle())
                .background(GeometryReader { g in
                    Color.clear.preference(key: ChatRowFramesKey.self, value: [index: g.frame(in: .named("avatar"))])
                })
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .frame(width: 248, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
    }

    private func statusColor(_ row: RobotModel.ChatRow) -> Color {
        if row.state == .waiting { return Color(red: 0.95, green: 0.45, blue: 0.05) }
        if row.state.isWorking { return Color(red: 0.13, green: 0.47, blue: 0.95) }
        return .secondary
    }
}

// MARK: - Kafa (şapkasız, nokta matris gözlü)

struct HeadFigure: View {
    let model: RobotModel
    let time: TimeInterval
    /// 0 normal hareket, 1 tamamen dingin (sakin çizim ya da "hareketi azalt"): süzülme, sallanma durur; duruş kalır
    var stillness: Double = 0
    /// Kullanım sınırları: ayaklarının dibinde iki küçük halka
    var usage: [UsageWindow] = []
    let look: CGFloat
    let health: Health
    var pointer: PointerTracker? = nil
    var bubbleBelow = false
    var extras: [RobotState] = []
    var extrasPoppedAt: Date = .distantPast

    var body: some View {
        let state = model.state
        let base = model.theme.color
        let eyeColor = Color(nsColor: base.mix(.white, 0.18))   // gözler uygulamanın renginde
        let accent = Color(nsColor: base.mix(.white, 0.55))
        // Yüz değişince (ör. düşünüyor → bitti) 0,35 sn'de yumuşak geçiş
        let blend = IdleMotion.smooth((time - model.visualChangedAt.timeIntervalSinceReferenceDate) / 0.35)
        let prevState = model.previousState, prevMood = model.previousMood
        let still = stillness
        let idle = (state == .idle && model.mood == nil && still <= 0) ? IdleMotion.at(time) : IdleMotion()
        let hop = hopHeight * CGFloat(1 - still)
        let float = mix(mix(floatOffset(prevState, prevMood), floatOffset(state, model.mood), blend), floatOffset(state, model.mood, at: 0), still)
        let shake = (shakeOffset + nudgeOffset) * CGFloat(1 - still) + CGFloat(idle.head.dx)
        let skin = SkinStore.shared.image(source: model.source, state: state)
        let lift = hop - float + CGFloat(idle.head.lift)
        let tilt = Double(mix(mix(CGFloat(headTilt(prevState, prevMood)), CGFloat(headTilt(state, model.mood)), blend),
                              CGFloat(headTilt(state, model.mood, at: 0)), still)) + idle.head.tilt
        // Gözde simge (? soru, ! onay, ✓ bitti, % kota), boştayken imlece bakış, kış kostümü
        let glyph = model.eyeGlyph(at: Date(timeIntervalSinceReferenceDate: time))
        let prevGlyph: Character? = prevState == .waiting ? "!" : nil
        // Hiçbir sohbet çalışmıyorken ve son iş biteli 20 sn olunca gözler imleci izler
        let gaze = pointer?.sample(time: time, active: (pointer?.avatar?.gazeAllowed ?? false)
                                   && [.idle, .done, .error].contains(state) && model.mood == nil) ?? Gaze()
        let winter = Preferences.winterActive

        return ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.14))
                .frame(width: Swift.max(24, 58 - lift * 1.5), height: 6)
                .position(x: 50, y: 96)

            // Kullanım sınırları: ayaklarının dibinde iki küçük halka (solda oturum, sağda hafta)
            ForEach(usage, id: \.kind) { w in
                UsageRing(percent: w.percent, color: UsageRing.tint(w.percent, normal: Color(nsColor: base.mix(.white, 0.2))))
                    .frame(width: 11, height: 11)
                    .position(x: w.kind == "five_hour" ? 14 : 86, y: 94)
            }

            // Kota halkası (ClaudeBar): kalan kota kadar dolu, azsa kırmızı
            if let left = model.quotaLeft {
                QuotaRing(left: left, color: Color(nsColor: base.mix(.white, 0.25)))
                    .frame(width: 98, height: 98)
                    .position(x: 50, y: 50)
                    .offset(x: shake, y: -lift)
            }

            ZStack {
                if let skin = skin {
                    Image(nsImage: skin)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 96, height: 90)
                        .position(x: 50, y: 48)
                } else {
                    FaceView(state: state, mood: model.mood, time: time, look: look, eyeColor: eyeColor, health: health,
                             prevState: prevState, prevMood: prevMood, blend: blend, idle: idle,
                             glyph: glyph, prevGlyph: prevGlyph, gaze: gaze, winter: winter, theme: Color(nsColor: base))
                    // Diğer sohbetler: ekranın altında küçük ışıklar (mavi çalışıyor, turuncu seni bekliyor)
                    if !extras.isEmpty {
                        ExtraLightsView(extras: extras, time: time,
                                        popAge: time - extrasPoppedAt.timeIntervalSinceReferenceDate,
                                        color: Color(nsColor: base))
                    }
                }
            }
            .frame(width: 100, height: 100)
            .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.5, y: 0.9))
            .offset(x: shake, y: -lift)

            if state == .thinking || state == .delegating || state == .reading || state == .searching {
                WavesView(time: time, color: Color(nsColor: base.mix(.white, 0.08)))   // yayılan çizgiler AI'ın renginde
                    .offset(x: shake, y: -lift)
            }
            if isCelebrating || state == .editing || model.mood == .party || model.mood == .proud {
                SparklesView(time: time, color: accent, radius: state == .editing ? 40 : 50)
                    .offset(y: -lift)
            }
            if state == .sleeping {
                ZzzView(time: time)
            }
            if winter {
                SnowView(time: time)
                    .frame(width: 130, height: 140)
                    .position(x: 50, y: 45)
            }
            // Uzun süredir seni bekliyor: "!" rozeti
            if isNudging {
                ZStack {
                    Circle().fill(Color(red: 1.0, green: 0.6, blue: 0.2))
                    Text("!").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
                }
                .frame(width: 17, height: 17)
                .scaleEffect(1 + 0.12 * CGFloat(sin(time * 6)))
                .position(x: 12, y: 16)
                .offset(x: shake, y: -lift)
            }
        }
        .frame(width: 100, height: 100)
    }

    /// Seni 30 saniyeden uzun süredir bekliyor mu?
    private var waitAge: Double? {
        guard Preferences.waitReminders, model.state == .waiting, let since = model.waitingSince else { return nil }
        return time - since.timeIntervalSinceReferenceDate
    }

    private var isNudging: Bool { (waitAge ?? 0) > 30 }

    /// Beklerken 4 saniyede bir kısa bir sallanma: "hey, buradayım!"
    private var nudgeOffset: CGFloat {
        guard let age = waitAge, age > 30 else { return 0 }
        let phase = age.truncatingRemainder(dividingBy: 4)
        guard phase < 0.6 else { return 0 }
        return CGFloat(sin(phase * 40) * (1 - phase / 0.6)) * 4
    }

    // Havada süzülme
    private func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    private func floatOffset(_ state: RobotState, _ mood: Mood?, at t: Double? = nil) -> CGFloat {
        let time = t ?? self.time
        if mood == .scared { return CGFloat(sin(time * 40)) * 1.2 }
        switch state {
        case .idle: return CGFloat(sin(time * 1.6)) * 2.5
        case .running: return CGFloat(sin(time * 9)) * 1.5
        case .waiting: return CGFloat(sin(time * 5)) * 3
        case .sleeping: return -2 + CGFloat(sin(time * 0.8)) * 1.2
        case .done, .error: return 0
        default: return CGFloat(sin(time * 3.2)) * 3
        }
    }

    private func headTilt(_ state: RobotState, _ mood: Mood?, at t: Double? = nil) -> Double {
        let time = t ?? self.time
        switch mood {
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

/// Küçük dolum halkası (kullanım sınırı): tepeden saat yönünde
struct UsageRing: View {
    let percent: Int
    let color: Color

    /// Rahat → AI rengi, %60 sarı, %85 kırmızı
    static func tint(_ percent: Int, normal: Color) -> Color {
        if percent >= 85 { return Color(red: 0.95, green: 0.33, blue: 0.33) }
        if percent >= 60 { return Color(red: 0.96, green: 0.66, blue: 0.2) }
        return normal
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color(red: 0.5, green: 0.49, blue: 0.56).opacity(0.35), lineWidth: 2)
            Circle()
                .trim(from: 0, to: CGFloat(Swift.min(100, Swift.max(0, percent))) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct FaceView: View {
    let state: RobotState
    let mood: Mood?
    let time: TimeInterval
    let look: CGFloat
    let eyeColor: Color
    let health: Health
    var prevState: RobotState = .idle
    var prevMood: Mood? = nil
    var blend: Double = 1
    var idle = IdleMotion()
    var glyph: Character? = nil
    var prevGlyph: Character? = nil
    var gaze = Gaze()
    var winter = false
    var theme: Color = .purple

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
            DotEyes(state: state, mood: mood, look: look, time: time, color: eyeColor,
                    prevState: prevState, prevMood: prevMood, blend: blend, idle: idle,
                    glyph: glyph, prevGlyph: prevGlyph, gaze: gaze)
                .frame(width: 70, height: 44)
                .position(x: 50, y: 52)
            if winter {
                // Kış: bere (ponpon sağlık ışığı renginde yanar, sorun yoksa beyaz)
                BeanieView(theme: theme, glow: health == .ok ? nil : ledColor, glowOpacity: ledOpacity)
                    .frame(width: 100, height: 100)
            } else {
                ledView
            }
        }
    }

    @ViewBuilder
    private var ledView: some View {
        // Alında sağlık ışığı: yeşil yolunda, turuncu güncelleme var, kırmızı çalışmıyor
        ZStack {
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
        switch health {
        case .ok: return Color(red: 0.2, green: 0.83, blue: 0.47)       // yeşil
        case .update: return Color(red: 1.0, green: 0.6, blue: 0.2)     // turuncu
        case .broken: return Color(red: 0.97, green: 0.3, blue: 0.3)    // kırmızı
        }
    }

    private var ledOpacity: Double {
        switch health {
        case .ok: return state == .sleeping ? 0.45 : 0.85 + 0.15 * sin(time * 2)
        case .update: return 0.6 + 0.4 * sin(time * 3)
        case .broken: return sin(time * 6) > 0 ? 1 : 0.3
        }
    }
}

/// LED nokta matrisi gözler: her göz 14 × 18 minik noktadan oluşur.
/// Şekiller sürekli koordinatlarda tanımlı (göz merkezi 3,4; eski 7 × 9 ızgaranın birimleri),
/// her nokta kendi konumunda örneklenir; böylece çözünürlük artınca desenler pürüzsüzleşir.
struct DotEyes: View {
    let state: RobotState
    let mood: Mood?
    let look: CGFloat
    let time: TimeInterval
    let color: Color
    var prevState: RobotState = .idle
    var prevMood: Mood? = nil
    var blend: Double = 1
    var idle = IdleMotion()
    var glyph: Character? = nil
    var prevGlyph: Character? = nil
    var gaze = Gaze()

    private static let cols = 14
    private static let rows = 18
    private static let spacing: CGFloat = 1.75
    private static let dot: CGFloat = 1.3

    var body: some View {
        Canvas { context, size in
            let tint = (state == .error && mood == nil) ? Color(red: 1, green: 0.42, blue: 0.42) : color
            let dim = tint.opacity(0.09)
            let centers: [CGFloat] = [size.width / 2 - 14, size.width / 2 + 14]
            let midC = Double(DotEyes.cols - 1) / 2
            let midR = Double(DotEyes.rows - 1) / 2
            for (eye, cx) in centers.enumerated() {
                for r in 0..<DotEyes.rows {
                    for c in 0..<DotEyes.cols {
                        let x = cx + (CGFloat(c) - CGFloat(midC)) * DotEyes.spacing
                        let y = size.height / 2 + (CGFloat(r) - CGFloat(midR)) * DotEyes.spacing
                        let rect = CGRect(x: x - DotEyes.dot / 2, y: y - DotEyes.dot / 2, width: DotEyes.dot, height: DotEyes.dot)
                        // Eski 7 × 9 birimlerine çevir (merkez 3,4)
                        let u = (Double(c) - midC) / 2 + 3
                        let v = (Double(r) - midR) / 2 + 4
                        let b = brightness(u: u, v: v, eye: eye)
                        if b > 0.05 {
                            context.fill(Path(ellipseIn: rect.insetBy(dx: -0.8, dy: -0.8)), with: .color(tint.opacity(0.25 * b)))
                            context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(b)))
                        } else {
                            context.fill(Path(ellipseIn: rect), with: .color(dim))
                        }
                    }
                }
            }
        }
    }

    private var blinking: Bool {
        state != .waiting && mood == nil && idle.kind == .none && gaze.hover < 0.5 && time.truncatingRemainder(dividingBy: 4.2) < 0.12
    }

    /// Bir noktanın parlaklığı (0…1): yüz değiştiyse eskisiyle yenisi arasında yumuşak geçiş
    private func brightness(u: Double, v: Double, eye: Int) -> Double {
        let now = pattern(state: state, mood: mood, u: u, v: v, eye: eye, idle: idle, glyph: glyph, hover: gaze.hover, blinks: true)
        guard blend < 1 else { return now }
        let before = pattern(state: prevState, mood: prevMood, u: u, v: v, eye: eye, idle: IdleMotion(), glyph: prevGlyph, hover: 0, blinks: false)
        return before + (now - before) * blend
    }

    private func pattern(state: RobotState, mood: Mood?, u: Double, v: Double, eye: Int, idle: IdleMotion,
                         glyph: Character?, hover: Double, blinks: Bool) -> Double {
        // Gözde simge: ? soru soruyor, ! onay bekliyor, ✓ bitti, % kota azaldı
        if let g = glyph { return DotEyes.glyph(g, u, v) * (0.85 + 0.15 * sin(time * 6)) }
        // Boştayken imlece, değilse ekranın ortasına doğru bak
        let lookShift = (gaze.u ?? Double(look) / 2.5) + idle.look
        if let mood = mood {
            switch mood {
            case .pleased: return heart(u, v) * (0.8 + 0.2 * sin(time * 6))
            case .shocked: return capsule(u, v, cx: 3, cy: 4, rx: 2.9, ry: 4.2)
            case .nervous: return capsule(u, v, cx: 3 + sin(time * 14) * 1.1, cy: 4.5, rx: 1.2, ry: 2)
            case .scared: return capsule(u, v, cx: 3 + sin(time * 40) * 0.4, cy: 4, rx: 1.4, ry: 3.8)
            case .proud, .party: return arc(u, v, cx: 3, cy: 6.2, radius: 2.7)
            case .tired: return capsule(u, v, cx: 3, cy: 5.2, rx: 2.1, ry: 1.1) * 0.8
            case .dizzy: return spiral(u, v, eye: eye)
            case .denied: return capsule(u, v, cx: 3, cy: 6, rx: 1.7, ry: 1.3)
            }
        }
        if blinks && blinking { return capsule(u, v, cx: 3 + lookShift, cy: 4.5, rx: 2, ry: 0.5) }
        switch state {
        // Bitti / hata yüzü de (kimse çalışmıyorken) imlece doğru bakar
        case .done:
            return arc(u, v, cx: 3 + lookShift * 0.6, cy: 6.2 + gaze.v * 0.5, radius: 2.7)
        case .error:
            return cross(u - lookShift * 0.6, v - gaze.v * 0.5)
        case .sleeping:
            return (abs(v - 6) < 0.3 && abs(u - 3) <= 2.2) ? 0.5 : 0
        case .thinking:
            return capsule(u, v, cx: 3 + 0.9, cy: 2.8, rx: 1.5, ry: 2.6)
        case .reading, .searching:
            return capsule(u, v, cx: 3 + sin(time * 3) * 1.5, cy: 4.4, rx: 1.5, ry: 2.3)
        case .editing:
            return capsule(u, v, cx: 3 + lookShift * 0.5, cy: 5, rx: 1.9, ry: 1.5)
        case .running, .delegating:
            let shimmer = 0.75 + 0.25 * sin(time * 18 + u * 2.6 + v * 1.4)
            return capsule(u, v, cx: 3, cy: 4, rx: 1.6, ry: 2.8) * shimmer
        case .waiting:
            return capsule(u, v, cx: 3, cy: 4, rx: 2.5, ry: 3.9) * (0.75 + 0.25 * sin(time * 6))
        case .idle:
            // Üstüne gelince gözlerini kısıp gülümser
            let awake = idleEyes(u, v, eye: eye, lookShift: lookShift, idle: idle)
            return awake + (arc(u, v, cx: 3, cy: 6.2, radius: 2.7) - awake) * hover
        }
    }

    private func idleEyes(_ u: Double, _ v: Double, eye: Int, lookShift: Double, idle: IdleMotion) -> Double {
        let base = capsule(u, v, cx: 3 + lookShift, cy: 4 + gaze.v, rx: 1.7, ry: 3.3)
        switch idle.kind {
        case .wink where eye == idle.side:   // göz kırpma
            let closed = capsule(u, v, cx: 3 + lookShift, cy: 4.6, rx: 1.9, ry: 0.45)
            return base + (closed - base) * idle.env
        case .scan:   // iki gözün üstünden geçen tarama çizgisi
            let gx = Double(eye) * 7 + u
            let bar: Double = (abs(gx - (-0.5 + 14 * idle.p)) < 0.7 && abs(v - 4) < 3.4) ? 1 : 0
            return base + (Swift.max(bar, base * 0.25) - base) * idle.env
        case .yawn:   // esneme: gözler kısılır
            let squint = capsule(u, v, cx: 3, cy: 4.9, rx: 2.0, ry: 0.9 + 0.4 * sin(idle.p * .pi))
            return base + (squint - base) * idle.env
        default:
            return base
        }
    }

    // MARK: Göz simgeleri (nokta matriste çizilen işaretler; Windows'takiyle aynı)

    private static func seg(_ u: Double, _ v: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ w: Double) -> Double {
        let dx = bx - ax, dy = by - ay, l = dx * dx + dy * dy
        let t = l > 0 ? Swift.min(1, Swift.max(0, ((u - ax) * dx + (v - ay) * dy) / l)) : 0
        let px = ax + t * dx - u, py = ay + t * dy - v
        return px * px + py * py <= w * w ? 1 : 0
    }

    private static func dotAt(_ u: Double, _ v: Double, _ cx: Double, _ cy: Double, _ r: Double) -> Double {
        (u - cx) * (u - cx) + (v - cy) * (v - cy) <= r * r ? 1 : 0
    }

    private static func ring(_ u: Double, _ v: Double, _ cx: Double, _ cy: Double, _ r: Double, _ w: Double) -> Bool {
        abs(((u - cx) * (u - cx) + (v - cy) * (v - cy)).squareRoot() - r) < w
    }

    static func glyph(_ g: Character, _ u: Double, _ v: Double) -> Double {
        switch g {
        case "!":
            return Swift.max(seg(u, v, 3, 0.8, 3, 5.0, 0.62), dotAt(u, v, 3, 6.9, 0.72))
        case "?":
            let top: Double = ring(u, v, 3, 2.4, 1.55, 0.55) && (v <= 2.4 || (u >= 3 && v <= 3.3)) ? 1 : 0
            return [top, seg(u, v, 4.3, 3.3, 3.0, 4.4, 0.58), seg(u, v, 3.0, 4.4, 3.0, 5.1, 0.58), dotAt(u, v, 3, 6.9, 0.72)].max() ?? 0
        case "✓":
            return Swift.max(seg(u, v, 0.9, 4.4, 2.5, 6.1, 0.6), seg(u, v, 2.5, 6.1, 5.3, 1.9, 0.6))
        case "%":
            let a: Double = ring(u, v, 1.6, 1.9, 0.75, 0.4) ? 1 : 0
            let b: Double = ring(u, v, 4.4, 6.1, 0.75, 0.4) ? 1 : 0
            return [a, b, seg(u, v, 5.0, 1.0, 1.0, 7.0, 0.45)].max() ?? 0
        default:
            return 0
        }
    }

    private func capsule(_ u: Double, _ v: Double, cx: Double, cy: Double, rx: Double, ry: Double) -> Double {
        let dx = (u - cx) / rx
        let dy = (v - cy) / ry
        let d = dx * dx + dy * dy
        if d <= 1 { return 1 }
        if d <= 1.22 { return 0.35 }
        return 0
    }

    /// ^ biçimi (mutlu)
    private func arc(_ u: Double, _ v: Double, cx: Double, cy: Double, radius: Double) -> Double {
        guard v <= cy else { return 0 }
        let d = ((u - cx) * (u - cx) + (v - cy) * (v - cy)).squareRoot()
        return abs(d - radius) < 0.45 ? 1 : 0
    }

    private func cross(_ u: Double, _ v: Double) -> Double {
        let x = u - 3
        let y = v - 4
        guard abs(x) <= 2.6 && abs(y) <= 2.6 else { return 0 }
        return (abs(x - y) < 0.4 || abs(x + y) < 0.4) ? 1 : 0
    }

    /// Kalp (memnun): (x² + y² − 1)³ − x²·y³ ≤ 0
    private func heart(_ u: Double, _ v: Double) -> Double {
        let x = (u - 3) / 2.6
        let y = -(v - 4.3) / 2.6
        let a = x * x + y * y - 1
        return a * a * a - x * x * y * y * y <= 0 ? 1 : 0
    }

    /// Dönen halka (başı dönmüş)
    private func spiral(_ u: Double, _ v: Double, eye: Int) -> Double {
        let x = u - 3
        let y = v - 4
        let d = (x * x + y * y).squareRoot()
        guard abs(d - 2.4) < 0.5 else { return d < 0.45 ? 1 : 0 }
        let angle = atan2(y, x)
        let phase = time * (eye == 0 ? 6 : -6)
        return 0.35 + 0.65 * max(0, cos(angle - phase))
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

/// İzin sorusu düğmeleri: eşit genişlikte İzin ver (AI renginde) · Hep izin ver · Reddet.
/// Tıklamayı AppKit tarafı yakalar (yerlerini bildiriyoruz). (Windows'ta DrawApprovalBubble'daki düğmeler)
struct ApprovalButtons: View {
    let approval: ApprovalPrompt
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            // "İzin ver" sadece tamamı balonda okunabilen kısa kabuk komutunda; gerisi balondan sadece reddedilir
            if approval.canAllow {
                button(.allow, loc("İzin ver", "Allow"), fill: allowFill, text: allowText)
            }
            if approval.canAllow && approval.hasAlways {
                button(.always, loc("Hep izin ver", "Always"), fill: Color.primary.opacity(0.1), text: color)
            }
            button(.deny, loc("Reddet", "Deny"), fill: Color.primary.opacity(0.1), text: .primary)
        }
        .frame(height: 23)
    }

    /// AI rengi biraz açılmış; üstündeki yazı renge göre koyu ya da beyaz
    private var allowFill: Color {
        Color(nsColor: (NSColor(color).usingColorSpace(.sRGB) ?? .systemOrange).blended(withFraction: 0.12, of: .white) ?? .systemOrange)
    }

    private var allowText: Color {
        let c = NSColor(allowFill).usingColorSpace(.sRGB) ?? .white
        let luma = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luma > 150.0 / 255.0 ? Color(red: 0.12, green: 0.11, blue: 0.15) : .white
    }

    private func button(_ choice: ApprovalChoice, _ label: String, fill: Color, text: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 7).fill(fill))
            .background(GeometryReader { g in
                Color.clear.preference(key: ApprovalFramesKey.self, value: [choice: g.frame(in: .named("avatar"))])
            })
    }
}

/// Boştayken arada bir yapılan küçük hareketler: etrafa bakma, göz kırpma, sallanma, zıplama, tarama, esneme.
/// 8 sn'lik dilimlerin çoğunda bir tane; başı ve sonu yumuşak (env), süzülmenin üstüne eklenir. Windows'ta da aynısı.
struct IdleMotion {
    enum Kind { case none, lookAround, wink, sway, bounce, scan, yawn }
    var kind: Kind = .none
    var p: Double = 0      // 0…1 ilerleme
    var env: Double = 0    // 0…1 yumuşak giriş/çıkış
    var side = 0

    static func smooth(_ x: Double) -> Double {
        let t = Swift.min(1, Swift.max(0, x))
        return t * t * (3 - 2 * t)
    }

    static func at(_ time: Double) -> IdleMotion {
        let slot = 8.0
        let n = Int64(floor(time / slot))
        let local = time - Double(n) * slot
        var x = UInt32(truncatingIfNeeded: n &* 2654435761)
        x ^= x >> 15
        x = x &* 2246822519
        x ^= x >> 13
        let h = Int(x & 0x7fffffff)
        if (h / 3) % 10 < 3 { return IdleMotion() }   // bazı dilimler sakin geçsin
        let kinds: [Kind] = [.lookAround, .wink, .sway, .bounce, .scan, .yawn]
        let kind = kinds[h % kinds.count]
        let dur: Double
        switch kind {
        case .wink: dur = 1.2
        case .bounce: dur = 1.6
        case .scan: dur = 2.2
        case .yawn: dur = 2.6
        default: dur = 3.0
        }
        let start = 2.0 + Double((h / 7) % 3)
        guard local >= start, local <= start + dur else { return IdleMotion() }
        let p = (local - start) / dur
        let env = kind == .wink ? smooth((p - 0.2) / 0.15) * smooth((0.8 - p) / 0.15)
                                : smooth(p / 0.2) * smooth((1 - p) / 0.2)
        return IdleMotion(kind: kind, p: p, env: env, side: (h / 13) % 2)
    }

    /// Kafanın ek hareketi: yatay kayma, ek yükseklik, ek eğim (derece)
    var head: (dx: Double, lift: Double, tilt: Double) {
        switch kind {
        case .lookAround: return (0, 0, sin(p * .pi * 2) * 4 * env)
        case .wink: return (0, 0, (side == 0 ? -5 : 5) * env)
        case .sway: return (sin(p * .pi * 4) * 2.5 * env, 0, sin(p * .pi * 4) * 6 * env)
        case .bounce: return (0, abs(sin(p * .pi * 3)) * 7 * env, 0)
        case .yawn: return (0, -3 * env, sin(p * .pi) * 3 * env)
        default: return (0, 0, 0)
        }
    }

    /// Göz bakışına ek kayma (etrafa bakarken)
    var look: Double { kind == .lookAround ? sin(p * .pi * 2) * 1.6 * env : 0 }
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


// MARK: - Kota halkası

struct QuotaRing: View {
    let left: Int
    let color: Color

    var body: some View {
        let fraction = CGFloat(Swift.max(0, Swift.min(100, left))) / 100
        let tint = left <= 20 ? Color(red: 0.97, green: 0.35, blue: 0.35) : color
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Minik kafalar (aynı anda çalışan diğer oturumlar)

struct MiniHeadsView: View {
    let minis: [RobotModel.MiniSession]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(Array(minis.prefix(4).enumerated()), id: \.element.id) { index, mini in
                    MiniHead(mini: mini, time: time + Double(index) * 0.7)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: MiniFramesKey.self,
                                                   value: [mini.source: g.frame(in: .named("avatar")).insetBy(dx: -3, dy: -3)])
                        })
                        .help(mini.label)
                }
                if minis.count > 4 {
                    Text("+\(minis.count - 4)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(red: 0.55, green: 0.52, blue: 0.66))
                }
            }
        }
    }
}

struct MiniHead: View {
    let mini: RobotModel.MiniSession
    let time: TimeInterval

    var body: some View {
        let color = Color(nsColor: Themes.shared.theme(for: mini.source).color.mix(.white, 0.18))
        let waiting = mini.state == .waiting
        let bob = CGFloat(sin(time * (waiting ? 5 : 3))) * (waiting ? 2 : 1.2)
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.97, blue: 0.95),
                                              Color(red: 0.86, green: 0.84, blue: 0.92)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 22, height: 18)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.16))
                .frame(width: 17, height: 10)
                .offset(y: 1)
            HStack(spacing: 4) {
                Capsule().fill(color).frame(width: 3, height: waiting ? 6 : 5)
                Capsule().fill(color).frame(width: 3, height: waiting ? 6 : 5)
            }
            .offset(y: 1)
            if waiting {
                Circle().fill(Color(red: 1.0, green: 0.6, blue: 0.2))
                    .frame(width: 6, height: 6)
                    .offset(x: 10, y: -8)
            }
        }
        .offset(y: -bob)
        .shadow(color: Color.black.opacity(0.12), radius: 1.5, x: 0, y: 1)
    }
}

// MARK: - İmlece bakış

/// Gözlerin bakışı: u/v imlece doğru kayma (nil: ekranın ortasına bak), hover: imleç kafanın üstünde (0…1)
struct Gaze {
    var u: Double? = nil
    var v: Double = 0
    var hover: Double = 0
}

/// İmlecin kafaya göre yeri: boştayken gözler imleci izler, üstüne gelince gözlerini kısıp gülümser.
/// Kareler arasında yumuşak geçiş için durum tutar (RobotAvatar'da bir tane).
final class PointerTracker {
    weak var avatar: RobotAvatar?
    private var hover = 0.0
    private var last = 0.0

    func sample(time: Double, active: Bool) -> Gaze {
        let dt = Swift.min(0.1, Swift.max(0, time - last))
        last = time
        var gaze = Gaze()
        var target = 0.0
        if active, let avatar = avatar {
            let mouse = NSEvent.mouseLocation
            let s = Double(avatar.scale)
            let dx = Double(mouse.x - avatar.head.x), dy = Double(mouse.y - avatar.head.y)
            let dist = (dx * dx + dy * dy).squareRoot()
            func clamp(_ x: Double) -> Double { Swift.min(1, Swift.max(-1, x)) }
            if dist < 900 * s {
                gaze.u = clamp(dx / (220 * s)) * 1.6
                gaze.v = -clamp(dy / (220 * s)) * 0.9   // ekran koordinatında y yukarı doğru artar
            }
            if dist < Double(Layout.baseHeadSize.width) * s * 0.45 { target = 1 }
        }
        hover += (target - hover) * Swift.min(1, dt * 8)
        gaze.hover = hover
        return gaze
    }
}

// MARK: - Diğer sohbetlerin ışıkları

/// Kafalarda görünmeyen her sohbet için ekranın altında bir nokta (en fazla 4; Windows'takinin aynısı).
/// Açık renkli yüzde kaybolmasın diye koyu tonlarda; yeni sohbet gelince kısa bir zıplamayla belirir.
struct ExtraLightsView: View {
    let extras: [RobotState]
    let time: TimeInterval
    var popAge: Double = 99
    /// AI'ın rengi (Claude turuncu, GPT mavi)
    var color: Color = .orange

    // Açık renkli yüzde çerçevesiz de seçilsin diye koyu tonlar
    var body: some View {
        Canvas { ctx, _ in
            let n = Swift.min(4, extras.count)
            guard n > 0 else { return }
            let gap = 9.0, cy = 80.0
            let bump = popAge >= 0 && popAge < 0.45 ? sin(popAge / 0.45 * .pi) : 0
            var c = ctx
            c.translateBy(x: 50, y: cy)
            c.scaleBy(x: 1 + 0.3 * bump, y: 1 + 0.3 * bump)
            c.translateBy(x: -50, y: -cy)
            for i in 0..<n {
                // AI'ın kendi renginde; seni bekleyen hızlı yanıp söner
                let isWaiting = extras[i] == .waiting
                let pulse = isWaiting ? 0.3 + 0.7 * (0.5 + 0.5 * sin(time * 9))
                    : 0.65 + 0.35 * (0.5 + 0.5 * sin(time * 3.2 + Double(i) * 1.3))
                let cx = 50 + (Double(i) - Double(n - 1) / 2) * gap
                c.fill(Path(ellipseIn: CGRect(x: cx - 3.0, y: cy - 3.0, width: 6.0, height: 6.0)),
                       with: .color(color.opacity(pulse)))
                c.fill(Path(ellipseIn: CGRect(x: cx - 1.7, y: cy - 1.7, width: 1.8, height: 1.8)),
                       with: .color(Color.white.opacity(0.55 * pulse)))
            }
        }
        .frame(width: 100, height: 100)
        .allowsHitTesting(false)
    }
}

// MARK: - Kış kostümü

/// Bere: uygulamanın renginde, beyaz kenarlı ve ponponlu (ponpon sorun varsa sağlık ışığı renginde yanar)
struct BeanieView: View {
    let theme: Color
    var glow: Color? = nil
    var glowOpacity: Double = 1

    var body: some View {
        Canvas { ctx, _ in
            let edge = Color(red: 0.54, green: 0.51, blue: 0.65)
            let wool = Color(red: 0.965, green: 0.953, blue: 0.933)
            var dome = Path()
            dome.move(to: CGPoint(x: 15, y: 23))
            dome.addCurve(to: CGPoint(x: 50, y: 1), control1: CGPoint(x: 15, y: 8), control2: CGPoint(x: 30, y: 1))
            dome.addCurve(to: CGPoint(x: 85, y: 23), control1: CGPoint(x: 70, y: 1), control2: CGPoint(x: 85, y: 8))
            dome.closeSubpath()
            ctx.fill(dome, with: .color(theme))
            for x: CGFloat in [32, 41, 50, 59, 68] {
                var rib = Path()
                rib.move(to: CGPoint(x: x, y: x == 50 ? 5 : 8))
                rib.addLine(to: CGPoint(x: x, y: 19))
                ctx.stroke(rib, with: .color(Color.black.opacity(0.18)), lineWidth: 1.2)
            }
            let band = Path(roundedRect: CGRect(x: 11, y: 17, width: 78, height: 10), cornerRadius: 5)
            ctx.fill(band, with: .color(wool))
            ctx.stroke(band, with: .color(edge), lineWidth: 1)
            if let glow = glow {
                ctx.fill(Path(ellipseIn: CGRect(x: 41, y: -7, width: 18, height: 18)), with: .color(glow.opacity(0.35 * glowOpacity)))
            }
            let pompom = Path(ellipseIn: CGRect(x: 44.5, y: -3.5, width: 11, height: 11))
            ctx.fill(pompom, with: .color(glow.map { $0.opacity(Swift.max(0.5, glowOpacity)) } ?? wool))
            ctx.stroke(pompom, with: .color(edge), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Kafanın çevresinde yağan kar (alan 130 × 140; kafa alanına göre -15, -25'ten başlar)
struct SnowView: View {
    let time: TimeInterval

    var body: some View {
        Canvas { ctx, _ in
            for i in 0..<12 {
                let speed = Double(9 + i % 4 * 3)
                let y = (time * speed + Double(i * 37)).truncatingRemainder(dividingBy: 140) - 25
                let x = Double(i * 53 % 130) - 15 + sin(time * 0.9 + Double(i)) * 5
                let r = 0.9 + Double(i % 3) * 0.4
                let o = 0.75 * Swift.min(1, (115 - y) / 30)
                ctx.fill(Path(ellipseIn: CGRect(x: x + 15 - r, y: y + 25 - r, width: r * 2, height: r * 2)),
                         with: .color(Color.white.opacity(o)))
            }
        }
        .allowsHitTesting(false)
    }
}

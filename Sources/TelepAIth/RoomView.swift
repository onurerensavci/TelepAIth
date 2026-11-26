import AppKit
import Charts
import SwiftUI

/// Odanın uygulamadan istedikleri (AppController sağlar)
protocol RoomHost: AnyObject {
    var roomUsage: [UsageWindow] { get }
    var roomSource: String { get }
    func setUsageLine(on: Bool)
}

/// Robotun odası: solda robot ve seviye, sağda Gardırop · Başarımlar · Emek · Kullanım. (Windows'ta RoomWindow.cs)
final class RoomModel: ObservableObject {
    enum Tab: String, CaseIterable { case wardrobe, effects, achievements, effort, usage }

    weak var host: RoomHost?
    @Published var tab: Tab = .wardrobe
    @Published var type = "coder"
    /// Gardırop görünümü: tiplere göre (Polis, Kral…) ya da parçalara göre (Baş, Gözlük…; istediğin kombini yap)
    @Published var bySlot = false
    @Published var slot = "head"
    /// Seçili efekt: "auto", "off" ya da bir efekt
    @Published var effect = RoomModel.currentEffect
    @Published var days = 30
    @Published private(set) var progress = ProgressData()
    @Published private(set) var effort = DailyStats.shared.effort(today: Date(), days: 30)
    @Published private(set) var usage: [UsageWindow] = []
    @Published private(set) var source = "claude"
    @Published private(set) var worn: [String: String] = [:]
    private var timer: Timer?

    init(host: RoomHost) {
        self.host = host
        refresh()
    }

    func refresh() {
        progress = Progress.shared.snapshot()
        effort = DailyStats.shared.effort(today: Date(), days: days)
        usage = host?.roomUsage ?? []
        source = host?.roomSource ?? "claude"
        worn = Dictionary(uniqueKeysWithValues: Outfits.slots.compactMap { s in Preferences.outfit(s).map { (s, $0) } })
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setDays(_ d: Int) {
        days = d
        effort = DailyStats.shared.effort(today: Date(), days: d)
    }

    /// Parçayı tak / çıkar
    func toggle(_ item: OutfitItem) {
        guard Outfits.unlocked(item, progress) else { return }
        Preferences.setOutfit(item.slot, worn[item.slot] == item.id ? nil : item.id)
        refresh()
    }

    static var currentEffect: String {
        let c = Preferences.costume
        return c == "off" || Effects.all.contains { $0.id == c } ? c : "auto"
    }

    func setEffect(_ id: String) {
        Preferences.costume = id
        effect = id
    }

    func takeOffAll() {
        Outfits.takeOffAll()
        refresh()
    }

    func takeOff(_ slot: String) {
        Preferences.setOutfit(slot, nil)
        refresh()
    }

    /// Tamamlanan tipin bütün parçalarını giy
    func wearType(_ type: String) {
        Outfits.wearType(type, progress)
        refresh()
    }

    var wornItems: [OutfitItem] { Outfits.worn(progress) }
    var themeColor: NSColor { Themes.shared.theme(for: source).color }
    var accent: Color { Color(nsColor: themeColor) }
}

final class RoomWindow: NSObject, NSWindowDelegate {
    static let shared = RoomWindow()
    private var window: NSWindow?
    private var model: RoomModel?

    func show(host: RoomHost) {
        if window == nil {
            let model = RoomModel(host: host)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 780, height: 520)
            w.contentView = NSHostingView(rootView: RoomView(model: model))
            w.delegate = self
            w.center()
            window = w
            self.model = model
        }
        window?.title = loc("Robotun odası", "Robot's room")
        model?.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
    }
}

struct RoomView: View {
    @ObservedObject var model: RoomModel

    var body: some View {
        HStack(spacing: 0) {
            RoomSidePanel(model: model)
                .frame(width: 250)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                RoomTabs(model: model)
                Divider()
                ScrollView {
                    Group {
                        switch model.tab {
                        case .wardrobe: WardrobeTab(model: model)
                        case .effects: EffectsTab(model: model)
                        case .achievements: AchievementsTab(model: model)
                        case .effort: EffortTab(model: model)
                        case .usage: UsageTab(model: model)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
    }
}

// MARK: - Sol panel: robot, seviye, sayılar, rozetler

struct RoomSidePanel: View {
    @ObservedObject var model: RoomModel

    var body: some View {
        let p = model.progress
        let next = Levels.next(p)
        let done = Achievements.all.filter { $0.done(p) }
        VStack(alignment: .leading, spacing: 14) {
            RoomRobotPreview(source: model.source, outfit: model.wornItems)
                .frame(maxWidth: .infinity)
                .frame(height: 190)
            Text(loc("Seviye \(Levels.level(p))", "Level \(Levels.level(p))"))
                .font(.system(size: 24, weight: .bold))
            VStack(alignment: .leading, spacing: 4) {
                RoomBar(fraction: next.fraction, color: model.accent)
                Text(loc("sonraki seviyeye \(next.left) XP", "\(next.left) XP to next level"))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                RoomStat(value: "\(p.streak)", label: loc("gün seri", "day streak"))
                RoomStat(value: "\(DailyStats.shared.turnsOn(Date()))", label: loc("bugün tur", "turns today"))
                RoomStat(value: "\(p.activeDays)", label: loc("aktif gün", "active days"))
            }
            // Tamamlanan tipler (Polis, Kral…)
            let types = Outfits.completedTypes(p)
            if !types.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc("Tiplerin", "Your types")).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach(types) { t in
                            Text("\(t.emoji) \(t.name)")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(model.accent.opacity(0.18)))
                        }
                    }
                }
            }
            // Son açılan başarımlar
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 5), count: 10), alignment: .leading, spacing: 5) {
                ForEach(done.suffix(20)) { a in
                    AchievementIcon(achievement: a, done: true, size: 18)
                        .help(a.title + " · " + a.description)
                }
            }
            Spacer()
            Text(loc("Gerçek işle XP kazanır: her tur, düzenleme, çalışılan dakika ve aktif gün.",
                     "Earns XP from real work: every turn, edit, minute worked and active day."))
                .font(.system(size: 10.5)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            LinearGradient(colors: [model.accent.opacity(0.16), Color.clear], startPoint: .top, endPoint: .center)
        )
    }
}

/// Odadaki robot: gerçek kafa çizimi, takılı parçalarla
struct RoomRobotPreview: View {
    let source: String
    let outfit: [OutfitItem]
    /// Önizleme için boşta duran robotlar (AI başına bir tane)
    private static var models: [String: RobotModel] = [:]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { context in
            HeadFigure(model: previewModel, time: context.date.timeIntervalSinceReferenceDate,
                       outfit: outfit, look: 0, health: .ok)
                .frame(width: 100, height: 100)
                .scaleEffect(1.55)
        }
    }

    private var previewModel: RobotModel {
        if let m = RoomRobotPreview.models[source] { return m }
        let m = RobotModel(source: source)
        RoomRobotPreview.models[source] = m
        return m
    }
}

struct RoomStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .semibold))
            Text(label).font(.system(size: 10.5)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RoomBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color).frame(width: Swift.max(0, Swift.min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Sekmeler

struct RoomTabs: View {
    @ObservedObject var model: RoomModel

    var body: some View {
        let p = model.progress
        HStack(spacing: 22) {
            tab(.wardrobe, loc("Gardırop", "Wardrobe"), "\(Outfits.all.filter { Outfits.unlocked($0, p) }.count)/\(Outfits.all.count)")
            tab(.effects, loc("Efektler", "Effects"), nil)
            tab(.achievements, loc("Başarımlar", "Achievements"), "\(Achievements.all.filter { $0.done(p) }.count)/\(Achievements.all.count)")
            tab(.effort, loc("Emek", "Effort"), nil)
            tab(.usage, loc("Kullanım", "Usage"), nil)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func tab(_ t: RoomModel.Tab, _ title: String, _ count: String?) -> some View {
        let selected = model.tab == t
        return Button { model.tab = t } label: {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundColor(selected ? .primary : .secondary)
                    if let count = count {
                        Text(count).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                Rectangle().fill(selected ? model.accent : Color.clear).frame(height: 2)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Gardırop

struct WardrobeTab: View {
    @ObservedObject var model: RoomModel

    var body: some View {
        let p = model.progress
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                // Tiplere göre (Polis, Kral…) ya da parçalara göre (Baş, Gözlük…): her yuvadan istediğini seç, kendi kombinini yap
                Picker("", selection: $model.bySlot) {
                    Text(loc("Tipler", "Sets")).tag(false)
                    Text(loc("Parçalar", "Pieces")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.bottom, 6)
                if model.bySlot {
                    ForEach(Outfits.slots, id: \.self) { slot in
                        let items = Outfits.all.filter { $0.slot == slot }
                        let open = items.filter { Outfits.unlocked($0, p) }.count
                        listRow(selected: model.slot == slot, title: Outfits.slotName(slot), emoji: nil,
                                trailing: "\(open)/\(items.count)", done: false) { model.slot = slot }
                    }
                } else {
                    ForEach(Outfits.types) { t in
                        let items = Outfits.items(of: t.id)
                        let open = items.filter { Outfits.unlocked($0, p) }.count
                        listRow(selected: model.type == t.id, title: t.name, emoji: t.emoji,
                                trailing: "\(open)/\(items.count)", done: open == items.count) { model.type = t.id }
                    }
                }
                Divider().padding(.vertical, 6)
                Button(loc("Hepsini Çıkar", "Take All Off")) { model.takeOffAll() }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                    .padding(.leading, 10)
            }
            .frame(width: 170)

            if model.bySlot {
                slotPage(p)
            } else if let t = Outfits.findType(model.type) {
                typePage(t, p)
            }
        }
    }

    private func listRow(selected: Bool, title: String, emoji: String?, trailing: String, done: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let emoji = emoji { Text(emoji).font(.system(size: 15)) }
                Text(title).font(.system(size: 12.5, weight: .medium))
                Spacer()
                if done {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundColor(model.accent)
                } else {
                    Text(trailing).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? model.accent.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var grid: [GridItem] { [GridItem(.adaptive(minimum: 104, maximum: 130), spacing: 10)] }

    @ViewBuilder
    private func card(_ item: OutfitItem, _ p: ProgressData, subtitle: String) -> some View {
        let isOpen = Outfits.unlocked(item, p)
        let selected = model.worn[item.slot] == item.id && isOpen
        Group {
            if item.legendary {
                LegendaryCard(item: item, open: isOpen, selected: selected, theme: model.themeColor, accent: model.accent)
            } else {
                WardrobeCard(title: item.name, subtitle: isOpen ? subtitle : Outfits.unlockHint(item),
                             selected: selected, locked: !isOpen, accent: model.accent) {
                    RoomMiniRobot(theme: model.themeColor, items: [item])
                }
            }
        }
        .onTapGesture { model.toggle(item) }
    }

    /// Parçalara göre: bir yuvanın bütün parçaları (her tipten), en başta "Hiçbiri"
    private func slotPage(_ p: ProgressData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Outfits.slotName(model.slot)).font(.system(size: 18, weight: .bold))
            Text(loc("Her yuvadan istediğini seç, kendi kombinini yap.", "Pick anything for each slot and make your own combo."))
                .font(.system(size: 11.5)).foregroundColor(.secondary)
            LazyVGrid(columns: grid, spacing: 10) {
                WardrobeCard(title: loc("Hiçbiri", "None"), subtitle: nil, selected: model.worn[model.slot] == nil,
                             locked: false, accent: model.accent) {
                    RoomMiniRobot(theme: model.themeColor, items: [])
                }
                .onTapGesture { model.takeOff(model.slot) }
                ForEach(Outfits.all.filter { $0.slot == model.slot }) { item in
                    let type = Outfits.findType(item.type)
                    card(item, p, subtitle: type.map { "\($0.emoji) \($0.name)" } ?? "")
                }
            }
        }
    }

    /// Tiplere göre: tipin 5 parçası, tamamlanınca "Hepsini Giy"
    private func typePage(_ t: OutfitType, _ p: ProgressData) -> some View {
        let items = Outfits.items(of: t.id)
        let open = items.filter { Outfits.unlocked($0, p) }.count
        let done = open == items.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(t.emoji).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.name).font(.system(size: 18, weight: .bold))
                    Text(done ? loc("Tamamlandı! \(t.name) tipi artık senin.", "Complete! The \(t.name) set is yours.")
                              : t.description + " · " + loc("5 parçayı topla, \(t.name) ol", "collect all 5 to become a \(t.name)"))
                        .font(.system(size: 11.5)).foregroundColor(.secondary)
                }
                Spacer()
                if done {
                    Button(loc("Hepsini Giy", "Wear All")) { model.wearType(t.id) }
                        .buttonStyle(.borderedProminent)
                        .tint(model.accent)
                }
            }
            RoomBar(fraction: Double(open) / Double(Swift.max(1, items.count)), color: model.accent)
            LazyVGrid(columns: grid, spacing: 10) {
                ForEach(items) { item in card(item, p, subtitle: Outfits.slotName(item.slot)) }
            }
        }
    }
}

/// Gizli ödül kartı: kilitliyken soru işareti ve parıltı, açılınca altın çerçeve ve "Efsanevi"
struct LegendaryCard: View {
    let item: OutfitItem
    let open: Bool
    let selected: Bool
    let theme: NSColor
    let accent: Color

    private static let gold = Color(red: 1, green: 0.82, blue: 0.36)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [LegendaryCard.gold.opacity(0.45 + 0.2 * sin(t * 2)), .clear],
                                             center: .center, startRadius: 2, endRadius: 40))
                        .frame(width: 84, height: 84)
                    ForEach(0..<4, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: i % 2 == 0 ? 8 : 11, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(0.25 + 0.75 * Swift.max(0, sin(t * 2.2 + Double(i) * 1.6)))
                            .offset(x: [-30, 28, -24, 31][i], y: [-24, -20, 24, 18][i])
                    }
                    if open {
                        RoomMiniRobot(theme: theme, items: [item])
                    } else {
                        Text("?")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [.white, LegendaryCard.gold, Color(red: 0.85, green: 0.55, blue: 0.15)],
                                                            startPoint: .top, endPoint: .bottom))
                            .shadow(color: LegendaryCard.gold.opacity(0.8), radius: 6)
                            .scaleEffect(1 + 0.05 * sin(t * 2.4))
                            .frame(width: 70, height: 70)
                    }
                }
                .frame(height: 70)
                Text(open ? item.name : loc("Gizli ödül", "Secret reward"))
                    .font(.system(size: 11.5, weight: .bold)).lineLimit(1)
                    .foregroundColor(open ? LegendaryCard.gold : .primary)
                Text(open ? "✨ " + loc("Efsanevi", "Legendary") : "🔒 " + Outfits.unlockHint(item))
                    .font(.system(size: 9.5)).foregroundColor(.secondary).lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient(
                colors: [Color(red: 0.36, green: 0.24, blue: 0.5).opacity(0.35), Color(red: 0.55, green: 0.38, blue: 0.1).opacity(0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AngularGradient(
                colors: [LegendaryCard.gold, .white, LegendaryCard.gold, Color(red: 0.95, green: 0.55, blue: 0.2), LegendaryCard.gold],
                center: .center, angle: .degrees(t.truncatingRemainder(dividingBy: 4) * 90)), lineWidth: selected ? 3 : 1.6))
            .contentShape(Rectangle())
        }
    }
}

/// Gardırop kartında küçük robot ve parça
struct RoomMiniRobot: View {
    let theme: NSColor
    let items: [OutfitItem]

    var body: some View {
        ZStack {
            RobotShell()
            Capsule().fill(Color(nsColor: theme).opacity(0.9)).frame(width: 9, height: 16).position(x: 36, y: 52)
            Capsule().fill(Color(nsColor: theme).opacity(0.9)).frame(width: 9, height: 16).position(x: 64, y: 52)
            VisorGlass()
            OutfitView(items: items, theme: theme)
            Circle().fill(Color(red: 0.2, green: 0.83, blue: 0.47)).frame(width: 5, height: 5).position(x: 50, y: 22.5)
        }
        .frame(width: 100, height: 100)
        .scaleEffect(0.58)
        .frame(width: 70, height: 70)
    }
}

struct WardrobeCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let selected: Bool
    let locked: Bool
    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 4) {
            content()
                .opacity(locked ? 0.35 : 1)
                .overlay(alignment: .topTrailing) {
                    if locked { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundColor(.secondary) }
                }
            Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
            Text(subtitle ?? " ").font(.system(size: 9.5)).foregroundColor(.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? accent : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}

// MARK: Efektler

struct EffectsTab: View {
    @ObservedObject var model: RoomModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("Efektler", "Effects")).font(.system(size: 16, weight: .semibold))
            Text(loc("Robotun çevresinde dolaşır; bitince, beklerken ya da hata verince canlanıp parlar.",
                     "They float around the robot and light up when a task finishes, needs you or fails."))
                .font(.system(size: 11.5)).foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 150), spacing: 10)], spacing: 10) {
                card("auto", loc("Otomatik", "Automatic"), loc("Mevsim + duygular", "Season + feelings"), preview: Effects.season(Date()))
                card("off", loc("Kapalı", "Off"), nil, preview: nil)
                ForEach(Effects.all) { fx in card(fx.id, fx.name, nil, preview: fx.id) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("Otomatik mod nasıl seçer?", "How does Automatic choose?")).font(.system(size: 12.5, weight: .semibold))
                Text(loc("• Mevsime göre: kışın kar, baharda gökkuşağı, yazın güneş, sonbaharda yapraklar. Yılbaşında konfeti, sevgililer gününde kalpler.\n• Sohbette bir duygu geçerse ona göre tepki verir: aşk → kalpler, kutlama → konfeti, övgü → yıldızlar, üzüntü → yağmur, iyi geceler → ateş böcekleri.\n• Robot bir şey yaparken görünür, boşta kalınca yavaşça söner.",
                         "• By season: snow in winter, a rainbow in spring, sun in summer, leaves in autumn. Confetti on New Year's, hearts on Valentine's Day.\n• Reacts to feelings in a chat: love → hearts, celebration → confetti, praise → stars, sadness → rain, good night → fireflies.\n• Shows while the robot is busy and slowly fades when it's idle."))
                    .font(.system(size: 11.5)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        }
    }

    private func card(_ id: String, _ title: String, _ subtitle: String?, preview: String?) -> some View {
        let selected = model.effect == id
        return VStack(spacing: 4) {
            EffectPreview(effect: preview, theme: model.themeColor)
            Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
            Text(subtitle ?? " ").font(.system(size: 9.5)).foregroundColor(.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? model.accent : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { model.setEffect(id) }
    }
}

/// Efekt kartındaki canlı önizleme: küçük robot ve çevresinde efekt (arada bir canlanır)
struct EffectPreview: View {
    let effect: String?
    let theme: NSColor

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let e = pow(Swift.max(0, sin(t * 1.1)), 3)
            ZStack {
                if let fx = effect, Effects.isBackground(fx) { EffectView(id: fx, time: t, energy: e) }
                RobotShell()
                Capsule().fill(Color(nsColor: theme).opacity(0.9)).frame(width: 9, height: 16).position(x: 36, y: 52)
                Capsule().fill(Color(nsColor: theme).opacity(0.9)).frame(width: 9, height: 16).position(x: 64, y: 52)
                VisorGlass()
                Circle().fill(Color(red: 0.2, green: 0.83, blue: 0.47)).frame(width: 5, height: 5).position(x: 50, y: 22.5)
                if effect == "winter" {
                    SnowView(time: t).frame(width: 130, height: 140).position(x: 50, y: 45)
                }
                if let fx = effect, fx != "winter", !Effects.isBackground(fx) { EffectView(id: fx, time: t, energy: e) }
            }
            .frame(width: 100, height: 100)
            .scaleEffect(0.62)
            .frame(width: 92, height: 80)
        }
    }
}

// MARK: Başarımlar

/// Başarım simgesi: zorluk renginde altıgen-yuvarlak rozet; açık değilse soluk
struct AchievementIcon: View {
    let achievement: Achievement
    let done: Bool
    var size: CGFloat = 34

    static func tierColor(_ tier: Int) -> Color {
        switch tier {
        case 0: return Color(red: 0.85, green: 0.55, blue: 0.36)
        case 1: return Color(red: 0.42, green: 0.62, blue: 0.95)
        case 2: return Color(red: 0.95, green: 0.74, blue: 0.25)
        default: return Color(red: 0.66, green: 0.48, blue: 0.95)
        }
    }

    private var symbol: String {
        switch achievement.category {
        case "chat": return "bubble.left.fill"
        case "code": return "hammer.fill"
        case "time": return "clock.fill"
        default: return "person.2.fill"
        }
    }

    var body: some View {
        let color = AchievementIcon.tierColor(achievement.tier)
        ZStack {
            Circle().fill(done ? color : Color.secondary.opacity(0.25))
            Circle().stroke(Color.white.opacity(done ? 0.45 : 0.1), lineWidth: size * 0.06).padding(size * 0.08)
            Image(systemName: symbol).font(.system(size: size * 0.42, weight: .bold)).foregroundColor(.white.opacity(done ? 0.95 : 0.5))
        }
        .frame(width: size, height: size)
    }
}

struct AchievementsTab: View {
    @ObservedObject var model: RoomModel

    var body: some View {
        let p = model.progress
        let all = Achievements.all
        let done = all.filter { $0.done(p) }.count
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(done)").font(.system(size: 34, weight: .bold))
                        Text("/ \(all.count)").font(.system(size: 15)).foregroundColor(.secondary)
                    }
                    Text(loc("\(all.count) başarımın \(done) tanesi tamam", "\(done) of \(all.count) achievements done"))
                        .font(.system(size: 11.5)).foregroundColor(.secondary)
                    RoomBar(fraction: Double(done) / Double(all.count), color: model.accent)
                        .frame(width: 240)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<4, id: \.self) { tier in
                        let inTier = all.filter { $0.tier == tier }
                        let ok = inTier.filter { $0.done(p) }.count
                        HStack(spacing: 8) {
                            Text(Achievements.tierName(tier)).font(.system(size: 11.5, weight: .semibold)).frame(width: 70, alignment: .leading)
                            Text("\(ok)/\(inTier.count)").font(.system(size: 11)).foregroundColor(.secondary).frame(width: 36, alignment: .trailing)
                            RoomBar(fraction: inTier.isEmpty ? 0 : Double(ok) / Double(inTier.count),
                                    color: AchievementIcon.tierColor(tier), height: 4)
                                .frame(width: 160)
                        }
                    }
                }
            }
            ForEach(Achievements.categories, id: \.self) { cat in
                let items = all.filter { $0.category == cat }
                let ok = items.filter { $0.done(p) }.count
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(Achievements.categoryName(cat)).font(.system(size: 14, weight: .semibold))
                        Text("\(ok)/\(items.count)").font(.system(size: 11)).foregroundColor(.secondary)
                        RoomBar(fraction: Double(ok) / Double(items.count), color: model.accent, height: 3)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(items) { a in AchievementCard(achievement: a, progress: p) }
                    }
                }
            }
        }
    }
}

struct AchievementCard: View {
    let achievement: Achievement
    let progress: ProgressData

    var body: some View {
        let done = achievement.done(progress)
        let value = achievement.value(progress)
        HStack(alignment: .top, spacing: 10) {
            AchievementIcon(achievement: achievement, done: done)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(achievement.title).font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text(Achievements.tierName(achievement.tier)).font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(AchievementIcon.tierColor(achievement.tier))
                }
                Text(achievement.description).font(.system(size: 10.5)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !done && value > 0 {
                    HStack(spacing: 6) {
                        RoomBar(fraction: achievement.fraction(progress), color: AchievementIcon.tierColor(achievement.tier), height: 4)
                            .frame(width: 50)
                        Text("\(Int(value)) / \(Int(achievement.target))").font(.system(size: 9.5)).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(done ? 0.06 : 0.03)))
        .opacity(done ? 1 : 0.85)
    }
}

// MARK: Emek

struct EffortBar: Identifiable {
    let day: String
    let source: String
    let hours: Double
    var id: String { day + source }
}

struct EffortTab: View {
    @ObservedObject var model: RoomModel

    var body: some View {
        let e = model.effort
        let bars: [EffortBar] = e.days.flatMap { d in
            d.secondsBySource.filter { $0.value > 0 }.map { EffortBar(day: d.day, source: $0.key, hours: $0.value / 3600) }
        }
        let sources = e.bySource.sorted { $0.value > $1.value }.map(\.key)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.headline(model.days)).font(.system(size: 18, weight: .semibold))
                    if let top = e.topLine { Text(top).font(.system(size: 12.5)) }
                    Text(loc("\(e.projects.count) proje · \(e.totalTurns) tur · \(e.totalEdits) düzenleme",
                             "\(e.projects.count) projects · \(e.totalTurns) turns · \(e.totalEdits) edits"))
                        .font(.system(size: 11.5)).foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(get: { model.days }, set: { model.setDays($0) })) {
                    Text(loc("7 gün", "7 days")).tag(7)
                    Text(loc("30 gün", "30 days")).tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            Chart(bars) { b in
                BarMark(x: .value("day", b.day), y: .value("hours", b.hours))
                    .foregroundStyle(by: .value("AI", Themes.shared.theme(for: b.source).displayName))
                    .cornerRadius(2)
            }
            .chartForegroundStyleScale(domain: sources.map { Themes.shared.theme(for: $0).displayName },
                                       range: sources.map { Color(nsColor: Themes.shared.theme(for: $0).color) })
            .chartXAxis {
                AxisMarks(values: e.days.enumerated().filter { $0.offset % (model.days > 7 ? 7 : 1) == 0 || $0.offset == e.days.count - 1 }.map(\.element.day)) { v in
                    AxisValueLabel { Text(EffortTab.shortDay(v.as(String.self) ?? "")) }
                }
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisGridLine()
                    AxisValueLabel { Text(loc("\(v.as(Double.self).map { String(format: "%.0f", $0) } ?? "") sa", "\(v.as(Double.self).map { String(format: "%.0f", $0) } ?? "") h")) }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 190)
            // AI'lar
            HStack(spacing: 8) {
                ForEach(sources, id: \.self) { s in
                    HStack(spacing: 5) {
                        Circle().fill(Color(nsColor: Themes.shared.theme(for: s).color)).frame(width: 8, height: 8)
                        Text(Themes.shared.theme(for: s).displayName).font(.system(size: 11.5, weight: .semibold))
                        Text(shortDuration(e.bySource[s] ?? 0)).font(.system(size: 10.5)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }
            Divider()
            Text(loc("Projeler", "Projects")).font(.system(size: 14, weight: .semibold))
            if e.projects.isEmpty {
                Text(loc("Henüz proje yok. Claude Code ve Codex'teki işler burada projelerine göre görünür.",
                         "No projects yet. Work in Claude Code and Codex shows up here by project."))
                    .font(.system(size: 11.5)).foregroundColor(.secondary)
            } else {
                let maxSeconds = e.projects.first?.seconds ?? 1
                VStack(spacing: 6) {
                    HStack {
                        Text(loc("Proje", "Project")).frame(maxWidth: .infinity, alignment: .leading)
                        Text(loc("Ajan saati", "Agent time")).frame(width: 220, alignment: .leading)
                        Text(loc("Tur", "Turns")).frame(width: 50, alignment: .trailing)
                    }
                    .font(.system(size: 10.5, weight: .semibold)).foregroundColor(.secondary)
                    ForEach(e.projects.prefix(12)) { pr in
                        HStack {
                            Text(pr.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 8) {
                                RoomBar(fraction: pr.seconds / maxSeconds, color: model.accent, height: 5).frame(width: 110)
                                Text(shortDuration(pr.seconds)).font(.system(size: 11.5, weight: .semibold))
                                Text("%\(Int((pr.share * 100).rounded()))").font(.system(size: 10.5)).foregroundColor(.secondary)
                            }
                            .frame(width: 220, alignment: .leading)
                            Text("\(pr.turns)").font(.system(size: 11.5)).frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    /// "2026-11-26" → "26 Kas"
    static func shortDay(_ key: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key) else { return key }
        let out = DateFormatter()
        out.locale = Locale(identifier: Language.current == .tr ? "tr_TR" : "en_US")
        out.dateFormat = "d MMM"
        return out.string(from: d)
    }
}

// MARK: Kullanım

struct UsageTab: View {
    @ObservedObject var model: RoomModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(loc("Kullanım sınırları", "Usage limits")).font(.system(size: 16, weight: .semibold))
            if model.usage.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(loc("Claude Code'un oturum (5 saat) ve haftalık limitini burada ve robotun altında görmek için durum satırını bağla. Senin durum satırın varsa görünmeye devam eder.",
                             "Connect the status line to see Claude Code's session (5-hour) and weekly limits here and under the robot. Your own status line keeps showing."))
                        .font(.system(size: 12)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if UsageLine.isConnected {
                        Text(loc("Bağlı. Claude Code'da bir sonraki mesajda dolacak.", "Connected. It fills in with your next Claude Code message."))
                            .font(.system(size: 11.5))
                    } else {
                        Button(loc("Durum satırını bağla", "Connect the status line")) {
                            model.host?.setUsageLine(on: true)
                            model.refresh()
                        }
                    }
                }
            } else {
                HStack(spacing: 40) {
                    ForEach(model.usage, id: \.kind) { w in
                        VStack(spacing: 10) {
                            ZStack {
                                UsageRing(percent: w.percent, color: UsageRing.tint(w.percent, normal: model.accent))
                                    .scaleEffect(1)
                                    .frame(width: 96, height: 96)
                                Text("%\(w.percent)").font(.system(size: 22, weight: .bold))
                            }
                            Text(UsageLimits.name(w.kind)).font(.system(size: 13, weight: .semibold))
                            Text(UsageLimits.line(w, now: Date()).components(separatedBy: " · ").dropFirst().joined(separator: " · "))
                                .font(.system(size: 11.5)).foregroundColor(.secondary)
                        }
                    }
                }
            }
            Divider()
            Text(loc("Bugün", "Today")).font(.system(size: 16, weight: .semibold))
            let today = DailyStats.shared.today().filter { $0.value.turns > 0 }.sorted { $0.value.seconds > $1.value.seconds }
            if today.isEmpty {
                Text(loc("Bugün henüz bir iş bitmedi.", "No work finished yet today.")).font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                ForEach(today, id: \.key) { entry in
                    let src = entry.key
                    let d = entry.value
                    HStack(spacing: 10) {
                        Circle().fill(Color(nsColor: Themes.shared.theme(for: src).color)).frame(width: 10, height: 10)
                        Text(Themes.shared.theme(for: src).displayName).font(.system(size: 12.5, weight: .semibold)).frame(width: 90, alignment: .leading)
                        Text(loc("\(d.turns) tur · \(shortDuration(d.seconds)) · \(d.edits) düzenleme · \(d.waits) kez bekledi",
                                 "\(d.turns) turns · \(shortDuration(d.seconds)) · \(d.edits) edits · waited \(d.waits)×"))
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

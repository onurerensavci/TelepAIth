import AppKit
import SwiftUI

/// Robota tıklayınca açılan Sohbetler paneli: bütün sohbetler, gruplu ve kaydırılabilir
/// (Seni bekliyor · Yeni bitti · Çalışıyor · Bitti). Satıra tıklayınca o sohbet açılır.
/// Robotun penceresinden ayrı bir penceredir, sohbet sayısı sınırlı değildir. (Windows'ta ChatsPanel.cs)
final class ChatsPanel: NSObject, NSWindowDelegate {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) { close() }   // Esc kapatır
    }

    let model = ChatsPanelModel()
    private var panel: Panel?
    private var timer: Timer?
    private var outsideMonitor: Any?
    /// Dışarı tıklanınca kapandığı an: aynı tıklama robota geldiyse paneli yeniden açmasın
    private(set) var closedAt = Date.distantPast
    /// Satırları her saniye tazeler (süreler ilerler, yeni sohbetler eklenir)
    var rows: () -> [RobotModel.ChatRow] = { [] }

    var isOpen: Bool { panel?.isVisible == true }

    /// Robotun kafasının ekrandaki dikdörtgeni (Cocoa koordinatları) yanında aç
    func show(near head: NSRect) {
        model.rows = rows()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? NSSize(width: 340, height: 300)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size, near: head))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // İlk çizimde liste yüksekliği ölçülür: panel hemen içeriğe göre boylansın
        for delay in [0.05, 0.25] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() } }
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Başka bir uygulamaya tıklanınca kapanır
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.close()
            }
        }
    }

    func close() {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        timer?.invalidate()
        timer = nil
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = nil
        closedAt = Date()
    }

    private func refresh() {
        guard let panel = panel, panel.isVisible else { return }
        model.rows = rows()
        // Yükseklik içeriğe göre (en fazla 480)
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        if abs(size.height - panel.frame.height) > 1 {
            var f = panel.frame
            f.origin.y += f.height - size.height
            f.size = size
            panel.setFrame(f, display: true)
        }
    }

    private func makePanel() -> Panel {
        let p = Panel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.delegate = self
        model.onClose = { [weak self] in self?.close() }
        let host = NSHostingView(rootView: ChatsPanelView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 300)
        p.contentView = host
        return p
    }

    /// Kafa ekranın sağındaysa paneli soluna, solundaysa sağına koy; üst kenarı kafayla hizalı, ekrana sığsın
    private func origin(for size: NSSize, near head: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(head) } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 10
        var x = head.midX > vis.midX ? head.minX - gap - size.width : head.maxX + gap
        x = Swift.min(Swift.max(x, vis.minX + 8), vis.maxX - size.width - 8)
        var y = head.maxY - size.height
        y = Swift.min(Swift.max(y, vis.minY + 8), vis.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    func windowDidResignKey(_ notification: Notification) { close() }   // dışarı tıklanınca kapanır
}

final class ChatsPanelModel: ObservableObject {
    @Published var rows: [RobotModel.ChatRow] = []
    var onOpen: ((RobotModel.ChatRow) -> Void)?
    var onClose: (() -> Void)?
}

/// Panelin içeriği
struct ChatsPanelView: View {
    @ObservedObject var model: ChatsPanelModel
    /// Listenin gerçek yüksekliği: panel içeriğe göre büyür, 430'dan uzunsa kaydırılır
    @State private var listHeight: CGFloat = 0

    private struct ChatGroup: Identifiable {
        let id: String
        let title: String
        let rows: [RobotModel.ChatRow]
    }

    /// Gruplar: seni bekleyenler, yeni bitenler (bakılmamış), çalışanlar, bitenler
    private var groups: [ChatGroup] {
        let r = model.rows
        return [
            ChatGroup(id: "waiting", title: loc("Seni bekliyor", "Needs you"), rows: r.filter { $0.rank == 0 }),
            ChatGroup(id: "fresh", title: loc("Yeni bitti", "Just finished"), rows: r.filter { $0.rank == 1 }),
            ChatGroup(id: "working", title: loc("Çalışıyor", "Working"), rows: r.filter { $0.rank == 2 }),
            ChatGroup(id: "seen", title: loc("Bitti", "Done"), rows: r.filter { $0.rank == 3 }),
        ].filter { !$0.rows.isEmpty }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { context in
            content(time: context.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: 340)
        .background(VisualEffectBackground().clipShape(RoundedRectangle(cornerRadius: 14)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func content(time: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(loc("Sohbetler", "Chats")).font(.system(size: 14, weight: .bold))
                Spacer()
                Text(model.rows.isEmpty ? "" : RobotModel.chatSummary(model.rows))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            Divider().opacity(0.5)
            if model.rows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc("Şu an sohbet yok", "No chats right now")).font(.system(size: 12.5, weight: .medium))
                    Text(loc("Bir sohbet çalışınca, seni bekleyince ya da bitince burada görünür; son 2 saatte bitenler de kalır.",
                             "Chats show up here when they work, need you or finish; ones finished in the last 2 hours stay too."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { g in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(g.title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                                    Text("\(g.rows.count)").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary.opacity(0.7))
                                }
                                .padding(.horizontal, 6)
                                ForEach(g.rows, id: \.sessionID) { row in
                                    ChatsPanelRow(row: row, time: time) { model.onOpen?(row) }
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(GeometryReader { g in Color.clear.preference(key: ChatsListHeightKey.self, value: g.size.height) })
                }
                .frame(height: Swift.min(Swift.max(listHeight, 44), 430))
                .onPreferenceChange(ChatsListHeightKey.self) { listHeight = $0 }
            }
        }
    }
}

private struct ChatsListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = Swift.max(value, nextValue()) }
}

/// Bir sohbet satırı: AI şeridi, durum simgesi, ad, uygulama ve durum, süre; renk kodlu zemin
struct ChatsPanelRow: View {
    let row: RobotModel.ChatRow
    let time: TimeInterval
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        let theme = Themes.shared.theme(for: row.source)
        let ai = Color(nsColor: theme.color)
        let tone = ChatListBubble.toneColor(row.tone, ai: ai)
        let seen = row.tone == "seen"
        return Button(action: open) {
            HStack(spacing: 8) {
                Capsule().fill(ai).frame(width: 3, height: 26)
                ChatStateIcon(state: row.state, color: ai, time: time).frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 12.5, weight: row.unread ? .bold : .medium))
                        .foregroundColor(seen ? .secondary : .primary)
                        .lineLimit(1)
                    Text(theme.displayName + " · " + ChatsPanelRow.kind(row))
                        .font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(row.label)
                    .font(.system(size: 11, weight: seen ? .regular : .semibold))
                    .foregroundColor(seen ? .secondary : tone)
                    .lineLimit(1)
                    .fixedSize()
                if row.unread { Circle().fill(ChatListBubble.unreadColor).frame(width: 7, height: 7) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(background(tone: tone, seen: seen))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(row.title)
    }

    /// Renk kodu: turuncu seni bekliyor (kenarı atar), AI rengi çalışıyor (üstünden ışık geçer), yeşil yeni bitti, kırmızı hata, gri bakılmış
    private func background(tone: Color, seen: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(tone.opacity((seen ? 0.06 : 0.14) + (hover ? 0.12 : 0)))
            if row.tone == "working" {
                GeometryReader { g in
                    let phase = (time * 0.5).truncatingRemainder(dividingBy: 1)
                    LinearGradient(colors: [tone.opacity(0), tone.opacity(0.35), tone.opacity(0)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.4)
                        .offset(x: (phase * 1.4 - 0.4) * g.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if row.tone == "waiting" {
                RoundedRectangle(cornerRadius: 8).stroke(tone.opacity(0.35 + 0.35 * (0.5 + 0.5 * sin(time * 4))), lineWidth: 1.2)
            }
        }
    }

    /// Ne tür sohbet: uygulamada açık olan, uygulamada arkada, terminal (Claude Code / Codex)
    static func kind(_ row: RobotModel.ChatRow) -> String {
        if row.sessionID.hasPrefix("app-") { return loc("uygulamada açık", "open in the app") }
        if row.sessionID.hasPrefix("bg-") { return loc("uygulamada arkada", "in the app, background") }
        return loc("terminal", "terminal")
    }
}

/// Panelin buzlu cam zemini
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

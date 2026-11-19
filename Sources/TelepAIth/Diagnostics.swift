import AppKit
import SwiftUI

/// İzleyicinin bir uygulamada gördükleri (teşhis paneli için).
struct AppDiagnostics: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var windows: String
    var composer: Bool
    var stopButton: Bool
    var sendButton: Bool
    var approveButton: Bool
    var streaming: Bool
    var generating: Bool
    var phase: String
    var chat: String
    var buttons: [String]
    var roles: String
    var texts: [String]
}

/// Teşhis paneline giden canlı veriler.
final class Diagnostics: ObservableObject {
    static let shared = Diagnostics()

    @Published var apps: [AppDiagnostics] = []
    @Published var general: [(String, String)] = []

    var reportText: String {
        var lines = ["TelepAIth teşhis raporu — \(Date())"]
        for (key, value) in general { lines.append("\(key): \(value)") }
        for app in apps {
            lines.append("")
            lines.append("== \(app.name) ==")
            lines.append("Pencereler: \(app.windows)")
            lines.append("Yazı kutusu: \(app.composer ? "var" : "yok") · Durdur: \(app.stopButton ? "var" : "yok") · Gönder: \(app.sendButton ? "var" : "yok") · İzin ver: \(app.approveButton ? "var" : "yok")")
            lines.append("Çalışıyor: \(app.generating ? "evet" : "hayır") · Metin akıyor: \(app.streaming ? "evet" : "hayır") · Aşama: \(app.phase)")
            lines.append("Sohbet: \(app.chat)")
            lines.append("Roller: \(app.roles)")
            lines.append("Düğmeler: " + app.buttons.joined(separator: " | "))
            lines.append("Metinler: " + app.texts.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }
}

struct DiagnosticsView: View {
    @ObservedObject var data = Diagnostics.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loc("Robot ne görüyor?", "What does the robot see?"))
                    .font(.headline)
                Spacer()
                Button(loc("Panoya kopyala", "Copy to clipboard")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(data.reportText, forType: .string)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(data.general.enumerated()), id: \.offset) { _, item in
                            row(item.0, item.1)
                        }
                    }
                    if data.apps.isEmpty {
                        Text(loc("İzlenen Claude/ChatGPT uygulaması yok (açık değil ya da izin verilmemiş).",
                                 "No Claude/ChatGPT app is being watched (not open, or no permission)."))
                            .foregroundColor(.secondary)
                    }
                    ForEach(data.apps) { app in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 10) {
                                badge(loc("Yazı kutusu", "Input box"), app.composer)
                                badge(loc("Durdur", "Stop"), app.stopButton)
                                badge(loc("Gönder", "Send"), app.sendButton)
                                badge(loc("İzin ver", "Allow"), app.approveButton)
                                badge(loc("Metin akıyor", "Streaming"), app.streaming)
                            }
                            row(loc("Durum", "State"), (app.generating ? loc("çalışıyor", "working") : loc("boşta", "idle")) + " · " + app.phase)
                            row(loc("Pencereler", "Windows"), app.windows)
                            row(loc("Sohbet", "Chat"), app.chat)
                            row(loc("Düğmeler", "Buttons"), app.buttons.isEmpty ? "—" : app.buttons.joined(separator: " | "))
                            row(loc("Metinler", "Texts"), app.texts.isEmpty ? "—" : app.texts.joined(separator: " | "))
                            row(loc("Roller", "Roles"), app.roles)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 420)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(key + ":").foregroundColor(.secondary).frame(width: 110, alignment: .leading)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
    }

    private func badge(_ title: String, _ on: Bool) -> some View {
        HStack(spacing: 3) {
            Circle().fill(on ? Color.green : Color.gray.opacity(0.5)).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11))
        }
    }
}

final class DiagnosticsWindow {
    static let shared = DiagnosticsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = AppInfo.name + " — " + loc("Teşhis", "Diagnostics")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: DiagnosticsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

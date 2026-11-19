import Foundation
import Network

/// Sadece bu Mac'ten (loopback) gelen istekleri dinleyen küçük HTTP sunucusu.
/// POST /event?source=claude   → hook olayları ve genel format
/// POST /claudebar             → ClaudeBar webhook'u
/// GET  /                      → "çalışıyor" cevabı (sağlık kontrolü)
final class EventServer {
    var onRequest: ((String, [String: String], Data) -> Void)?
    var onReady: ((UInt16) -> Void)?
    var onFailure: ((String) -> Void)?
    private(set) var port: UInt16 = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "telepaith.server")
    private let maxBytes = 8 * 1024 * 1024

    func start(preferredPort: UInt16) {
        queue.async { self.tryStart(port: preferredPort, attemptsLeft: 10) }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func tryStart(port: UInt16, attemptsLeft: Int) {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let newListener = try? NWListener(using: params, on: nwPort) else {
            retry(port: port, attemptsLeft: attemptsLeft, reason: loc("Port \(port) açılamadı", "Couldn't open port \(port)"))
            return
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.port = port
                DispatchQueue.main.async { self.onReady?(port) }
            case .failed(let error), .waiting(let error):
                newListener?.cancel()
                self.retry(port: port, attemptsLeft: attemptsLeft, reason: error.localizedDescription)
            default:
                break
            }
        }
        listener = newListener
        newListener.start(queue: queue)
    }

    private func retry(port: UInt16, attemptsLeft: Int, reason: String) {
        if attemptsLeft > 0 && port < UInt16.max {
            tryStart(port: port + 1, attemptsLeft: attemptsLeft - 1)
        } else {
            DispatchQueue.main.async { self.onFailure?(reason) }
        }
    }

    private func accept(_ connection: NWConnection) {
        guard EventServer.isLocal(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data(), sentContinue: false)
    }

    private static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            return address.isLoopback
        case .ipv6(let address):
            return address.isLoopback || "\(address)".hasPrefix("::ffff:127.")
        case .name(let name, _):
            return name == "localhost"
        @unknown default:
            return false
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data, sentContinue: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            var buf = buffer
            if let data = data { buf.append(data) }
            if buf.count > self.maxBytes {
                self.respond(connection, status: "413 Payload Too Large")
                return
            }

            switch HTTPRequest.parse(buf) {
            case .invalid:
                self.respond(connection, status: "400 Bad Request")
            case .complete(let request):
                // Tarayıcıdaki web sayfaları localhost'a istek atamasın
                if request.headers["origin"] != nil {
                    self.respond(connection, status: "403 Forbidden")
                    return
                }
                guard request.method == "POST" else {
                    let ok = request.method == "GET"
                    self.respond(connection, status: ok ? "200 OK" : "405 Method Not Allowed", body: "\(AppInfo.name) is running")
                    return
                }
                self.respond(connection, status: "200 OK")
                self.onRequest?(request.path, request.query, request.body)
            case .incomplete(let expectContinue):
                if error != nil || isComplete {
                    connection.cancel()
                    return
                }
                var sent = sentContinue
                if expectContinue && !sent {
                    sent = true
                    connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in })
                }
                self.receive(connection, buffer: buf, sentContinue: sent)
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String = "ok") {
        let bodyData = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(bodyData)
        connection.send(content: out, completion: .contentProcessed { _ in connection.cancel() })
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    enum ParseResult {
        case incomplete(expectContinue: Bool)
        case complete(HTTPRequest)
        case invalid
    }

    static func parse(_ data: Data) -> ParseResult {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 64 * 1024 ? .invalid : .incomplete(expectContinue: false)
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        if data.endIndex - bodyStart < length {
            return .incomplete(expectContinue: headers["expect"]?.lowercased() == "100-continue")
        }
        let body = Data(data[bodyStart..<(bodyStart + length)])

        let target = String(requestLine[1])
        let components = URLComponents(string: "http://localhost" + target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }

        return .complete(HTTPRequest(method: String(requestLine[0]).uppercased(),
                                     path: components?.path ?? target,
                                     query: query,
                                     headers: headers,
                                     body: body))
    }
}

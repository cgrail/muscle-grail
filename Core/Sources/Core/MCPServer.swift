#if os(macOS)
import Foundation
import Network
import SwiftData

/// Serves `MCP` over the Streamable HTTP transport on this Mac only: POST /mcp with one JSON-RPC message.
/// Requests from web pages are refused, so a site can't reach it through the browser.
@MainActor public final class MCPServer {
    private let listener: NWListener
    private let mcp: MCP

    /// Port nil picks a free one, for tests. `isShared` says whether a plan is shared with the training partner.
    public init(context: ModelContext, port: UInt16?, isShared: @escaping (UUID) -> Bool = { _ in false }) throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any)
        mcp = MCP(context: context, isShared: isShared)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.serve(connection) }
        }
        listener.start(queue: .main)
    }

    /// The port once it listens, or nil if it couldn't within 5 seconds (another app may have the port).
    public func ready() async -> UInt16? {
        for _ in 0..<500 {
            switch listener.state {
            case .ready: return listener.port?.rawValue
            case .failed, .cancelled: return nil
            default: try? await Task.sleep(for: .milliseconds(10))
            }
        }
        return nil
    }

    public func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, after: Data())
    }

    private func receive(on connection: NWConnection, after buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                let buffer = buffer + (data ?? Data())
                if let request = HTTPRequest(buffer) {
                    self?.respond(to: request, on: connection)
                } else if done || error != nil || buffer.count > 1 << 20 {
                    connection.cancel()
                } else {
                    self?.receive(on: connection, after: buffer)
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let (status, body): (String, Data?) = switch (request.method, request.path) {
        case _ where !request.fromThisMac: ("403 Forbidden", nil)
        case ("POST", "/mcp"): mcp.handle(request.body).map { ("200 OK", $0) } ?? ("202 Accepted", nil)
        case (_, "/mcp"): ("405 Method Not Allowed", nil)
        default: ("404 Not Found", nil)
        }
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body?.count ?? 0)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + (body ?? Data()), completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// One HTTP/1.1 request, once all of it has arrived.
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count >= 2 else { return nil }
        headers = Dictionary(lines.dropFirst().compactMap { line in
            line.firstIndex(of: ":").map { (line[..<$0].lowercased(), line[line.index(after: $0)...].trimmingCharacters(in: .whitespaces)) }
        }, uniquingKeysWith: { first, _ in first })
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard data.count - end.upperBound >= length else { return nil }
        (method, path, body) = (String(start[0]), String(start[1]), data[end.upperBound...].prefix(length))
    }

    /// Browsers send an Origin; only pages served from this Mac may call.
    var fromThisMac: Bool {
        guard let origin = headers["origin"] else { return true }
        return ["localhost", "127.0.0.1"].contains(URL(string: origin)?.host() ?? "")
    }
}
#endif

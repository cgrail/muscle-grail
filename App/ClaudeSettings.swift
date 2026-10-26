#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// Runs the MCP server while it is switched on in Settings: one for the whole app, not one per window.
@MainActor @Observable final class ClaudeConnection {
    static let port: UInt16 = 7428
    static let url = "http://127.0.0.1:\(port)/mcp"
    private let context: ModelContext
    private var server: MCPServer?
    private(set) var failed = false

    init(context: ModelContext) {
        self.context = context
        set(on: UserDefaults.standard.bool(forKey: "mcpServer"))
    }

    func set(on: Bool) {
        server?.stop()
        server = on ? try? MCPServer(context: context, port: Self.port) { PartnerStatus.shared.plans.contains($0) } : nil
        failed = on && server == nil
        guard let server else { return }
        Task { failed = await server.ready() == nil }
    }
}

/// Settings → Claude: lets Claude create and extend plans through MCP, and shows how to connect it.
struct ClaudeSettings: View {
    @Environment(ClaudeConnection.self) private var connection
    @AppStorage("mcpServer") private var on = false

    var body: some View {
        Form {
            Toggle("Let Claude create and edit plans", isOn: $on)
            if connection.failed {
                Text("Another app uses port \(Int(ClaudeConnection.port)). Quit it and switch this on again.").foregroundStyle(.red)
            }
            Section("Connect Claude") {
                LabeledContent("Claude Code") { command("claude mcp add --transport http muscle-grail \(ClaudeConnection.url)") }
                LabeledContent("Claude Desktop") {
                    command(#"{"mcpServers": {"muscle-grail": {"command": "npx", "args": ["-y", "mcp-remote", "\#(ClaudeConnection.url)"]}}}"#)
                }
                Text("Only apps on this Mac can connect, and only while Muscle Grail is open.").foregroundStyle(.secondary)
            }
            .disabled(!on)
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .onChange(of: on) { connection.set(on: on) }
    }

    private func command(_ text: String) -> some View {
        Text(verbatim: text).font(.callout.monospaced()).textSelection(.enabled)
    }
}
#endif

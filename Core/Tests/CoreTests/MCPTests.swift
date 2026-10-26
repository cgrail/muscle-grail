import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct MCPTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    /// Sends one JSON-RPC request and returns the whole reply. `shared` plans are shared with the training partner.
    func send(_ method: String, _ params: [String: Any] = [:], shared: Set<UUID> = []) throws -> [String: Any] {
        let request = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        let reply = try #require(MCP(context: context) { shared.contains($0) }.handle(request))
        return try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any])
    }

    func tool(_ name: String, _ arguments: [String: Any] = [:], shared: Set<UUID> = []) throws -> (text: String, isError: Bool) {
        let result = try #require(send("tools/call", ["name": name, "arguments": arguments], shared: shared)["result"] as? [String: Any])
        return ((result["content"] as? [[String: Any]])?.first?["text"] as? String ?? "", result["isError"] as? Bool ?? false)
    }

    func errorCode(_ reply: [String: Any]) -> Int? { (reply["error"] as? [String: Any])?["code"] as? Int }

    // MARK: Protocol

    @Test func initializeAnnouncesToolsInTheClientsVersion() throws {
        let result = try #require(send("initialize", ["protocolVersion": "2025-03-26"])["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
    }

    @Test func notificationsGetNoReply() throws {
        let note = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        #expect(MCP(context: context).handle(note) == nil)
    }

    @Test func pingAnswers() throws {
        #expect(try send("ping")["result"] != nil)
    }

    @Test func toolsAreListed() throws {
        let tools = try #require(send("tools/list")["result"] as? [String: Any])["tools"] as? [[String: Any]]
        #expect(tools?.compactMap { $0["name"] as? String } == ["list_plans", "search_exercises", "create_plan", "add_exercises"])
    }

    @Test func unknownMethodsAndGarbageAreErrors() throws {
        #expect(errorCode(try send("resources/list")) == -32601)
        let garbage = try #require(MCP(context: context).handle(Data("not json".utf8)))
        #expect(errorCode(try #require(JSONSerialization.jsonObject(with: garbage) as? [String: Any])) == -32700)
    }

    // MARK: Tools

    @Test func createPlanBuildsThePlanWithTargets() throws {
        _ = try tool("create_plan", ["name": "Legs", "exercises": [["name": "Barbell Back Squat", "sets": 5, "reps": 5, "weight_kg": 100], ["name": "Zercher Carry"]]])
        let plan = try #require(context.fetch(FetchDescriptor<Plan>()).first)
        let squat = plan.sortedItems[0]
        #expect(plan.name == "Legs" && plan.sortedItems.count == 2)
        #expect((squat.exerciseID, squat.targetSets, squat.targetReps, squat.targetWeightKg) == ("squat", 5, 5, 100))
    }

    @Test func addExercisesExtendsAPlanFoundByName() throws {
        let plan = makePlan(context, "squat")
        context.rename(plan, to: "Legs")
        _ = try tool("add_exercises", ["plan": "legs", "exercises": [["name": "Barbell Deadlift"]]])
        #expect(plan.sortedItems.map(\.exerciseID) == ["squat", "deadlift"])
    }

    @Test func exercisesAddedToASharedPlanAreYoursUnlessSharedToo() throws {
        let plan = makePlan(context)
        context.rename(plan, to: "Legs")
        _ = try tool("add_exercises", ["plan": "Legs", "exercises": [["name": "Barbell Deadlift"]]], shared: [plan.id])
        _ = try tool("add_exercises", ["plan": "Legs", "exercises": [["name": "Barbell Back Squat"]], "shared": true], shared: [plan.id])
        #expect(plan.sortedItems.map(\.ownedBy) == [.me, .both])
    }

    @Test func addingToAPlanThatDoesNotExistIsAnError() throws {
        #expect(try tool("add_exercises", ["plan": "Legs", "exercises": [["name": "Barbell Back Squat"]]]).isError)
    }

    @Test func listPlansShowsExercisesAndTargets() throws {
        #expect(try tool("list_plans").text == "No plans yet.")
        context.rename(makePlan(context, "squat"), to: "Legs")
        #expect(try tool("list_plans").text == "Legs\n- Barbell Back Squat: 3 × 10 at 0 kg")
    }

    @Test func searchFindsCatalogNames() throws {
        #expect(try tool("search_exercises", ["query": "barbell squat"]).text.contains("Barbell Back Squat"))
    }

    @Test func editingWaitsForAnUpdateAfterNewerActions() throws {
        let newer = Action()
        newer.version = Change.version + 1
        context.insert(newer)
        #expect(try tool("create_plan", ["name": "Legs", "exercises": []]).isError)
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 0)
    }

    @Test func unknownToolIsAnError() throws {
        #expect(try tool("delete_everything").isError)
    }

    // MARK: Server

    func post(_ body: [String: Any], to path: String = "/mcp", port: UInt16, origin: String? = nil, method: String = "POST") async throws -> Int {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.httpBody = method == "POST" ? try JSONSerialization.data(withJSONObject: body) : nil
        request.setValue(origin, forHTTPHeaderField: "Origin")
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    @Test func serverAnswersOnThisMac() async throws {
        let server = try MCPServer(context: context, port: nil)
        defer { server.stop() }
        let port = try #require(await server.ready())
        #expect(try await post(["jsonrpc": "2.0", "id": 1, "method": "ping"], port: port) == 200)
        #expect(try await post(["jsonrpc": "2.0", "method": "notifications/initialized"], port: port) == 202)
    }

    @Test func serverRefusesWebPagesAndOtherRequests() async throws {
        let server = try MCPServer(context: context, port: nil)
        defer { server.stop() }
        let port = try #require(await server.ready())
        #expect(try await post(["jsonrpc": "2.0", "id": 1, "method": "ping"], port: port, origin: "https://example.com") == 403)
        #expect(try await post([:], port: port, method: "GET") == 405)
        #expect(try await post([:], to: "/other", port: port) == 404)
    }

    @Test func serverOnATakenPortReportsIt() async throws {
        let first = try MCPServer(context: context, port: nil)
        defer { first.stop() }
        let port = try #require(await first.ready())
        let second = try MCPServer(context: context, port: port)
        defer { second.stop() }
        #expect(await second.ready() == nil)
    }
}

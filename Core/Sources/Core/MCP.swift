import Foundation
import SwiftData

/// The Model Context Protocol for Claude: tools to list, find and create plans. Every edit goes through the same
/// Core functions as the app's own, so it is recorded as actions and waits for an update like the app does.
@MainActor public struct MCP {
    static let versions = ["2025-06-18", "2025-03-26"]
    let context: ModelContext
    /// Whether a plan is shared with the training partner.
    let isShared: (UUID) -> Bool

    public init(context: ModelContext, isShared: @escaping (UUID) -> Bool = { _ in false }) {
        self.context = context
        self.isShared = isShared
    }

    /// Answers one JSON-RPC message, or returns nil for a notification, which gets no answer.
    public func handle(_ body: Data) -> Data? {
        guard let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = message["method"] as? String else { return reply(id: NSNull(), error: (-32700, "Parse error")) }
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return reply(id: id, result: [
                "protocolVersion": Self.versions.contains(asked) ? asked : Self.versions[0],
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "muscle-grail", "version": "1.0"],
            ])
        case "ping":
            return reply(id: id, result: [:])
        case "tools/list":
            return reply(id: id, result: ["tools": Self.tools])
        case "tools/call":
            return reply(id: id, result: call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:]))
        default:
            return reply(id: id, error: (-32601, "Method not found: \(method)"))
        }
    }

    private func call(_ tool: String, _ arguments: [String: Any]) -> [String: Any] {
        do {
            return ["content": [["type": "text", "text": try run(tool, arguments)]]]
        } catch {
            return ["content": [["type": "text", "text": "\(error)"]], "isError": true]
        }
    }

    private func run(_ tool: String, _ arguments: [String: Any]) throws -> String {
        let plans = try context.fetch(FetchDescriptor<Plan>(sortBy: [SortDescriptor(\.order)]))
        switch tool {
        case "list_plans":
            return plans.isEmpty ? "No plans yet." : plans.map(describe).joined(separator: "\n\n")
        case "search_exercises":
            let custom = try context.fetch(FetchDescriptor<CatalogEntry>()).filter(\.isOwnExercise).map(\.name)
            return catalogNames(matching: arguments["query"] as? String ?? "", custom: custom, limit: 20).joined(separator: "\n")
        case "create_plan":
            try requireEditing()
            let plan = context.addPlan()
            if let name = arguments["name"] as? String { context.rename(plan, to: name) }
            context.add(exercises(arguments), to: plan)
            try context.save()
            return describe(plan)
        case "add_exercises":
            try requireEditing()
            let name = arguments["plan"] as? String ?? ""
            guard let plan = plans.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw Failure("No plan called \(name). list_plans shows them.")
            }
            // In a shared plan, the user's own unless the call or the user's settings say for both, like the app's question.
            let forBoth = arguments["shared"] as? Bool ?? NSUbiquitousKeyValueStore.default.bool(forKey: partnerAlwaysBothKey)
            context.add(exercises(arguments), to: plan, own: isShared(plan.id) && !forBoth ? .mine : nil)
            try context.save()
            return describe(plan)
        default:
            throw Failure("Unknown tool \(tool).")
        }
    }

    private func requireEditing() throws {
        guard try context.fetchCount(Action.newer) == 0 else {
            throw Failure("A newer version of Muscle Grail changed the plans. Update the app on this Mac to edit them.")
        }
    }

    private func exercises(_ arguments: [String: Any]) -> [PlannedExercise] {
        let defaults = targetDefaults()
        return (arguments["exercises"] as? [[String: Any]] ?? []).compactMap { exercise in
            guard let name = exercise["name"] as? String else { return nil }
            return PlannedExercise(
                name: name, sets: exercise["sets"] as? Int ?? defaults.sets, reps: exercise["reps"] as? Int ?? defaults.reps,
                weightKg: (exercise["weight_kg"] as? NSNumber)?.doubleValue ?? 0
            )
        }
    }

    private func describe(_ plan: Plan) -> String {
        ([plan.title] + plan.sortedItems.map { item in
            return "- \(context.exerciseName(item.exerciseID, localized: false)): \(item.targetSets) × \(item.targetReps) at \(item.targetWeightKg.formatted()) kg"
        }).joined(separator: "\n")
    }

    private func reply(id: Any, result: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func reply(id: Any, error: (code: Int, message: String)) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "error": ["code": error.code, "message": error.message]])
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static var tools: [[String: Any]] {
        let defaults = targetDefaults()
        let exercises: [String: Any] = [
            "type": "array",
            "description": "Exercises in order. Use the catalog's exact names from search_exercises; other names become the user's own exercises.",
            "items": [
                "type": "object", "required": ["name"],
                "properties": [
                    "name": ["type": "string"], "sets": ["type": "integer", "description": "Default \(defaults.sets)"],
                    "reps": ["type": "integer", "description": "Default \(defaults.reps)"], "weight_kg": ["type": "number", "description": "Default 0"],
                ],
            ],
        ]
        func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
            ["name": name, "description": description, "inputSchema": ["type": "object", "properties": properties, "required": required]]
        }
        return [
            tool("list_plans", "Lists the workout plans with their exercises, sets, reps and weights."),
            tool("search_exercises", "Searches the exercise catalog by name, muscle or equipment, in English. Returns exact exercise names.",
                 ["query": ["type": "string"]], required: ["query"]),
            tool("create_plan", "Creates a workout plan.", ["name": ["type": "string"], "exercises": exercises], required: ["name", "exercises"]),
            tool("add_exercises", "Adds exercises to the end of an existing plan.",
                 ["plan": ["type": "string", "description": "The plan's name"], "exercises": exercises,
                  "shared": ["type": "boolean", "description": "For a plan shared with the user's training partner: true adds the exercises for both, false for the user only. Without it they're the user's own, unless the user's settings say always both."]],
                 required: ["plan", "exercises"]),
        ]
    }
}

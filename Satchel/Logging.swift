import Foundation
import os
import SatchelCore

enum SatchelLog {
    private static let tools = Logger(subsystem: "com.kevinzheng.satchel", category: "tools")
    private static let navigation = Logger(subsystem: "com.kevinzheng.satchel", category: "navigation")

    static func toolRun(id: String, inputs: Int, outcome: String, seconds: String) {
        tools.info("tool=\(id, privacy: .public) inputs=\(inputs, privacy: .public) outcome=\(outcome, privacy: .public) duration=\(seconds, privacy: .public)")
    }

    static func tab(_ name: String) {
        navigation.info("tab=\(name, privacy: .public)")
    }

    static func opened(_ id: String) {
        navigation.info("opened=\(id, privacy: .public)")
    }

    static func search(length: Int, results: Int) {
        navigation.info("search_len=\(length, privacy: .public) results=\(results, privacy: .public)")
    }
}

enum RunLog {
    static func measure<T>(tool: ToolID, inputs: Int, _ work: () async throws -> T) async throws -> T {
        let start = Date()
        do {
            let value = try await work()
            SatchelLog.toolRun(id: tool.rawValue, inputs: inputs, outcome: "ok", seconds: stamp(start))
            return value
        } catch {
            SatchelLog.toolRun(id: tool.rawValue, inputs: inputs, outcome: "failed", seconds: stamp(start))
            throw error
        }
    }

    static func stamp(_ start: Date) -> String {
        String(format: "%.2fs", Date().timeIntervalSince(start))
    }
}

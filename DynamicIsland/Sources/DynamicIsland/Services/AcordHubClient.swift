import Foundation

/// A value passed as a tool argument.
enum HubArgument: Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)

    var json: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .bool(let value): value
        }
    }
}

struct HubError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Talks to the Acord Hub MCP server over Streamable HTTP (JSON-RPC 2.0).
///
/// The island uses the same tools as Claude does (`list_tasks`, `list_calendar_events`, …), so the
/// Hub needs no extra API. Responses may come back as plain JSON or as a server-sent event stream.
actor AcordHubClient {
    struct Configuration: Equatable, Sendable {
        var endpoint: URL
        var token: String
    }

    private struct SessionExpired: Error {}

    private var configuration: Configuration?
    private var sessionID: String?
    private var protocolVersion = "2025-03-26"
    private var isInitialized = false
    private var nextID = 1
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func configure(_ configuration: Configuration?) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        reset()
    }

    /// Runs the MCP handshake if it hasn't happened yet. Call before firing requests in parallel.
    func connect() async throws {
        guard let configuration else { throw HubError("Acord Hub is not set up") }
        if !isInitialized { try await initialize(configuration) }
    }

    /// Calls a tool and returns its JSON payload (the structured content, or the text content).
    func call(_ tool: String, _ arguments: [String: HubArgument] = [:]) async throws -> Data {
        guard let configuration else { throw HubError("Acord Hub is not set up") }
        if !isInitialized { try await initialize(configuration) }
        do {
            return try await callTool(tool, arguments, configuration)
        } catch is SessionExpired {
            reset()
            try await initialize(configuration)
            return try await callTool(tool, arguments, configuration)
        }
    }

    // MARK: Protocol

    private func reset() {
        sessionID = nil
        isInitialized = false
    }

    private func initialize(_ configuration: Configuration) async throws {
        let params: [String: Any] = [
            "protocolVersion": protocolVersion,
            "capabilities": [String: Any](),
            "clientInfo": ["name": "Dynamic Island", "version": "1.1"],
        ]
        let result = try await request("initialize", params: params, configuration)
        if let version = result["protocolVersion"] as? String { protocolVersion = version }
        try await notify("notifications/initialized", configuration)
        isInitialized = true
    }

    private func callTool(_ tool: String, _ arguments: [String: HubArgument], _ configuration: Configuration) async throws -> Data {
        let result = try await request("tools/call", params: [
            "name": tool,
            "arguments": arguments.mapValues(\.json),
        ], configuration)

        let text = (result["content"] as? [[String: Any]])?
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n") ?? ""

        if result["isError"] as? Bool == true {
            throw HubError(text.isEmpty ? "\(tool) failed" : text)
        }
        if let structured = result["structuredContent"], JSONSerialization.isValidJSONObject(structured) {
            return try JSONSerialization.data(withJSONObject: structured)
        }
        return Data(text.utf8)
    }

    private func request(_ method: String, params: [String: Any], _ configuration: Configuration) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let (data, response) = try await send(body, configuration)

        let message = Self.message(in: data, contentType: response.value(forHTTPHeaderField: "Content-Type"), id: id)
        guard let message else { throw HubError("The Hub sent an unreadable response to \(method)") }
        if let error = message["error"] as? [String: Any] {
            throw HubError(error["message"] as? String ?? "The Hub returned an error")
        }
        return message["result"] as? [String: Any] ?? [:]
    }

    private func notify(_ method: String, _ configuration: Configuration) async throws {
        _ = try await send(["jsonrpc": "2.0", "method": method], configuration)
    }

    private func send(_ body: [String: Any], _ configuration: Configuration) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let token = configuration.token.trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue(token.lowercased().hasPrefix("bearer ") ? token : "Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if isInitialized { request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw HubError(error.code == .notConnectedToInternet ? "You’re offline" : "Can’t reach the Hub (\(error.localizedDescription))")
        }
        guard let http = response as? HTTPURLResponse else { throw HubError("The Hub sent no HTTP response") }
        if let newSession = http.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = newSession }

        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case 401, 403:
            throw HubError("The Hub rejected the token (HTTP \(http.statusCode))")
        case 404 where sessionID != nil && isInitialized:
            throw SessionExpired()
        case 404:
            throw HubError("No MCP server at this address (HTTP 404)")
        default:
            throw HubError("The Hub answered HTTP \(http.statusCode)")
        }
    }

    /// Finds the JSON-RPC message with `id` in a JSON body or a server-sent event stream.
    private static func message(in data: Data, contentType: String?, id: Int) -> [String: Any]? {
        func matches(_ object: Any) -> [String: Any]? {
            if let message = object as? [String: Any] {
                if let messageID = message["id"] as? Int, messageID == id { return message }
                if let messageID = message["id"] as? String, messageID == String(id) { return message }
                return nil
            }
            if let batch = object as? [Any] { return batch.lazy.compactMap(matches).first }
            return nil
        }

        if contentType?.contains("text/event-stream") == true || data.starts(with: Data("event:".utf8)) || data.starts(with: Data("data:".utf8)) {
            let text = String(decoding: data, as: UTF8.self)
            var buffer = ""
            var found: [String: Any]?
            func flush() {
                if !buffer.isEmpty, let object = try? JSONSerialization.jsonObject(with: Data(buffer.utf8)), let message = matches(object) {
                    found = message
                }
                buffer = ""
            }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = line.hasSuffix("\r") ? line.dropLast() : line
                if line.isEmpty { flush() }
                else if line.hasPrefix("data:") {
                    let payload = line.dropFirst(5).drop { $0 == " " }
                    if !buffer.isEmpty { buffer += "\n" }
                    buffer += String(payload)
                }
            }
            flush()
            return found
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return matches(object)
    }
}

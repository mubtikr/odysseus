//
//  OpenCodeGoClient.swift
//  OpenCode Go (opencode.ai Inference) transport
//
//  Talks the OpenAI Chat Completions shape against the Go plan gateway:
//    POST https://opencode.ai/inference/go/openai/v1/chat/completions
//
//  Gateway contract (verified 2026-10 against the live endpoint + docs):
//   - Authorization: Bearer <Console API key>  (personal key: oc_sk_...)
//   - x-opencode-session: stable ID per conversation, sent on EVERY request.
//     Requests without it are rejected with MissingSessionID before auth.
//   - A real client User-Agent (not a generic HTTP-library name).
//   - Free-tier models are 403 for external clients; Go plan models only.
//   - Usage reports arrive in the final usage chunk
//     (`stream_options.include_usage`) with `usage.opencode.allowance`.
//

import Foundation

class OpenCodeGoClient {
    static let userAgent = "odysseus/1.0"
    static let baseURLString = "https://opencode.ai/inference/go/openai/v1/chat/completions"

    private var apiKey: String?
    private let apiURL: URL
    var model: String
    var maxOutputTokens: Int
    private let session: URLSession

    /// Sticky conversation session id; the voice pipeline rotates this on
    /// each new push-to-talk conversation so routes + prompt caches stay
    /// per-conversation (gateway requirement, not per-request).
    private(set) var sessionID: String

    init(
        apiKey: String?,
        model: String = OdysseusModelCatalog.opencodeGoDeepSeekFlashModelID,
        maxOutputTokens: Int = 64_000
    ) {
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiURL = URL(string: Self.baseURLString)!
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.sessionID = OpenCodeGoClient.makeSessionID()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }

    func setAPIKey(_ apiKey: String?) {
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func rotateSession() {
        sessionID = OpenCodeGoClient.makeSessionID()
    }

    /// Pre-warm the TLS handshake to the inference gateway so the first
    /// streaming turn doesn't pay the cold-connect tax.
    func warmUpConnection() {
        var warmupRequest = URLRequest(url: apiURL)
        warmupRequest.httpMethod = "HEAD"
        warmupRequest.timeoutInterval = 10
        session.dataTask(with: warmupRequest) { _, _, _ in }.resume()
    }

    static func makeSessionID() -> String {
        "ses_" + UUID().uuidString.lowercased()
    }

    static func makeRequestHeaders(apiKey: String?, sessionID: String) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            "User-Agent": userAgent,
            "x-opencode-session": sessionID
        ]
        if let resolvedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !resolvedKey.isEmpty {
            headers["Authorization"] = "Bearer \(resolvedKey)"
        }
        return headers
    }

    /// Missing-key surface mirroring the other clients' domain.
    static func missingKeyError() -> NSError {
        NSError(
            domain: "OpenCodeGoClient",
            code: -1000,
            userInfo: [NSLocalizedDescriptionKey: "OpenCode Go is not configured. Add your Console API key to ~/.config/odysseus/secrets.env as OPENCODE_API_KEY."]
        )
    }

    /// DeepSeek on Go is a text endpoint; image turns are routed elsewhere.
    static func textOnlyModelError() -> NSError {
        NSError(
            domain: "OpenCodeGoClient",
            code: -1001,
            userInfo: [NSLocalizedDescriptionKey: "DeepSeek V4.1 Flash (OpenCode Go) cannot see images. Attach visual context requires the Codex analysis model."]
        )
    }

    private func requireKey() throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw Self.missingKeyError()
        }
        return apiKey
    }

    func makeMessages(
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        images: [(data: Data, label: String)] = [],
        imageMediaTypeResolver: @escaping (Data) -> String = { _ in "image/png" }
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = [[
            "role": "system",
            "content": systemPrompt
        ]]
        for turn in conversationHistory {
            messages.append(["role": "user", "content": turn.userPlaceholder])
            messages.append(["role": "assistant", "content": turn.assistantResponse])
        }
        if images.isEmpty {
            messages.append(["role": "user", "content": userPrompt])
        } else {
            // DeepSeek V4.1 Flash on the Go gateway accepts OpenAI-style
            // image_url parts on chat completions (verified live 2026-10).
            // It reasons the image through `reasoning_content`; the spoken
            // answer still arrives in `content`.
            var contentBlocks: [[String: Any]] = []
            for image in images {
                contentBlocks.append(["type": "text", "text": image.label])
                let mediaType = imageMediaTypeResolver(image.data)
                contentBlocks.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(mediaType);base64,\(image.data.base64EncodedString())"]
                ])
            }
            contentBlocks.append(["type": "text", "text": userPrompt])
            messages.append(["role": "user", "content": contentBlocks])
        }
        return messages
    }

    func makeBody(
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        stream: Bool,
        images: [(data: Data, label: String)] = [],
        modelOverride: String? = nil
    ) -> [String: Any] {
        [
            "model": modelOverride ?? model,
            "messages": makeMessages(
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                userPrompt: userPrompt,
                images: images
            ),
            "stream": stream,
            "stream_options": ["include_usage": true],
            "max_tokens": maxOutputTokens
        ]
    }

    /// One-shot completion (element pointing etc.).
    func complete(
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String
    ) async throws -> String {
        let key = try requireKey()

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        for (name, value) in Self.makeRequestHeaders(apiKey: key, sessionID: sessionID) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        // Non-streaming: omit the usage ideal — the gateway still reports
        // usage in the response body; include_usage is stream-only.
        var body = makeBody(
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt,
            stream: false
        )
        body.removeValue(forKey: "stream_options")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw Self.networkError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
                body: String(data: data, encoding: .utf8) ?? "Unknown error"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "OpenCodeGoClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid OpenCode Go response format."]
            )
        }
        Self.logUsageIfPresent(json, event: "opencode.complete.response")

        guard let text = Self.firstChoiceText(from: json),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "OpenCodeGoClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "OpenCode Go returned an empty response."]
            )
        }
        return text
    }

    /// Streaming completion for the voice pipeline. Emits the ACCUMULATED
    /// text on every delta (matches the other transport clients).
    func analyzeVoiceResponseStreaming(
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String,
        images: [(data: Data, label: String)] = [],
        modelOverride: String? = nil,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let key = try requireKey()
        let startTime = Date()

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        for (name, value) in Self.makeRequestHeaders(apiKey: key, sessionID: sessionID) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let body = makeBody(
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt,
            stream: true,
            images: images,
            modelOverride: modelOverride
        )
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData

        OdysseusMessageLogStore.shared.append(
            lane: "voice",
            direction: "outgoing",
            event: "opencode.streaming.request",
            fields: [
                "model": model,
                "session": sessionID,
                "payloadBytes": bodyData.count,
                "transport": "sse",
                "url": apiURL.absoluteString
            ]
        )

        let (byteStream, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "OpenCodeGoClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response from OpenCode Go."]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyLines: [String] = []
            for try await line in byteStream.lines {
                errorBodyLines.append(line)
            }
            let errorBody = errorBodyLines.joined(separator: "\n")
            throw Self.networkError(
                statusCode: httpResponse.statusCode,
                body: errorBody
            )
        }

        var accumulatedText = ""
        var deltaCount = 0
        var firstDeltaAt: Date?

        for try await line in byteStream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]" else { break }

            guard let jsonData = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Error events arrive as {"type":"error","error":{...}} or as
            // bare chat-completions error JSON.
            if let errorPayload = Self.errorPayload(from: event) {
                throw NSError(
                    domain: "OpenCodeGoClient",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: errorPayload]
                )
            }

            guard let choices = event["choices"] as? [[String: Any]] else { continue }
            for choice in choices {
                guard let delta = choice["delta"] as? [String: Any],
                      let chunk = delta["content"] as? String,
                      !chunk.isEmpty else {
                    continue
                }
                deltaCount += 1
                if firstDeltaAt == nil {
                    firstDeltaAt = Date()
                    OdysseusMessageLogStore.shared.append(
                        lane: "voice",
                        direction: "incoming",
                        event: "opencode.streaming.first_text_delta",
                        fields: [
                            "model": model,
                            "transport": "sse",
                            "firstTokenLatencyMs": Self.elapsedMilliseconds(from: startTime, to: firstDeltaAt!),
                            "chunkLength": chunk.count
                        ]
                    )
                }
                accumulatedText += chunk
                let currentAccumulated = accumulatedText
                await MainActor.run {
                    onTextChunk(currentAccumulated)
                }
            }

            // Final chunk carries usage when stream_options.include_usage
            // is set (choices array empty).
            if (event["choices"] as? [[String: Any]])?.isEmpty == true,
               (event["usage"] as? [String: Any]) != nil {
                Self.logUsageIfPresent(event, event: "opencode.streaming.usage")
            }
        }

        guard !accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "OpenCodeGoClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "OpenCode Go streaming returned an empty response."]
            )
        }

        let duration = Date().timeIntervalSince(startTime)
        OdysseusMessageLogStore.shared.append(
            lane: "voice",
            direction: "incoming",
            event: "opencode.streaming.response",
            fields: [
                "model": model,
                "duration": duration,
                "durationMs": Self.elapsedMilliseconds(from: startTime, to: Date()),
                "textDeltaCount": deltaCount,
                "firstTokenLatencyMs": firstDeltaAt.map { Self.elapsedMilliseconds(from: startTime, to: $0) } ?? -1,
                "transport": "sse",
                "text": accumulatedText
            ]
        )
        return (text: accumulatedText, duration: duration)
    }

    // MARK: - Static parsing helpers (unit-testable)

    static func firstChoiceText(from json: [String: Any]) -> String? {
        guard let choices = json["choices"] as? [[String: Any]] else { return nil }
        var textParts: [String] = []
        for choice in choices {
            guard let message = choice["message"] as? [String: Any],
                  let content = message["content"] as? String else { continue }
            textParts.append(content)
        }
        return textParts.joined()
    }

    static func errorPayload(from event: [String: Any]) -> String? {
        if let type = event["type"] as? String, type == "error" {
            if let error = event["error"] as? [String: Any] {
                if let message = error["message"] as? String {
                    return message
                }
                return "OpenCode Go streaming returned an error event."
            }
            if let message = event["message"] as? String {
                return message
            }
            return "OpenCode Go streaming returned an error event."
        }
        if let error = event["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }

    /// Extracts the Go-plan allowance so request logs show how much of the
    /// monthly quota a turn consumed (docs: usage.opencode.allowance).
    static func opencodeUsage(from json: [String: Any]) -> [String: Any]? {
        guard let usage = json["usage"] as? [String: Any],
              let opencode = usage["opencode"] as? [String: Any] else {
            return nil
        }
        return [
            "allowance": opencode["allowance"] ?? 0,
            "billingSource": opencode["billing_source"] ?? "unknown",
            "inputTokens": (usage["prompt_tokens"] as? Int) ?? 0,
            "outputTokens": (usage["completion_tokens"] as? Int) ?? 0
        ]
    }

    static func logUsageIfPresent(_ json: [String: Any], event: String) {
        guard let usageFields = opencodeUsage(from: json) else { return }
        OdysseusMessageLogStore.shared.append(
            lane: "voice",
            direction: "incoming",
            event: event,
            fields: usageFields
        )
    }

    static func networkError(statusCode: Int, body: String) -> NSError {
        let hint: String
        switch statusCode {
        case 401:
            hint = "Invalid OpenCode Go credential — check OPENCODE_API_KEY."
        case 402:
            hint = "OpenCode Go balance/limit reached (Extra Usage off?)."
        case 403:
            hint = "OpenCode Go model access disabled — the Go plan blocks unconfigured regions/models (see Settings › Privacy on opencode.ai)."
        case 429:
            hint = "OpenCode Go rate limited — free-lane throttle or plan limits."
        default:
            hint = ""
        }

        var localized = "OpenCode Go API error (\(statusCode)): \(body)"
        if !hint.isEmpty {
            localized += " — \(hint)"
        }
        return NSError(
            domain: "OpenCodeGoClient",
            code: statusCode,
            userInfo: [NSLocalizedDescriptionKey: localized]
        )
    }

    static func elapsedMilliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
    }
}

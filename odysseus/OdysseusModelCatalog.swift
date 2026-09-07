import Foundation

nonisolated enum OdysseusModelProvider: String, Equatable {
    case apple
    case anthropic
    case openAI
    case codex
    case deepgram
    case opencodeGo

    var displayName: String {
        switch self {
        case .apple:
            return "Apple"
        case .anthropic:
            return "Anthropic"
        case .openAI:
            return "OpenAI"
        case .codex:
            return "Codex"
        case .deepgram:
            return "Deepgram"
        case .opencodeGo:
            return "OpenCode Go"
        }
    }

    /// Coarse family used by the bubble / notch provider selector.
    /// Realtime speech and Deepgram stay outside this three-way switch.
    var voiceBackendFamily: OdysseusVoiceBackendFamily? {
        switch self {
        case .apple:
            return .apple
        case .anthropic:
            return .claude
        case .codex:
            return .codex
        case .openAI:
            return .codex
        case .deepgram:
            return nil
        case .opencodeGo:
            return .go
        }
    }
}

/// Terminal-first voice backend family: Apple on-device, local Codex, Claude Agent SDK,
/// or OpenCode Go (DeepSeek/open models via opencode.ai Inference).
nonisolated enum OdysseusVoiceBackendFamily: String, CaseIterable, Equatable, Sendable {
    case apple
    case codex
    case claude
    case go

    var displayName: String {
        switch self {
        case .apple: return "Apple"
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .go: return "OpenCode Go"
        }
    }

    var shortLabel: String {
        switch self {
        case .apple: return "A"
        case .codex: return "X"
        case .claude: return "C"
        case .go: return "Go"
        }
    }

    /// Default catalog model id when the user picks this family in the bubble selector.
    var defaultModelID: String {
        switch self {
        case .apple:
            return OdysseusModelCatalog.appleFoundationModelID
        case .codex:
            return OdysseusModelCatalog.defaultCodexActionsModelID
        case .claude:
            return OdysseusModelCatalog.defaultAnthropicResponseModelID
        case .go:
            return OdysseusModelCatalog.opencodeGoDeepSeekFlashModelID
        }
    }
}

nonisolated struct OdysseusModelOption: Identifiable, Equatable {
    let id: String
    let label: String
    let provider: OdysseusModelProvider
    /// Published maximum generated output tokens for this model.
    /// For Anthropic this maps to `max_tokens`; for OpenAI Responses this maps to `max_output_tokens`.
    ///
    /// Voice responses must not carry a short-form cap here: the prompt
    /// already asks for concise spoken replies by default, but if the user
    /// asks for a deeper answer the TTS pipeline should be allowed to keep
    /// generating rather than truncating at an artificial "spoken" budget.
    let maxOutputTokens: Int
}

nonisolated enum OdysseusModelCatalog {
    static let defaultSpeechModelID = "gpt-realtime-2.1-mini"
    /// Fast conversational responder. Used for the always-on voice loop —
    /// hears the user, routes direct computer-use locally, and delegates
    /// background work to the configured Codex model.
    static let defaultVoiceResponseModelID = defaultSpeechModelID
    static let defaultAnthropicResponseModelID = "fable-5"
    static let defaultCodexActionsModelID = "gpt-5.6-sol"
    /// On-device Apple Foundation Models (macOS 26+ / Apple Intelligence).
    static let appleFoundationModelID = "apple-foundation"
    /// OpenCode Go plan model: DeepSeek V4.1 Flash via https://opencode.ai/inference/go.
    /// Multimodal on chat completions (verified 2026-10): accepts OpenAI-style
    /// image_url parts, answers stream in `content` after `reasoning_content`.
    static let opencodeGoDeepSeekFlashModelID = "deepseek-v4.1-flash"
    /// Verified vision-capable Go model used as a retry safety net when a
    /// DeepSeek image turn fails upstream ($30/mo allowance on Go).
    static let opencodeGoVisionFallbackModelID = "qwen3.8-flash"
    /// Text/vision model used when a live speech model needs screenshots,
    /// attachments, or Codex fallback. Realtime IDs stay on the audio path.
    static let defaultVoiceAnalysisModelID = defaultCodexActionsModelID
    /// Heavier model used when the voice responder delegates a coding/agent task.
    /// Coding work goes here; the voice path stays on the fast model.
    static let defaultDelegationModelID = "sonnet-5"
    static let defaultComputerUseModelID = defaultCodexActionsModelID

    /// Resolves the delegation model — falls back to a sensible coder
    /// when the user hasn't picked one explicitly.
    static func delegationModel(withID modelID: String?) -> OdysseusModelOption {
        if let modelID {
            let resolved = normalizedModelID(modelID)
            if let match = voiceResponseModels.first(where: { $0.id == resolved }) {
                return match
            }
        }
        return voiceResponseModel(withID: defaultDelegationModelID)
    }

    static let voiceResponseModels: [OdysseusModelOption] = [
        // Voice turns should still be concise by prompt, but never by a
        // hard generation ceiling. Long spoken explanations can stream
        // sentence-by-sentence through TTS without being cut off.
        OdysseusModelOption(id: appleFoundationModelID, label: "Apple On-Device", provider: .apple, maxOutputTokens: 64_000),
        OdysseusModelOption(id: "fable-5", label: "Fable 5", provider: .anthropic, maxOutputTokens: 64_000),
        OdysseusModelOption(id: "sonnet-5", label: "Sonnet 5", provider: .anthropic, maxOutputTokens: 64_000),
        OdysseusModelOption(id: "opus-5", label: "Opus 5", provider: .anthropic, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-5.6-sol", label: "GPT-5.6 Sol", provider: .openAI, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-5.6-terra", label: "GPT-5.6 Terra", provider: .openAI, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-5.6-luna", label: "GPT-5.6 Luna", provider: .openAI, maxOutputTokens: 128_000),
        // OpenCode Go plans include DeepSeek tokens (paid-model lane; external
        // clients cannot reach OpenCode's free tier). Zero data retention.
        OdysseusModelOption(id: opencodeGoDeepSeekFlashModelID, label: "DeepSeek V4.1 Flash (Go)", provider: .opencodeGo, maxOutputTokens: 64_000)
    ]

    static let speechModels: [OdysseusModelOption] = [
        // Realtime models are speech-to-speech response models. When one
        // is selected as the response voice model, it owns both the spoken
        // reply generation and the audio playback path instead of chaining
        // a separate text model into TTS.
        // Default stays on mini for lower latency and cost; full 2.1 is
        // available when stronger realtime reasoning is worth the spend.
        OdysseusModelOption(id: "gpt-realtime-2.1-mini", label: "GPT Realtime 2.1 mini", provider: .openAI, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-realtime-2.1", label: "GPT Realtime 2.1", provider: .openAI, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-realtime-1.5", label: "GPT Realtime 1.5", provider: .openAI, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "deepgram-voice-agent", label: "Deepgram Voice Agent", provider: .deepgram, maxOutputTokens: 128_000)
    ]

    static let responseVoiceModels: [OdysseusModelOption] = speechModels + voiceResponseModels

    static let computerUseModels: [OdysseusModelOption] = [
        OdysseusModelOption(id: "sonnet-5", label: "Sonnet 5", provider: .anthropic, maxOutputTokens: 64_000),
        OdysseusModelOption(id: "opus-5", label: "Opus 5", provider: .anthropic, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-realtime-2.1-mini", label: "GPT Realtime 2.1 mini", provider: .openAI, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-realtime-2.1", label: "GPT Realtime 2.1", provider: .openAI, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-5.6-sol", label: "GPT-5.6 Sol", provider: .codex, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-5.6-terra", label: "GPT-5.6 Terra", provider: .codex, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-5.6-luna", label: "GPT-5.6 Luna", provider: .codex, maxOutputTokens: 128_000),
        OdysseusModelOption(id: opencodeGoDeepSeekFlashModelID, label: "DeepSeek V4.1 Flash (Go)", provider: .opencodeGo, maxOutputTokens: 64_000)
    ]

    static let codexActionsModels: [OdysseusModelOption] = [
        OdysseusModelOption(id: "gpt-5.6-sol", label: "GPT-5.6 Sol", provider: .openAI, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-5.6-terra", label: "GPT-5.6 Terra", provider: .openAI, maxOutputTokens: 128_000),
        OdysseusModelOption(id: "gpt-5.6-luna", label: "GPT-5.6 Luna", provider: .openAI, maxOutputTokens: 128_000)
    ]
    // Local MLX models are intentionally NOT offered for Agent Mode: the local
    // endpoint (mlx_lm at 127.0.0.1:32124) only speaks /v1/chat/completions,
    // but Codex requires the Responses API, so routing agents there 404s on
    // /v1/responses. Keep agents on real cloud providers.

    /// Maps retired / alias model IDs onto the currently offered catalog IDs.
    /// Keep legacy `gpt-realtime-2` pointed at the new mini default so existing
    /// installs do not fall through to a text model.
    static func normalizedModelID(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultVoiceResponseModelID }
        switch trimmed.lowercased() {
        case "gpt-realtime-2", "gpt-realtime-2.0", "gpt-realtime-2-mini":
            return defaultSpeechModelID
        case "claude-haiku-4-5", "claude-haiku-4-6", "haiku-5", "fable", "claude-fable-5":
            return defaultAnthropicResponseModelID
        case "claude-sonnet-4-6", "sonnet", "claude-sonnet-5":
            return "sonnet-5"
        case "claude-opus-4-6", "opus", "claude-opus-5":
            return "opus-5"
        case "gpt-5.5", "gpt-5.4", "gpt-5.3-codex", "gpt-5.2-codex", "gpt-5.2":
            return defaultCodexActionsModelID
        case "gpt-5.4-mini":
            return "gpt-5.6-luna"
        case "deepseek", "deepseek-v4.1", "deepseek-v4.1-free", "go-deepseek-v4.1-flash", "opencode-go/deepseek-v4.1-flash":
            return opencodeGoDeepSeekFlashModelID
        default:
            return trimmed
        }
    }

    static func voiceResponseModel(withID modelID: String) -> OdysseusModelOption {
        let resolved = normalizedModelID(modelID)
        if let match = responseVoiceModels.first(where: { $0.id == resolved }) {
            return match
        }
        // Unknown IDs reset to the product default (speech-to-speech), not the
        // first text model in the list (which used to silently become Haiku).
        return responseVoiceModels.first { $0.id == defaultVoiceResponseModelID }
            ?? speechModels.first
            ?? voiceResponseModels[0]
    }

    static func voiceAnalysisModel(withID modelID: String?) -> OdysseusModelOption {
        if let modelID {
            let resolved = normalizedModelID(modelID)
            if !isSpeechModelID(resolved),
               let match = voiceResponseModels.first(where: { $0.id == resolved }) {
                return match
            }
        }
        if let match = voiceResponseModels.first(where: { $0.id == defaultVoiceAnalysisModelID }) {
            return match
        }
        return voiceResponseModels[0]
    }

    static func codexVoiceSessionModel(withID modelID: String?) -> OdysseusModelOption {
        if let modelID {
            let resolved = normalizedModelID(modelID)
            if !isSpeechModelID(resolved),
               let match = codexActionsModels.first(where: { $0.id == resolved }) {
                return match
            }
        }

        let analysisModel = voiceAnalysisModel(withID: modelID)
        if let match = codexActionsModels.first(where: { $0.id == analysisModel.id }) {
            return match
        }

        return codexActionsModels.first { $0.id == defaultCodexActionsModelID } ?? codexActionsModels[0]
    }

    static func isSpeechModelID(_ modelID: String) -> Bool {
        let resolved = normalizedModelID(modelID)
        return speechModels.contains { $0.id == resolved }
    }

    static func speechModel(withID modelID: String?) -> OdysseusModelOption {
        if let modelID {
            let resolved = normalizedModelID(modelID)
            if let match = speechModels.first(where: { $0.id == resolved }) {
                return match
            }
        }
        return speechModels.first { $0.id == defaultSpeechModelID } ?? speechModels[0]
    }

    static func computerUseModel(withID modelID: String) -> OdysseusModelOption {
        let resolved = normalizedModelID(modelID)
        return computerUseModels.first { $0.id == resolved }
            ?? computerUseModels.first { $0.id == defaultComputerUseModelID }
            ?? computerUseModels[0]
    }

    static func codexActionsModel(withID modelID: String) -> OdysseusModelOption {
        let resolved = normalizedModelID(modelID)
        return codexActionsModels.first { $0.id == resolved }
            ?? codexActionsModels.first { $0.id == defaultCodexActionsModelID }
            ?? codexActionsModels[0]
    }
}

# Odysseus Agent Instructions

## Non-Negotiable Rules

1. Check model validity before making assumptions about current model releases or identifiers.
2. Never use emoji unless the user explicitly asks for them.
3. Do not run `xcodebuild` from the terminal. Use Xcode for app builds and permission testing.
4. The 2026-10 rename (cursor-buddy/OpenClicky -> odysseus/Odysseus) is done. Do not rename it again casually; references exist across targets, scripts, CI, and Codex resources.

## Overview

Odysseus is a macOS menu-bar companion app by mubtikr. It uses SwiftUI with AppKit bridging for a custom floating panel, cursor overlay, Agent Mode dashboard, and macOS permission flows.

The product identity is Odysseus:

- Bundle identifier: `com.mubtikr.odysseus`
- Display name: `Odysseus`
- Copyright: mubtikr

## Architecture

- App type: menu-bar app using `LSUIElement=true`
- Frameworks: SwiftUI, AppKit, AVFoundation, ScreenCaptureKit
- Pattern: `@MainActor` state orchestration with observable SwiftUI views
- Voice input: push-to-talk via a global CGEvent tap and pluggable transcription providers
- Voice response: selectable model families — DeepSeek via OpenCode Go, Claude, OpenAI/Codex, Apple on-device, Deepgram
- Text-to-speech: Microsoft Edge neural voices by default (free), ElevenLabs/Cartesia/Deepgram/OpenAI Realtime optional
- Screen context: ScreenCaptureKit screenshots when the user invokes help
- Agent Mode: bundled Codex runtime and Odysseus resource pack in `AppResources/Odysseus`

## Key Files

- `odysseus/odysseusApp.swift`: app entry point and delegate hookup.
- `odysseus/CompanionManager.swift`: central app state machine for voice, screen capture, Claude, TTS, overlay, settings, and Agent Mode.
- `odysseus/MenuBarPanelManager.swift`: menu-bar item and floating panel lifecycle.
- `odysseus/CompanionPanelView.swift`: main Odysseus panel and settings subscreen.
- `odysseus/OverlayWindow.swift`: cursor overlay, agent dock icons, captions, and response cards.
- `odysseus/CodexHUDWindowManager.swift`: Agent Mode dashboard window.
- `odysseus/CodexHomeManager.swift`: prepares the local Codex home using Odysseus bundled resources.
- `odysseus/OdysseusCodexConfigTemplate.swift`: renders Codex configuration for Odysseus Agent Mode.
- `odysseus/OdysseusNextStageParityModels.swift`: knowledge index, permission guide, response-card, and handoff support models.
- `AppResources/Odysseus/`: bundled Agent Mode instructions, skills, wiki seed, runtime, and completion sound.

## Configuration

Odysseus should use local keys and user configuration. Do not add Google login or hosted key sync:

- `ANTHROPIC_API_KEY` for Claude responses
- `ELEVENLABS_API_KEY` for ElevenLabs TTS
- `OPENAI_API_KEY` for Codex/Agent Mode where needed
- `OPENCODE_API_KEY` for the OpenCode Go plan gateway (DeepSeek V4.1 Flash)

Do not introduce a hard dependency on a Cloudflare Worker for the final app.

## Inference Routing

Two independent layers — keep them straight:

1. **Provider selection (driven by Settings + bubble/notch selector).** Every model in `OdysseusModelCatalog` carries a `provider` (`.apple` / `.anthropic` / `.openAI` / `.codex` / `.deepgram` / `.opencodeGo`). `CompanionManager.analyzeVoiceResponse` and the element-pointing path switch on the selected model's provider to choose the backend family:
   - `.apple` -> on-device Apple Foundation Models (`AppleFoundationModelsVoiceClient`; free, no API key; text-only)
   - `.anthropic` -> Claude (`ClaudeAgentSDKAPI` then `ClaudeAPI`)
   - `.openAI` -> `OpenAIAPI` (with Codex app-server first for non-speech models)
   - `.codex` -> `CodexVoiceSession` / `CodexPointDetector` (selecting e.g. `gpt-5.6-sol` means Codex handles it)
   - `.deepgram` -> Deepgram Voice Agent
   - `.opencodeGo` -> `OpenCodeGoClient` (Chat Completions SSE at `https://opencode.ai/inference/go/openai/v1/chat/completions`; requires `Authorization: Bearer $OPENCODE_API_KEY`, `x-opencode-session` per conversation — `opencodeGoAPI.rotateSession()` on each new voice/text turn — and `User-Agent: odysseus/1.0`. **DeepSeek V4.1 Flash is multimodal** on the gateway: OpenAI-style `image_url` parts work on chat completions; the model reasons via `reasoning_content` and streams the answer in `content` — never cap `max_tokens` low or content gets starved (`finish_reason: length`). A failed image turn retries once with the verified Go vision model `qwen3.8-flash`. Keep `genie-gate`: never let this route reach Codex/OpenAI — text AND vision stay on the Go key.)
   Coarse family chips (Apple / Codex / Claude / Go) live on the response bubble and notch via `OdysseusVoiceBackendSelector` + `OdysseusProviderDiscovery` (auto-detect installed CLI / on-device availability / key presence — do not package runtimes).
2. **Within-provider ordering (money rule).** For the Claude branch, the Claude Agent SDK is the PRIMARY path because it uses the local Claude Code sign-in already paid for. Direct `ClaudeAPI` HTTP is FALLBACK ONLY (SDK nil or throws). Never short-circuit to direct REST for latency or capability reasons — direct REST bills per token. The OpenAI/Codex branch follows the same shape: Codex app server first, OpenAI key fallback. Apple is always free/local. EXEMPTION: realtime speech models (`gpt-realtime-2.1-mini` default, `gpt-realtime-2.1`, `gpt-realtime-1.5`; legacy `gpt-realtime-2` aliases to mini) use the direct Realtime API path only.
3. **Voice defaults (free-first).** STT is `automatic` = Parakeet on-device (free), Apple Speech fallback. TTS defaults to Microsoft Edge (`microsoftEdge` free, voice `en-US-BrianMultilingualNeural`); engine resolution falls back to Edge automatically when no OpenAI key exists — do not force-revert the startup migration block to Realtime unless a key is present.

Do not delete `ClaudeAPI.swift` or the HTTP path — it is the deliberate fallback. Before editing any Claude/OpenAI call site, confirm the order is SDK/app-server -> key fallback.


## Development Rules

- Prefer existing design-system tokens and local view patterns.
- Keep UI state updates on the main actor.
- Use async/await for asynchronous work.
- Use AppKit only where SwiftUI cannot provide the needed macOS behavior.
- Keep changes scoped to the requested behavior.
- Preserve user or generated changes in the worktree unless explicitly told to revert them.
- User-facing copy should use the Odysseus product name.

## Verification

Use lightweight checks that do not disturb macOS permissions:

```sh
swiftc -parse <relevant Swift source files>
```

Do not launch unsigned or throwaway builds for TCC permission testing.

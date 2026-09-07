# 3D Model Generation — Integration Guide

This module adds text-to-3D (low-poly stylized) to Odysseus. Provider: **Tripo AI**.
Output: **GLB**. Viewer: a floating macOS window with an inline rotatable SceneKit preview.

## Why a floating window (not the chat panel)

Odysseus's "chat" is voice-driven — `CompanionPanelView.swift` is a settings/control panel,
not a chat-message list, and `conversationHistory` is flat string tuples with no message-row
UI. So the user-visible 3D preview surface is a floating window that auto-opens whenever a
generation job starts (queued by the dispatcher) and lists in-flight + recent assets.

## Files added

| File | Role |
|---|---|
| `ThreeDGenerationTypes.swift` | Protocol + request/result/error types + `ThreeDStyle` |
| `TripoThreeDProvider.swift` | Tripo v2 OpenAPI client (submit → poll → download) |
| `ThreeDGenerationService.swift` | Orchestrator + persistent index, `@MainActor` ObservableObject |
| `ThreeDViewerView.swift` | SwiftUI SceneKit viewer (auto-rotate, camera control) |
| `ThreeDChatBubbleView.swift` | Bubble wrapper with progress, Show-in-Finder, Re-gen |
| `ThreeDGenerationTool.swift` | Agent-tool surface (`generate_3d`) with JSON schema |
| `ThreeDGenerationDispatcher.swift` | Parses `/3d` slash command + `[ODYSSEUS_3D]` sentinel |
| `ThreeDViewerWindowManager.swift` | Floating window manager, auto-opens on first job |

## Edits made to existing files (additive only)

| File | Change |
|---|---|
| `CompanionManager.swift` | One block at the top of `rememberVoiceExchange(...)` — scans both user transcript and assistant response for `/3d` + sentinel, dispatches via `ThreeDGenerationDispatcher`. |
| `ClaudeAgentSDKAPI.swift` | Appended `ThreeDGenerationDispatcher.systemPromptInstruction` to the persistent bridge system prompt — teaches Claude Agent SDK to emit `[ODYSSEUS_3D] prompt: "…"` when the user asks for a 3D model. |
| `CodexAgentSession.swift` | Appended the same instruction to `developerInstructions` at thread-start — Codex CLI gets the same behaviour. |

## Xcode setup (do these once)

### 1. Add files to the `odysseus` target

In Xcode → File → Add Files to "odysseus"… → select all eight new
`.swift` files (plus this `.md` if you want it in the project):

- `ThreeDGenerationTypes.swift`
- `TripoThreeDProvider.swift`
- `ThreeDGenerationService.swift`
- `ThreeDViewerView.swift`
- `ThreeDChatBubbleView.swift`
- `ThreeDGenerationTool.swift`
- `ThreeDGenerationDispatcher.swift`
- `ThreeDViewerWindowManager.swift`

Make sure **Add to targets: odysseus** is ticked. The three existing-file
edits (`CompanionManager`, `ClaudeAgentSDKAPI`, `CodexAgentSession`) are
already in place and won't compile until the new files are part of the target.

### 2. Add Swift Package: GLTFSceneKit

GLB → SceneKit needs a loader. We use **magicien/GLTFSceneKit** (MIT).

Xcode → File → Add Package Dependencies… →
`https://github.com/magicien/GLTFSceneKit.git` → **Up to Next Major** from
`0.4.0` → add the `GLTFSceneKit` library product to the `odysseus`
target.

`ThreeDViewerView.swift` already guards the import with `#if canImport(GLTFSceneKit)`
so the project still compiles before the package is added (with a runtime
"package not linked" error in the bubble until it is).

### 3. Set the Tripo API key

Two options, in priority order:

1. **UserDefaults** (production path): set `Odysseus.Tripo3D.APIKey` from
   the Settings UI. Quickest test:
   ```bash
   defaults write com.odysseus.odysseus Odysseus.Tripo3D.APIKey 'tsk_...'
   ```
2. **Env var** for dev: `TRIPO_API_KEY=tsk_...` in the scheme's Run env.

Replace with Keychain via your existing key-storage pattern (the
ElevenLabs/Deepgram providers in this repo) when you're happy with the flow —
swap `ThreeDGenerationService.readTripoAPIKey()`.

Get a key: https://platform.tripo3d.ai (Pricing: ~10 credits/text-to-model;
quad mesh +5 credits.)

## Wiring tasks (the parts that touch existing files)

These are intentionally **not done yet** so you can review before I edit your
1,415-line `CompanionPanelView.swift` and 13,131-line `CompanionManager.swift`.

### A. Render the bubble in the chat list (`CompanionPanelView.swift`)

In the message-row builder, when a message has 3D-tool metadata:

```swift
// somewhere in the message row switch:
if let jobId = message.threeDJobId,
   let job = ThreeDGenerationService.shared.jobs.first(where: { $0.id == jobId }) {
    ThreeDChatBubbleView(
        mode: .job(job),
        onRetry: { ThreeDGenerationService.shared.generate(prompt: job.prompt, style: job.style) },
        onCancel: { ThreeDGenerationService.shared.cancelJob(job.id) }
    )
}
```

For older completed assets surfaced from history:
```swift
ThreeDChatBubbleView(mode: .asset(result))
```

Add a `threeDJobId: UUID?` field to whatever message struct
`CompanionManager` uses, populated when the tool returns its `job_id`.

### B. Register the tool with Codex agent (`CodexAgentSession.swift`)

When you build the Codex tool list, append:

```swift
CodexTool(
    name: ThreeDGenerationTool.name,
    description: ThreeDGenerationTool.description,
    parameters: ThreeDGenerationTool.jsonSchema,
    handler: { args in
        let result = try await MainActor.run {
            try ThreeDGenerationTool.invoke(arguments: args)
        }
        return try JSONEncoder().encode(result)
    }
)
```

(Exact constructor depends on how Codex tools are declared in the file — the
core idea: name/description/schema/handler.)

### C. Register the tool with Claude agent (`ClaudeAgentSDKAPI.swift`)

Same shape, Anthropic tool format:

```swift
let generate3DTool = AnthropicTool(
    name: ThreeDGenerationTool.name,
    description: ThreeDGenerationTool.description,
    input_schema: ThreeDGenerationTool.jsonSchema
)
// In your tool dispatcher:
case "generate_3d":
    let result = try await MainActor.run {
        try ThreeDGenerationTool.invoke(arguments: input)
    }
    return ToolResult(json: result)
```

### D. (Optional) Slash-command shortcut

For users who'd rather skip the LLM and type the prompt directly, add a chat
input parser:

```swift
if userText.hasPrefix("/3d ") {
    let prompt = String(userText.dropFirst(4))
    let jobId = ThreeDGenerationService.shared.generate(prompt: prompt)
    // attach jobId to a new assistant message in the conversation
    return  // don't send to LLM
}
```

## Behaviour summary once wired

1. User types: *"can you make me a low-poly mushroom?"*
2. Agent calls `generate_3d({ prompt: "a friendly mushroom with a polka-dot cap", style: "low_poly_stylized" })`
3. Tool returns `job_id` + `user_message` instantly. Agent says the message
   ("Generating a low_poly_stylized 3D model of …"). A `ThreeDChatBubbleView`
   appears bound to that job, showing a progress bar.
4. ~30–60s later the bubble swaps to an inline rotatable model. "Show in
   Finder" and "Copy Path" point at
   `~/Library/Application Support/Odysseus/Generated3D/<task_id>.glb`.

## Provider extension (later)

To add Meshy or Fal/Hunyuan: implement `ThreeDGenerationProvider`, then
`ThreeDGenerationService.shared.setProvider(MeshyProvider(...))`. Nothing in
the UI or tool layer needs to change.

## Known follow-ups

- [ ] Replace UserDefaults key storage with Keychain (match
      ElevenLabs/Deepgram pattern in this repo).
- [ ] Cancel button should actually cancel the in-flight URLSession task
      (track the `Task` per job in the service).
- [ ] Add a Settings panel section (provider picker, default style toggle,
      quad/PBR toggles, API key field).
- [ ] Thumbnail-only history view (Pet-style grid) for the Generated3D folder.
- [ ] Export to USDZ (so AirDrop / Quick Look on iPhone works) via
      `Model I/O` + `MDLAsset.export`.

## Quick smoke test (no app build required)

```bash
# from anywhere with curl + jq + TRIPO_API_KEY exported
curl -s -X POST https://api.tripo3d.ai/v2/openapi/task \
  -H "Authorization: Bearer $TRIPO_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "text_to_model",
    "prompt": "low poly, stylized, flat shaded, faceted clean geometry, a friendly fox",
    "texture": true, "pbr": true, "quad": true
  }' | jq
# (Omit model_version — Tripo picks its current default. Pinning to a stale
# version like v2.5-20250123 will fail with HTTP 401 even with a valid key.)
# → grab task_id, then:
curl -s https://api.tripo3d.ai/v2/openapi/task/<task_id> \
  -H "Authorization: Bearer $TRIPO_API_KEY" | jq
# wait for status:success and download data.output.pbr_model
```

If that smoke test produces a usable GLB, the Swift client will too.

# Odysseus

A macOS menu-bar companion that watches your screen, hears you, and answers out loud — fully local by default, OpenAI never required.

**Brain:** your choice — [DeepSeek V4.1 Flash](https://opencode.ai/v2/docs/console/go/) through an [OpenCode Go](https://opencode.ai/v2/docs/console/go/) subscription (recommended, $10/mo), on-device Apple Foundation Models, or a classic Claude / OpenAI / Deepgram key.
**Voice in:** on-device transcription (Parakeet or Apple Speech) — nothing leaves the Mac.
**Voice out:** free Microsoft Edge neural TTS (or ElevenLabs / Cartesia / Deepgram / OpenAI Realtime if you bring a key).
**Agent Mode:** background sessions that see your screen, answer, research, and hand off concrete next actions.

## How it fits together

```
PTT / wake word ─▶ on-device STT ─▶ model (Go gateway / Apple / Claude…) ─▶ sentence-pipelined TTS ─▶ reply
       │                    │                              │
       │                    └── screenshots only when you ask ────────┤
       ▼                                                             ▼
   agent sessions (Go gateway, vision)                    response card + caption overlay
```

- Push-to-talk holds a global shortcut; release to talk. Wake word: "Hey Odysseus" (on Apple Speech).
- Screen context is attached only when the request needs it — screenshots never leave the machine except to your chosen model
  endpoint.
- Agent sessions run the task brief + inline screen images through the configured model and stream an answer into the session card.

## Install

Grab the latest DMG from [Releases](https://github.com/mubtikr/odysseus/releases) and drag Odysseus to Applications.

> The CI build is ad-hoc signed. On first launch macOS asks once to confirm the app — right-click Open, or
> `xattr -dr com.apple.quarantine /Applications/Odysseus.app`.

### First run

Odysseus walks you through macOS permissions (Accessibility, Microphone, Screen Recording) on first open. For the brain you have two zero-friction options:

1. **OpenCode Go (recommended)** — subscribe at [opencode.ai/console](https://opencode.ai/console), copy your `oc_sk_...` key, and paste it into
   Odysseus **Settings → OpenCode Go key** (or the first-run panel field). It is stored in your login keychain.
2. **Apple Intelligence** — enable it in System Settings and pick "Apple On-Device": no key at all, but text-only answers.

Advanced: keep keys in `~/.config/odysseus/secrets.env` instead (`OPENCODE_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `ELEVENLABS_API_KEY`, …).
Or launch with environment variables. Keys never leave your machine.

## Configuration reference

| Setting | Where | Notes |
| --- | --- | --- |
| `OPENCODE_API_KEY` | Settings field / secrets env | DeepSeek V4.1 Flash + agent brain (Go plan) |
| Transcription | Settings | `Automatic` = Parakeet (local) → Apple Speech |
| TTS engine | Settings | Default Microsoft Edge (free); optional ElevenLabs, Cartesia, Deepgram, OpenAI Realtime |
| Theme | Settings | Coral default to match the logo; Accent picker available |
| STEL session, wake word, widget | Settings | optional |

## Build

```sh
open odysseus.xcodeproj        # select the odysseus scheme, Cmd+R
# local DMG:
bash scripts/release.sh 1.1.0 1 --local   # → dist/Odysseus-1.1.0-1.dmg
```

A run script verifies Swift syntax without touching TCC permissions: `xcrun swiftc -parse <files>`.

## Release pipeline

GitHub Actions builds a versioned DMG on every push to `main`: the patch version increments, the build number is the CI run
number, and the artifact is attached to an auto-created Release with install instructions and a SHA-256.
With paid Apple Developer secrets configured (`APPLE_CERT_P12`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`) it
also signs, notarizes, and (optionally, with `SPARKLE_ED_PRIVATE_KEY`) publishes the Sparkle `appcast.xml` feed.

## Privacy

- Transcription: on-device (Parakeet/Apple). Whisper providers are opt-in.
- LLM calls go only to the provider you configure (OpenCode Go DeepSeek — zero retention, no training; Apple on-device — nothing leaves the Mac).
- Screen captures: local files until a request needs vision; never pooled or synced.
- No cloud login, no hosted key storage.
## License

Odysseus is released under the [MIT License](LICENSE).

```
MIT License
Copyright (c) 2026 mubtikr
```

You are free to use, modify, distribute, and sell — attribution is appreciated but not required. Third-party code and model credits live in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Contributing

Contributions are welcome — the project is public and MIT-licensed.

- **Bugs / ideas:** open a [GitHub Issue](https://github.com/mubtikr/odysseus/issues) with the macOS version, model, and a short repro.
- **Code:** fork → feature branch (`feat/<topic>`) → PR. Keep diffs focused; CI is the gate (DMG build on every push to `main` plus selected PRs).
- **Checks before you push:** `xcrun swiftc -parse` on touched Swift files, and a local DMG build (`bash scripts/release.sh 1.1.0 1 --local`) if you touch packaging.
- No Claude Code / AI-generated commit attribution, no personal API keys, no binaries — DMGs come from CI only.
- Brain + model additions follow the provider routing rules in AGENTS.md (free/local-first, per-family routing, money rule).

### Roadmap ideas

- Shell/file tools for Agent Mode on the Go gateway
- Optional Sparkle auto-update feed (Ed25519-signed `appcast.xml`)
- More STT/TTS providers behind the existing routing switch

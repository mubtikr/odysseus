# OpenClicky Skill Compatibility Policy

This policy applies to bundled skills when they run inside OpenClicky Agent Mode.

## Current Runtime Boundaries

- Agent Mode runs Codex with local filesystem and shell access, but skills must still respect explicit user intent, app-level policy, and macOS permission prompts.
- OpenClicky's native capabilities include local files, shell commands, web/current research when available, screenshots supplied by OpenClicky, local computer-use backends, the external visual bridge, local keys, and artifact handoff metadata.
- Do not assume provider-backed image generation, video generation, slide rendering, Spotify tools, Google Workspace tools, GitHub tools, or third-party CLIs exist unless the current runtime exposes them or the local command/auth check passes.
- Prefer structured local integrations over browser automation. If a structured tool or CLI is unavailable, stop with the exact missing setup step instead of silently falling back to risky UI automation.

## Permission Classes

- Read-only: search, summarize, inspect, list, preview, and draft. These are safe after normal task intent is clear.
- Local write: create or edit files inside the selected project/output location. Use archive-first rules when replacing OpenClicky memory, prompts, skills, config, runtime notes, or learned artifacts.
- External write: the user's instruction IS the approval for writes they clearly asked for — creating calendar events, modifying cloud docs, adding rows, renaming, moving, completing tasks, opening PRs, and similar reversible actions the request names execute directly; do not draft-and-wait or re-confirm an action the user already named. Require explicit user approval immediately before execution ONLY for the narrow risky set: sending email/messages, deleting or archiving existing data, overwriting or replacing content the user did not ask you to touch, merging, deploying, publishing, trading, and spending money.
- Credential/auth setup: do not start OAuth, keychain, token, or passphrase flows unless the user explicitly asked for setup. Report the missing credential or account clearly.
- macOS TCC: do not run commands that intentionally trigger new Accessibility, Screen Recording, Contacts, Calendar, Photos, Reminders, Messages, Mail, Full Disk Access, Camera, Microphone, or Speech Recognition prompts unless the user asked for that permission flow.

## Visual Guidance Tools

OpenClicky's external bridge currently supports local token-gated endpoints for cursor pointing, multi-cursors, captions, screenshots, click, clear, speak, notify, multi-call batches, temporary scribble/freehand paths, temporary rectangle highlights, and MCP-style tool descriptors.

- Use coordinates only for visible, current screen content.
- Keep captions short and avoid covering critical UI.
- Use `/clear` before changing scenes or ending stale tours.
- Scribble/freehand path and rectangle highlight overlays are supported when `GET /health` reports `visual_guidance.scribble` and `visual_guidance.rectangle` as `supported` and `GET /mcp/tools` exposes `show_scribble`, `show_highlight`, and `show_rectangle`. If the capability status is `gated`, do not call those tools until the runtime flag is enabled. Do not claim spotlight masks, arrows, or persistent annotations exist until those descriptors are added.
- For clicks, prefer element-aware/native computer-use tools when available; use raw coordinate clicks only when the target is visible and unambiguous.

## Gmail OAuth Tools

OpenClicky's external bridge may advertise `gmail.oauth` only when the local runtime flag `openClickyGmailOAuthToolsEnabled` / `OPENCLICKY_GMAIL_OAUTH_TOOLS_ENABLED` is on. Even then, `gmail_list_messages`, `gmail_read_message`, and `gmail_draft_reply` are stubs that return structured not-implemented errors until the local OAuth/gog backend is wired.

- Treat Gmail as risky external-account data.
- Prefer the bundled `gog` / `google-workspace-gogcli` skill path for real mailbox reads when available.
- Require local Google OAuth and least-privilege Gmail scopes before live mailbox reads.
- List, search, read, summarize, and draft-only reply preparation are read-oriented actions when auth is already available and task intent is clear.
- Do not call send, forward, reply-all, delete, archive, label, mark-read, or other mailbox mutations from the stub path.
- If a Gmail bridge tool returns `status: gated` / HTTP 501, stop and report that the bridge backend is not implemented yet.
- Future Gmail sends must require explicit confirmation of recipient, subject, body, account, and attachments immediately before execution.

## Output and Artifacts

- User-facing deliverables belong in the configured project/output location, not loose at the projects root.
- Final artifact metadata should list only files or URLs the user should open or share.
- Exclude logs, temp files, helper scripts, package caches, lockfiles, and build outputs from artifact lists unless the user explicitly asked for them.

## Validation

For skill and prompt changes, run lightweight text validation such as frontmatter/header checks and targeted `rg` scans. For Swift source changes, use `swiftc -parse <relevant Swift source files>` only; do not run terminal `xcodebuild` for OpenClicky.

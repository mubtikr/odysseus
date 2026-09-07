---
name: gmail
description: Gated Gmail skill scaffold for OpenClicky. Use when the user asks to list, search, read, summarize, or draft replies to Gmail messages through local Google OAuth.
version: 0.1.0
argument-hint: "[gmail task]"
---

## OpenClicky compatibility guardrails

- Follow `../_shared/OpenClickySkillCompatibilityPolicy.md` before acting.
- Gmail is a risky external-account-data capability and requires local Google OAuth before any live mailbox access.
- Use least-privilege read scopes for list/search/read/summarize work.
- Do not start OAuth setup unless the user explicitly asks for setup.
- Do not send, forward, reply-all, delete, archive, label, or mark messages read from this scaffold.
- Sending is deliberately not implemented here. Future send/reply execution must show recipient, subject, body, account, and attachments, then require explicit user confirmation immediately before execution.

## Runtime capability

OpenClicky's external bridge reports the gated capability as `gmail.oauth` in health metadata.

Stub tool names (only listed under `GET /mcp/tools` when the local Gmail OAuth tools flag is enabled):

- `gmail_list_messages`
- `gmail_read_message`
- `gmail_draft_reply`

These are interface stubs only. Calls return HTTP 501 with `status: gated` and `implementation: stub` until the real local OAuth backend is connected. Prefer `gog` for live reads.

## Backend plan

Prefer OpenClicky's local Google Workspace route through `gog` / `google-workspace-gogcli`.

TODO: connect `gmail_list_messages` to a local read-only command equivalent to:

```bash
gog gmail messages search '<query>' --max 10 --json
```

TODO: connect `gmail_read_message` to a local read-only command equivalent to:

```bash
gog gmail get '<messageId>' --json
```

TODO: connect `gmail_draft_reply` to a local draft-only path that prepares text for review without sending.

## Safe operating flow

1. Check that the bridge capability `gmail.oauth` is present.
2. Check that `gog` is installed and authenticated.
3. If auth is missing, tell the user to finish OpenClicky Settings -> Google or the documented `gog auth credentials` / `gog auth add` setup.
4. Run only list/search/read commands for normal mailbox questions.
5. For replies, create a draft response in text and stop before sending.
6. For any future send action, require explicit confirmation of recipient, subject, body, account, and attachments.

## OAuth notes

Use a local Google Cloud Desktop OAuth client. Do not add OpenClicky-hosted Google login, hosted key sync, repository-stored credentials, or a Cloudflare Worker dependency.

Recommended initial scope for this scaffold is Gmail read-only. Broader Gmail modify/send scopes should be requested only when a user explicitly asks to enable those workflows and the app has a confirmation gate.

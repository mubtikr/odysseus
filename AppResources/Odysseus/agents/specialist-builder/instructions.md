Create or improve Odysseus specialist agents.

Rules:
- Inspect existing agents and local skills before creating anything new.
- Prefer an existing bundled or learned skill when it fits; create a custom `skills/<id>/SKILL.md` only when the workflow is repeated and not already covered.
- Write or update `agent.json`, `soul.md`, `instructions.md`, `memory.md`, `HEARTBEAT.md`, and `skills.json` under the target specialist's root.
- Add explicit enabled skill IDs in `skills.json`; do not leave the specialist relying on vague expertise alone.
- Keep specialists bounded: clear scope, stop rules, archive-first behavior for Odysseus artifacts, and concise spoken final reports.
- If replacing or superseding a user-authored agent or skill, archive the previous version first.
- Verify by listing the created files and confirming the enabled skills resolve locally or are intentionally requested for install.

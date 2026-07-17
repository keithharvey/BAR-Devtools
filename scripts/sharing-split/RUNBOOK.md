# sharing-split runbook

## The normal cycle (after every `fmt-mig-generate`)

`fmt-mig-generate` rewrites `fmt-llm`, so the sharing stack must be replayed onto it:

```bash
just bar::sharing-split rebase build verify push update-prs
```

If it runs clean, you're done.

## When `rebase` conflicts (the usual case)

The script leaves the rebase **in progress** — do not abort, do not start a manual rebase.

1. Resolve the conflicts in `Beyond-All-Reason/`. The recurring one is
   `gui_advplayerslist.lua` `DrawState`: fmt-llm has
   `local _, _, _, ai = spGetPlayerInfo(playerID)`, Sharing 6/7 intentionally
   replaces it with `local ai = player[playerID] and player[playerID].ai`.
   **Take the sharing side.** In general: the sharing commit's version wins;
   fmt-llm only ever restyles the pre-sharing line.
2. `git -C Beyond-All-Reason rebase --continue` (repeat 1–2 if more commits conflict).
3. Re-run **without** `rebase`:

```bash
just bar::sharing-split gen-manifest build verify push update-prs
```

`gen-manifest` is required here — `rebase` normally regenerates the manifest
itself, but the conflict exit skips that.

## Sanity check before build (cheap, catches silent commit loss)

```bash
git -C Beyond-All-Reason log --oneline origin/fmt-llm..sharing_tab
```

You must see **every** `Sharing N/7` commit (plus any fixups on top). If layer 1
is missing, git dropped it — reset `sharing_tab` to the last reflog entry that
still contains it and redo the rebase.

## Known failure modes

- **`Sharing 1/7` silently dropped** — old `cmd_rebase` used a fixed `$TIP~N`;
  a fixup commit on top of the stack made it undercount and treat layer 1 as
  base. Fixed 2026-07-17: the rebase now anchors on the layer-1 commit message.
  The sanity check above still catches any regression.
- **`fatal: '_sharing_build' is already used by worktree`** — a worktree
  (e.g. `~/code/sharing-split`) holds the scratch branch.
  Free it: `git -C <worktree> checkout --detach`.
- **Layer commit fails with "nothing to commit"** — the manifest is misaligned
  with the commit range (usually a symptom of a dropped commit; see above).
- **Fixup commits on `sharing_tab`** are fine: `build` absorbs them and
  normalizes `sharing_tab` back to exactly the 7 layer commits.

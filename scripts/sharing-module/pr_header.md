### 🧩 Chain PR 3 of 3 — stacked on #5704 (The Sharing Tab)

- 1 · Type migration stack (#8235)
- 2 · The Sharing Tab (#5704)
- **3 · The Modules Format** ← you are here

> [!WARNING]
> **Draft, stacked.** Based on `sharing/05-game-modes-export` — the top of #5704's split stack — so the diff below is exactly this PR's own work: the **16 commits from `modules: module framework + loader hooks` onward**. The sharing feature itself is reviewed in #5704's split PRs; this PR reviews the module format.

> [!IMPORTANT]
> **This branch is deterministically regenerated**, same discipline as the sharing split: the ~80-file relocation commit is generated from a move map against `sharing_tab`'s tip, and the hand-authored overlay commits are cherry-picked on top — so when #5704 moves under review, `just bar::sharing-module rebuild && verify` replays the branch and conflicts can only appear in the small overlay, never the move commit. Regeneration is byte-identical (`git rev-parse HEAD^{tree}` equal before/after). Tooling lives beside `bar::sharing-split` in BAR-Devtools and may fold into it.

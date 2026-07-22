### 🧩 The Modules Format — tip of the sharing stack (#8411)

- 1 · Type migration stack (#8395 → #8398)
- 2 · The sharing stack (#8125 → #8095; feature tracking: #8412)
- **3 · The Modules Format** ← you are here

> [!NOTE]
> Based on `sharing/05-game-modes-export` (#8095) — the top of the sharing split — so the diff below is exactly this PR's own work: the overlay commits from `modules: module framework + loader hooks` onward. The sharing feature itself is reviewed in the sharing stack PRs; this PR reviews the module format.

> [!IMPORTANT]
> **This branch is deterministically regenerated**, same discipline as the sharing split: the ~80-file relocation commit is generated from a move map against `sharing_tab`'s tip, and the hand-authored overlay commits are cherry-picked on top — so when the sharing stack moves under it, `just bar::sharing-module rebuild && verify` replays the branch and conflicts can only appear in the small overlay, never the move commit. Regeneration is byte-identical (`git rev-parse HEAD^{tree}` equal before/after). Tooling lives beside `bar::sharing-split` in BAR-Devtools and may fold into it.

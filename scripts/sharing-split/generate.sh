#!/usr/bin/env bash
# Deterministically rebuild the 7-PR sharing stack by file partition.
# Each file is assigned to exactly one layer and materialized in its final
# (TIP) form, so every file in every PR is byte-identical to TIP.
# TIP sits directly on $BASE (the migrated line): its 7 commits carry natively
# migrated content, so every PR diff is noise-free. The type-migration stack
# (#8235) merges first; this stack then retargets to master unchanged.
# Back-out: sharing_tab_premigration holds the old master-based commits.
# Called by: just bar::sharing-split <gen-manifest|build|verify> [--push] [--update-prs]
set -euo pipefail

DEVTOOLS_DIR="${DEVTOOLS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."; pwd)}"
BAR="${BAR_DIR:-${DEVTOOLS_DIR}/Beyond-All-Reason}"
SELF_DIR="${DEVTOOLS_DIR}/scripts/sharing-split"

TIP="${SHARING_TIP:-sharing_tab}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
# Migrated line the stack sits on: origin/fmt-llm until #8235 lands, then
# upstream/master + master (rebase after flipping). BASE is the ref we read;
# BASE_BRANCH is its upstream publish name (layer-1 + root PR base).
BASE="${SHARING_BASE:-upstream/fmt-llm}"
BASE_BRANCH="${SHARING_BASE_BRANCH:-fmt-llm}"
# Model for `describe` (generate + validate). Override if the id 404s.
DESC_MODEL="${SHARING_DESC_MODEL:-claude-opus-4-6}"

MANIFEST="${SELF_DIR}/manifest.tsv"   # <layer>\t<path>
LAYERS_CONF="${SELF_DIR}/layers.tsv"  # <layer>\t<staging-branch>\t<message>
PR_TARGETS="${SELF_DIR}/pr_targets.tsv"  # <layer>\t<real-branch>\t<base>\t<remote>\t<pr#>
FORK_OWNER="${FORK_OWNER:-$(git -C "$BAR" remote get-url origin 2>/dev/null | sed -n 's|.*[:/]\([^/]*\)/.*|\1|p')}"
STACK_NATIVE="${STACK_NATIVE:-8411}"  # native stacked-PR stack (the merge path)
STACK_ISSUE="${STACK_ISSUE:-8412}"    # feature tracking issue
STACK_FMT_PR="${STACK_FMT_PR:-8398}"  # type-migration capstone; merges before this stack

git_bar() { git -C "$BAR" -c submodule.recurse=false "$@"; }
step() { printf '\033[1;34m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*" >&2; }

layer_branch()  { awk -F'\t' -v l="$1" '$1==l{print $2}' "$LAYERS_CONF"; }
layer_message() { awk -F'\t' -v l="$1" '$1==l{print $3}' "$LAYERS_CONF"; }
layer_ids()     { cut -f1 "$LAYERS_CONF" | sort -n; }
files_for()     { awk -F'\t' -v l="$1" '$1==l{print $2}' "$MANIFEST"; }

# ── gen-manifest: derive file->layer from the existing stack ──────────────────
# Each file's home = the lowest-numbered layer whose commit touches it (earliest,
# most foundational placement), materialized in final TIP content. Single-layer
# files map to their only layer. Forward-dependency cases (final content imports
# a later-homed module) surface as per-layer spec failures in `verify` and get
# an explicit later home via OVERRIDES below.
# Files whose final content forward-depends on a later layer (a VFS.Include of a
# module homed later than the file's earliest touch). Pin them to a later layer
# so each PR stays self-contained. Discovered via `verify` failures; minimal.
# Also pins files introduced by post-stack fixup commits (earliest touch > layer
# count) to their logical home.
declare -A OVERRIDES=(
    [types/engine.lua]=1
    # post-stack fixup commits (I18N/EngineSynced/annotation cleanups) touched
    # these base-line files first; pin type stubs + test infra to foundations,
    # runtime shims to the transfer-runtime layer.
    [types/I18N.lua]=1
    [types/luassert/library/luassert.lua]=1
    [common/tablefunctions.lua]=1
    [spec/builders/sequence.lua]=1
    [spec/builders/unit_def_builder.lua]=1
    [spec/builders/unit_defs_builder.lua]=1
    [spec/builders/engine_unsynced_builder.lua]=1
    [spec/gamedata/unitdefs_spec.lua]=1
    [spec/luaui/Widgets/api_build_orders_spec.lua]=1
    [init.lua]=4
    [luarules/system.lua]=4
    [luaui/system.lua]=4
)

cmd_gen_manifest() {
    step "Deriving manifest from $BASE..$TIP"
    declare -A LBL; local i=0 c
    for c in $(git_bar rev-list --reverse "$BASE..$TIP"); do i=$((i+1)); LBL[$c]=$i; done
    : > "$MANIFEST"
    local f home chunks
    while read -r f; do
        [ -z "$f" ] && continue
        if [ -n "${OVERRIDES[$f]:-}" ]; then
            printf '%s\t%s\n' "${OVERRIDES[$f]}" "$f" >> "$MANIFEST"; continue
        fi
        chunks=""
        for c in $(git_bar log --format='%H' "$BASE..$TIP" -- "$f"); do chunks="$chunks ${LBL[$c]}"; done
        home=$(echo $chunks | tr ' ' '\n' | sort -un | head -1)
        if [ -z "$home" ]; then
            err "no layer home for $f — differs from $BASE but untouched by $BASE..$TIP"
            exit 1
        fi
        if [ -z "$(layer_branch "$home")" ]; then
            err "$f homes to commit #$home which has no layer (fixup commit?) — pin it in OVERRIDES"
            exit 1
        fi
        printf '%s\t%s\n' "$home" "$f" >> "$MANIFEST"
    done < <(git_bar diff --name-only --no-renames "$BASE" "$TIP")
    sort -n -o "$MANIFEST" "$MANIFEST"
    ok "Wrote $(wc -l < "$MANIFEST") entries to $MANIFEST"
    cmd_check_manifest
}

# ── check: manifest is a total, unique partition of the TIP diff ─────────────
cmd_check_manifest() {
    local diffset manifestset
    diffset=$(git_bar diff --name-only --no-renames "$BASE" "$TIP" | sort)
    manifestset=$(cut -f2 "$MANIFEST" | sort)
    local dup; dup=$(cut -f2 "$MANIFEST" | sort | uniq -d)
    [ -n "$dup" ] && { err "files assigned to >1 layer:"; echo "$dup"; exit 1; }
    if ! diff <(echo "$diffset") <(echo "$manifestset") >/dev/null; then
        err "manifest is not a total partition of $BASE..$TIP:"
        diff <(echo "$diffset") <(echo "$manifestset") | sed 's/^/  /'
        exit 1
    fi
    ok "manifest is a total, unique partition ($(wc -l < "$MANIFEST") files)"
}

# ── build: assemble the 7 commits, each materializing its layer's files ──────
cmd_build() {
    cmd_check_manifest
    step "Building stack on $BASE (final content from $TIP)"
    git_bar checkout --force -B _sharing_build "$BASE" >/dev/null 2>&1

    local l br msg f
    for l in $(layer_ids); do
        br=$(layer_branch "$l"); msg=$(layer_message "$l")
        while read -r f; do
            [ -z "$f" ] && continue
            if git_bar cat-file -e "$TIP:$f" 2>/dev/null; then
                git_bar checkout "$TIP" -- "$f"
            else
                git_bar rm -q --ignore-unmatch "$f" >/dev/null
            fi
        done < <(files_for "$l")
        # exclude the regen-volatile submodule; its gitlink comes from BASE/manifest, not the dirty worktree
        git_bar add -A -- . ':(exclude)recoil-lua-library'
        git_bar commit -q -m "$msg"
        git_bar branch -f "$br" HEAD
        ok "layer $l -> $br ($(git_bar rev-parse --short HEAD))"
    done
    git_bar checkout --force "$(layer_branch "$(layer_ids | tail -1)")" >/dev/null 2>&1
    git_bar branch -D _sharing_build >/dev/null 2>&1 || true
    cmd_verify
    # normalize: absorb fixup commits so $TIP stays exactly the N layer commits
    git_bar branch -f "$TIP" "$(layer_branch "$(layer_ids | tail -1)")"
    ok "$TIP normalized to the assembled stack ($(git_bar rev-parse --short "$TIP"))"
}

# ── verify: tip tree identical + each layer self-contained (busted) ──────────
cmd_verify() {
    local tip_branch; tip_branch=$(layer_branch "$(layer_ids | tail -1)")
    step "Verifying assembled tip == $TIP"
    if git_bar diff --quiet "$TIP" "$tip_branch"; then
        ok "assembled $tip_branch tree is byte-identical to $TIP"
    else
        err "assembled tip differs from $TIP:"; git_bar diff --stat "$TIP" "$tip_branch"; exit 1
    fi
    step "Per-layer busted (each PR must pass standalone)"
    local l br failed=""
    for l in $(layer_ids); do
        br=$(layer_branch "$l")
        git_bar checkout --force "$br" >/dev/null 2>&1
        # Retry once: the recoil-lua-library regen on the first run after a
        # checkout can flake. Only a genuine failure repeats.
        if (cd "$BAR" && lx --lua-version 5.1 test >/dev/null 2>&1) \
            || (cd "$BAR" && lx --lua-version 5.1 test >/dev/null 2>&1); then
            ok "layer $l ($br): specs pass"
        else
            err "layer $l ($br): specs FAIL — a file may be homed later than a layer that needs it"
            failed="$failed $l"
        fi
    done
    git_bar checkout --force "$tip_branch" >/dev/null 2>&1
    [ -n "$failed" ] && { err "layers with failing specs:$failed"; exit 1; } || ok "all layers pass standalone"
}


# ── step 0: fetch so $BASE is fresh before any subcommand ────────────────────
sync_base() {
    step "Fetching $UPSTREAM_REMOTE; base $BASE"
    git_bar fetch --no-recurse-submodules "$UPSTREAM_REMOTE"
    case "$BASE" in
        */*) [ "${BASE%%/*}" = "$UPSTREAM_REMOTE" ] || git_bar fetch --no-recurse-submodules "${BASE%%/*}" ;;
    esac
    git_bar rev-parse --verify "$BASE" >/dev/null 2>&1 || { err "$BASE not found"; exit 1; }
    local drift
    drift=$(git_bar rev-list --count "$(git_bar merge-base "$BASE" "$UPSTREAM_REMOTE/master")..$UPSTREAM_REMOTE/master")
    if [ "$drift" -gt 0 ]; then
        warn "$BASE's master snapshot is $drift commit(s) behind $UPSTREAM_REMOTE/master"
        warn "  the stack (and QA builds of $TIP) won't see them until fmt-mig-generate + rebase"
    fi
}

preflight() {
    [ -n "$(git_bar status --porcelain | grep -v recoil-lua-library)" ] && {
        err "BAR tree dirty — commit/stash first (sharing-split rewrites branches)"; exit 1; }
    return 0
}


# ── rebase: replay TIP's layer commits onto the freshly-synced $BASE ──────────
cmd_rebase() {
    # Anchor on the layer-1 commit by message: $TIP may carry fixup commits on
    # top of the N layers, so a fixed ~N undercounts and silently drops layer 1.
    local root n
    root=$(git_bar rev-list --fixed-strings --grep "$(layer_message 1)" -n1 "$TIP")
    [ -n "$root" ] || { err "layer-1 commit ('$(layer_message 1)') not found on $TIP"; exit 1; }
    n=$(git_bar rev-list --count "$root^..$TIP")
    git_bar checkout --force "$TIP" >/dev/null 2>&1
    step "Rebasing $TIP ($n commits) onto $BASE"
    # Leave the rebase IN PROGRESS on conflict (don't auto-abort): fix files,
    # `git -C <BAR> rebase --continue`, then re-run without 'rebase' — sync_base
    # re-points $BASE and gen-manifest re-derives the partition.
    if ! git_bar rebase --onto "$BASE" "$root^" "$TIP"; then
        err "Conflict rebasing $TIP onto $BASE. Resolve the conflicts in $BAR,"
        err "  then: git -C $BAR rebase --continue"
        err "  then re-run without 'rebase' (e.g. gen-manifest build verify push update-prs)."
        exit 1
    fi
    ok "$TIP rebased onto $BASE ($(git_bar rev-parse --short "$BASE"))"
    cmd_gen_manifest
}

# ── describe: per-layer machine summary + fact-validation of the human prose ──
# LLM-in-the-loop (the only non-deterministic step). Uses $DESC_MODEL and adopts
# the human description's ubiquitous language. Writes <key>.summary.md and
# <key>.validation.md next to the human <key>.md.
cmd_describe() {
    command -v claude >/dev/null 2>&1 || { err "claude CLI not on PATH"; exit 1; }
    local target="${1:-all}" l
    for l in $(layer_ids); do
        [ "$target" != "all" ] && [ "$target" != "$l" ] && continue
        local br key prev human diff out val
        br=$(layer_branch "$l"); key=$(basename "$br")
        [ "$l" -eq 1 ] && prev="$BASE" || prev=$(layer_branch $((l-1)))
        git_bar rev-parse --verify "$br" >/dev/null 2>&1 || { warn "layer $l ($br) not built — skipping"; continue; }
        diff=$(git_bar diff "$prev" "$br")
        human=$(cat "${SELF_DIR}/descriptions/${key}.md" 2>/dev/null || echo "(none authored yet)")
        step "describe layer $l ($br) via $DESC_MODEL"
        out=$(claude -p --model "$DESC_MODEL" <<EOF
You are generating and fact-checking the description for ONE pull request in a
stacked split of a Beyond All Reason feature. The human author maintains a
specific ubiquitous language (e.g. PolicyType, PolicyResult, behavior
controller, view model) — adopt THEIR vocabulary; do not invent synonyms.

PR layer $l: $(layer_message "$l")

=== PR DIFF (what a reviewer sees) ===
$diff

=== HUMAN-AUTHORED DESCRIPTION ===
$human

Output EXACTLY two sections, each beginning with its marker line alone:

===CLAUDE_DESCRIPTION===
A tight, scannable summary of what THIS PR introduces, in the human author's
ubiquitous language (reuse THEIR symbols; no synonyms, no filler, no restating
the human prose). Format as Markdown:

- A one-line bold lead stating what the PR does in a single clause.
- Then 2-5 bullets, each a concrete change: the type, function, view model, or
  module it introduces / moves / renames, and what that piece is now responsible
  for. Cite the real identifiers from the diff as inline code spans.
- If it is a pure move or rename with no behavior change, say so in one bullet.

Aim for a reviewer grasping the PR's shape in ~10 seconds. Neutral and specific;
renders above the human prose, so complement it rather than repeat it.

===VALIDATION===
ONLY factual errors in the human description vs the diff: wrong symbol names,
wrong file paths, references to functions/types absent from the diff, or claims
that contradict the code (e.g. calling an action a policy). Terse bullets with a
line ref. Write "none" if clean. Do NOT rewrite prose or critique style.
EOF
)
        printf '%s\n' "$out" | awk '/^===CLAUDE_DESCRIPTION===/{f=1;next}/^===VALIDATION===/{f=0}f' \
            > "${SELF_DIR}/descriptions/${key}.summary.md"
        val=$(printf '%s\n' "$out" | awk '/^===VALIDATION===/{f=1;next}f')
        printf '%s\n' "$val" > "${SELF_DIR}/descriptions/${key}.validation.md"
        ok "  summary -> descriptions/${key}.summary.md"
        if printf '%s' "$val" | grep -qiE '[a-z]' && ! printf '%s' "$val" | grep -qiE '^[[:space:]]*none\.?[[:space:]]*$'; then
            warn "  $key.md — validation flagged:"; printf '%s\n' "$val" | sed 's/^/    /'
        else
            ok "  $key.md — factually clean"
        fi
    done
}

# ── PR target accessors (pr_targets.tsv) ─────────────────────────────────────
pr_branch() { awk -F'\t' -v l="$1" '$1==l{print $2}' "$PR_TARGETS"; }
pr_base()   { awk -F'\t' -v l="$1" '$1==l{print $3}' "$PR_TARGETS"; }
pr_remote() { awk -F'\t' -v l="$1" '$1==l{print $4}' "$PR_TARGETS"; }
pr_num()    { awk -F'\t' -v l="$1" '$1==l{print $5}' "$PR_TARGETS"; }

# ── stacked_split: the bottom-up nav block, current layer bolded ──────────────
cmd_topology() {
    local cur="${1:-}" l n msg line
    echo "### 📚 The sharing stack — review bottom-up"
    echo ""
    local total; total=$(layer_ids | wc -l)
    for l in $(layer_ids); do
        n=$(pr_num "$l"); msg=$(layer_message "$l" | sed -E 's#^Sharing [0-9]+/[0-9]+: ##')
        line="${l}/${total} · ${msg} (#${n})"
        if [ "$l" = "$cur" ]; then echo "- **${line}** ← you are here"; else echo "- ${line}"; fi
    done
    echo ""
    echo "> [!NOTE]"
    echo "> Part of native stack #${STACK_NATIVE} (feature tracking: #${STACK_ISSUE}). Merges bottom-up through the GitHub stacked-PR UI once the type-migration stack (#${STACK_FMT_PR}) is in."
    echo ""
    echo "Each PR is file-partitioned: every file appears in exactly one PR in its final \`${TIP}\` form, so each PR's diff is byte-identical to that branch. Regenerated deterministically by \`just bar::sharing-split\`."
}

# ── pr_body: stacked_split + claude_description (summary) + human_description ──
cmd_pr_body() {
    local l="$1" key human summary
    key=$(basename "$(layer_branch "$l")")
    cmd_topology "$l"
    echo ""
    summary="${SELF_DIR}/descriptions/${key}.summary.md"
    if [ -s "$summary" ]; then echo "#### Summary (LLM-generated, ${DESC_MODEL})"; echo ""; cat "$summary"; echo ""; fi
    human="${SELF_DIR}/descriptions/${key}.md"
    if [ -s "$human" ]; then echo "-----"; echo ""; cat "$human"; fi
    return 0
}

# ── push: promote split/* content to the real branches, bottom-up ────────────
# Each real branch must exist on its PR head's remote AND on any remote where it
# is used as a base. force-with-lease against the live SHA, then ls-remote verify.
cmd_push() {
    declare -A NEED
    local l rb base remote
    for l in $(layer_ids); do
        rb=$(pr_branch "$l"); base=$(pr_base "$l"); remote=$(pr_remote "$l")
        NEED["$rb"]+="$remote "
        [ "$base" != "$BASE_BRANCH" ] && NEED["$base"]+="$remote "
    done
    git_bar fetch --no-recurse-submodules upstream origin >/dev/null 2>&1 || true
    # $BASE_BRANCH is layer 1's + the root PR's base; NEED skips it, so publish it here.
    local now base_old; base_old=$(git_bar ls-remote "$UPSTREAM_REMOTE" "refs/heads/$BASE_BRANCH" | awk '{print $1}')
    step "publish $BASE -> $UPSTREAM_REMOTE/$BASE_BRANCH ($(echo "${base_old:-new}" | cut -c1-10))"
    if [ -n "$base_old" ]; then
        git_bar push --force-with-lease="$BASE_BRANCH:$base_old" "$UPSTREAM_REMOTE" "$BASE:refs/heads/$BASE_BRANCH"
    else
        git_bar push "$UPSTREAM_REMOTE" "$BASE:refs/heads/$BASE_BRANCH"
    fi
    now=$(git_bar ls-remote "$UPSTREAM_REMOTE" "refs/heads/$BASE_BRANCH" | awk '{print $1}')
    [ "$now" = "$(git_bar rev-parse "$BASE")" ] && ok "  verified $UPSTREAM_REMOTE/$BASE_BRANCH" || { err "  DRIFT: $UPSTREAM_REMOTE/$BASE_BRANCH=$now"; exit 1; }
    # $TIP is the root PR's head — publish to origin
    local tip_old; tip_old=$(git_bar ls-remote origin "refs/heads/$TIP" | awk '{print $1}')
    step "push $TIP -> origin/$TIP ($(echo "${tip_old:-new}" | cut -c1-10))"
    if [ -n "$tip_old" ]; then
        git_bar push --force-with-lease="$TIP:$tip_old" origin "$TIP:refs/heads/$TIP"
    else
        git_bar push origin "$TIP:refs/heads/$TIP"
    fi
    now=$(git_bar ls-remote origin "refs/heads/$TIP" | awk '{print $1}')
    [ "$now" = "$(git_bar rev-parse "$TIP")" ] && ok "  verified origin/$TIP" || { err "  DRIFT: origin/$TIP=$now"; exit 1; }
    for l in $(layer_ids); do
        rb=$(pr_branch "$l"); local src; src=$(layer_branch "$l")
        local r; for r in $(echo "${NEED[$rb]}" | tr ' ' '\n' | sort -u | grep .); do
            local old; old=$(git_bar ls-remote "$r" "refs/heads/$rb" | awk '{print $1}')
            step "push $src -> $r/$rb ($(echo "${old:-new}" | cut -c1-10))"
            if [ -n "$old" ]; then
                git_bar push --force-with-lease="$rb:$old" "$r" "$src:refs/heads/$rb"
            else
                git_bar push "$r" "$src:refs/heads/$rb"
            fi
            local now; now=$(git_bar ls-remote "$r" "refs/heads/$rb" | awk '{print $1}')
            [ "$now" = "$(git_bar rev-parse "$src")" ] && ok "  verified $r/$rb" || { err "  DRIFT: $r/$rb=$now != $src"; exit 1; }
        done
    done
}

# ── update-prs: push composed bodies + set bases via gh ──────────────────────
# Native stacks reject --base edits (the stack owns the base) — send --base
# only when it needs to move.
edit_pr() {
    local n="$1" body="$2" base="$3" current
    current=$(gh pr view "$n" --repo beyond-all-reason/Beyond-All-Reason --json baseRefName -q .baseRefName)
    if [ "$current" = "$base" ]; then
        gh pr edit "$n" --repo beyond-all-reason/Beyond-All-Reason --body-file "$body"
    else
        gh pr edit "$n" --repo beyond-all-reason/Beyond-All-Reason --body-file "$body" --base "$base"
    fi
}

cmd_update_prs() {
    command -v gh >/dev/null 2>&1 || { err "gh not on PATH"; exit 1; }
    local l n base body failed=""
    for l in $(layer_ids); do
        n=$(pr_num "$l"); base=$(pr_base "$l")
        body="$BAR/.git/sharing-pr-${l}-body.md"
        cmd_pr_body "$l" > "$body"
        step "gh pr edit #$n (base $base)"
        # Resilient: a single gh failure (transient/cross-repo) must not abort the rest.
        if edit_pr "$n" "$body" "$base"; then
            ok "  #$n updated"
        else
            warn "  #$n FAILED — continuing"; failed="$failed $n"
        fi
    done
    [ -n "$failed" ] && { err "PRs not updated:$failed (re-run update-prs)"; exit 1; } || ok "all PRs updated"
}

usage() { err "usage: generate.sh <rebase|gen-manifest|check|build|verify|describe [layer]|pr-body <layer>|push|update-prs> ..."; exit 1; }
[ $# -eq 0 ] && usage

sync_base   # step 0: $BASE freshly fetched before any subcommand
preflight

# Run each subcommand in sequence (set -e stops on first failure), so the full
# pipeline chains: generate.sh build verify describe push update-prs
while [ $# -gt 0 ]; do
    cmd="$1"; shift
    case "$cmd" in
        gen-manifest)   cmd_gen_manifest ;;
        check)          cmd_check_manifest ;;
        rebase)         cmd_rebase ;;
        build)          cmd_build ;;
        verify)         cmd_verify ;;
        describe)
            if [ $# -gt 0 ] && printf '%s' "$1" | grep -qE '^[0-9]+$'; then cmd_describe "$1"; shift; else cmd_describe all; fi ;;
        pr-body)
            [ $# -gt 0 ] || usage
            cmd_pr_body "$1"; shift ;;
        push)           cmd_push ;;
        update-prs)     cmd_update_prs ;;
        *) err "unknown subcommand: $cmd"; usage ;;
    esac
done

#!/usr/bin/env bash
# Deterministically rebuild the 7-PR sharing stack by file partition.
# Each file is assigned to exactly one layer and materialized in its final
# (TIP) form, so every file in every PR is byte-identical to TIP.
# Called by: just bar::sharing-split <gen-manifest|build|verify> [--push] [--update-prs]
set -euo pipefail

DEVTOOLS_DIR="${DEVTOOLS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."; pwd)}"
BAR="${BAR_DIR:-${DEVTOOLS_DIR}/Beyond-All-Reason}"
SELF_DIR="${DEVTOOLS_DIR}/scripts/sharing-split"

BASE="${SHARING_BASE:-sharing_tab_mergeable}"
TIP="${SHARING_TIP:-sharing_tab}"

MANIFEST="${SELF_DIR}/manifest.tsv"   # <layer>\t<path>
LAYERS_CONF="${SELF_DIR}/layers.tsv"  # <layer>\t<branch>\t<message>

git_bar() { git -C "$BAR" -c submodule.recurse=false "$@"; }
step() { printf '\033[1;34m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; }

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
declare -A OVERRIDES=(
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
    [ -n "$(git_bar status --porcelain | grep -v recoil-lua-library)" ] && {
        err "BAR tree dirty — commit/stash first"; exit 1; }

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
        git_bar add -A
        git_bar commit -q -m "$msg"
        git_bar branch -f "$br" HEAD
        ok "layer $l -> $br ($(git_bar rev-parse --short HEAD))"
    done
    git_bar checkout --force "$(layer_branch "$(layer_ids | tail -1)")" >/dev/null 2>&1
    git_bar branch -D _sharing_build >/dev/null 2>&1 || true
    cmd_verify
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
    local l br
    for l in $(layer_ids); do
        br=$(layer_branch "$l")
        git_bar checkout --force "$br" >/dev/null 2>&1
        if (cd "$BAR" && lx --lua-version 5.1 test >/dev/null 2>&1); then
            ok "layer $l ($br): specs pass"
        else
            err "layer $l ($br): specs FAIL — a file may be homed later than a layer that needs it"
        fi
    done
    git_bar checkout --force "$tip_branch" >/dev/null 2>&1
}

case "${1:-}" in
    gen-manifest)   cmd_gen_manifest ;;
    check)          cmd_check_manifest ;;
    build)          cmd_build ;;
    verify)         cmd_verify ;;
    *) err "usage: generate.sh <gen-manifest|check|build|verify>"; exit 1 ;;
esac

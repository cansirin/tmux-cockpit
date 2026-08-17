#!/usr/bin/env bats
# Tests for the picker's candidate filters — cockpit_zoxide_keep (is this
# directory a plausible project at all?) and cockpit_prune_nested (which ONE
# member of a nest do we offer?). Pure functions, no tmux server needed.

setup() {
  . "${BATS_TEST_DIRNAME}/../scripts/lib.sh"
  HOME="/home/u"
}

# ── cockpit_zoxide_keep ───────────────────────────────────────────────────────

@test "keep: an ordinary project dir passes" {
  cockpit_zoxide_keep "/home/u/work/app"
}

@test "keep: a project whose name has spaces passes (not everything is a slug)" {
  cockpit_zoxide_keep "/home/u/Desktop/sofia - master"
}

@test "keep: a project that is NOT a git repo still passes" {
  # deliberate: coursework folders and scratch dirs are projects too, so the
  # filter must not quietly become "must contain .git"
  cockpit_zoxide_keep "/home/u/Desktop/notes"
}

@test "keep: \$HOME itself is rejected" {
  ! cockpit_zoxide_keep "/home/u"
}

@test "keep: a trailing slash does not smuggle \$HOME through" {
  ! cockpit_zoxide_keep "/home/u/"
}

@test "keep: anything above \$HOME is rejected" {
  ! cockpit_zoxide_keep "/home"
  ! cockpit_zoxide_keep "/"
}

@test "keep: a dot-prefixed component is rejected at any depth" {
  ! cockpit_zoxide_keep "/home/u/.config"
  ! cockpit_zoxide_keep "/home/u/.claude/skills"
  ! cockpit_zoxide_keep "/home/u/work/.git"
}

@test "keep: a dot INSIDE a name is fine — only a leading dot means hidden" {
  cockpit_zoxide_keep "/home/u/code/github.com"
  cockpit_zoxide_keep "/home/u/work/v1.2-release"
}

# ── cockpit_prune_nested ──────────────────────────────────────────────────────

# tab-separated "<tag>\t<path>" lines, the shape sessionizer feeds in
tagged() { printf '%b\n' "$@"; }

@test "prune: a nest collapses to its first-seen member" {
  run tagged 'z\t/home/u/Desktop/sofia' 'z\t/home/u/Desktop/sofia/ml/hw-4' 'z\t/home/u/Desktop/sofia/ml'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [ "$result" = "/home/u/Desktop/sofia" ]
}

@test "prune: an ancestor is never dropped for arriving late" {
  # ~/Desktop/sofia scores 58.9 and ~/Desktop scores 1.3, so sofia comes first.
  # Both survive: sofia is what you wanted, and ~/Desktop is merely ranked low,
  # which fzf already handles. Dropping ancestors is what let a container eat the
  # projects inside it.
  run tagged 'z\t/home/u/Desktop/sofia' 'z\t/home/u/Desktop'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [ "$(printf '%s\n' "$result" | head -1)" = "/home/u/Desktop/sofia" ]
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "prune: a configured root child does NOT suppress a project beneath it" {
  # regression: `find` lists ~/code/github.com as a root child, which is a
  # mechanical listing and not a claim that github.com is the project. If it
  # suppressed, github.com/owner/repo (a ghq layout) would be unreachable —
  # exactly the config bug the zoxide source exists to kill.
  run tagged 'e\t/home/u/code/github.com' 'z\t/home/u/code/github.com/owner/repo'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [[ "$result" == *"/home/u/code/github.com/owner/repo"* ]]
}

@test "prune: KNOWN LIMIT — a container you visit more than its projects wins" {
  # Not a bug we can see from here: ~/w outranking ~/w/api and ~/w/web is
  # indistinguishable from sofia outranking its own subfolders. Asserted so the
  # behaviour is known and tested rather than a surprise. The fix is to name the
  # container in @cockpit-paths, which makes its children `e` — see the test
  # above, nothing can suppress those.
  run tagged 'z\t/home/u/w' 'z\t/home/u/w/api' 'z\t/home/u/w/web'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [ "$result" = "/home/u/w" ]
}

@test "prune: a configured (e) path is never dropped, even nested under another" {
  run tagged 'e\t/home/u/work/monorepo' 'e\t/home/u/work/monorepo/services'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 2 ]
  [[ "$result" == *"/home/u/work/monorepo/services"* ]]
}

@test "prune: a configured path is not shadowed by a zoxide ancestor" {
  run tagged 'e\t/home/u/work/app' 'z\t/home/u/work'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [ "$(printf '%s\n' "$result" | head -1)" = "/home/u/work/app" ]
}

@test "prune: a tab-less line cannot empty the candidate list" {
  # an empty path stored as a suppressor makes inside() true for every absolute
  # path, silently truncating everything after it
  run tagged 'no-tab-line' 'e\t/a/b' 'z\t/c/d'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [[ "$result" == *"/a/b"* ]]
  [[ "$result" == *"/c/d"* ]]
  [[ "$result" != *"no-tab-line"* ]]
}

@test "prune: a trailing slash is normalized, not treated as a second path" {
  # @cockpit-extra "~/work/app/" and a zoxide "/w/app" are the same directory;
  # without normalizing, the picker shows both and neither can suppress the other
  run tagged 'e\t/w/app/' 'z\t/w/app/src' 'z\t/w/app'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [ "$(printf '%s\n' "$result" | grep -cx '/w/app')" -eq 1 ]   # the clean form, once
  [ "$(printf '%s\n' "$result" | grep -cx '/w/app/')" -eq 0 ]  # no slashed duplicate
}

@test "prune: the same path from both sources appears once" {
  run tagged 'e\t/home/u/work/app' 'z\t/home/u/work/app'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [ "$result" = "/home/u/work/app" ]
}

@test "prune: sibling projects are untouched — only nesting collapses" {
  run tagged 'z\t/home/u/work/api' 'z\t/home/u/work/web' 'z\t/home/u/work/cli'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 3 ]
}

@test "prune: a shared name PREFIX is not nesting (app vs app-legacy)" {
  # index(p, keep "/") and not a bare prefix test — "/w/app-legacy" must survive
  # alongside "/w/app", or the picker silently eats a real project
  run tagged 'z\t/home/u/work/app' 'z\t/home/u/work/app-legacy'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 2 ]
  [[ "$result" == *"app-legacy"* ]]
}

@test "prune: a path with spaces survives the tab-delimited round trip" {
  run tagged 'z\t/home/u/Desktop/sofia - master' 'z\t/home/u/Desktop/sofia - master/ml'
  result="$(printf '%s\n' "$output" | cockpit_prune_nested)"
  [ "$result" = "/home/u/Desktop/sofia - master" ]
}

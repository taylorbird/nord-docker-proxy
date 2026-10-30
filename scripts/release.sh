#!/bin/zsh -f
# Cut a release:  scripts/release.sh <version>   (e.g. 0.1.1)
#
#   1. Preflight: on main, clean tree, tag free, notary profile reachable.
#   2. Write VERSION, commit "Release v<version>", tag v<version>.
#   3. Build + sign (scripts/build-app.sh), notarize, staple, zip.
#   4. Push main + tag; GitHub release with the zip.
#   5. Bump version + sha256 in the tap's cask (taylorbird/homebrew-nord-docker-proxy).
#
# Takes several minutes (notarization). Run it from a terminal.
set -euo pipefail
ROOT=${0:A:h:h}
REPO=taylorbird/nord-docker-proxy
TAP_REPO=taylorbird/homebrew-nord-docker-proxy
TAP_CASK=Casks/nord-docker-proxy.rb
NOTARY_PROFILE=${NDP_NOTARY_PROFILE:-notary}
V=${1:?usage: scripts/release.sh <version>   (e.g. 0.1.1)}

die() { print -u2 -r -- "release: $*"; exit 1 }

[[ "$V" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "version must look like 1.2.3, got \"$V\""
[[ "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)" == main ]] || die "releases are cut from main"
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || die "working tree has uncommitted changes"
git -C "$ROOT" rev-parse -q --verify "refs/tags/v$V" >/dev/null && die "tag v$V already exists"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notarytool profile \"$NOTARY_PROFILE\" missing, or Apple unreachable"
# Pin gh to the personal account; the active gh account can drift between
# work and personal mid-run.
GH_TOKEN="$(gh auth token --user taylorbird)" || die "gh is not logged in as taylorbird"
export GH_TOKEN

print -r -- "$V" > "$ROOT/VERSION"
git -C "$ROOT" add VERSION
git -C "$ROOT" commit -q -m "Release v$V"
git -C "$ROOT" tag "v$V"
print "==> Committed and tagged v$V (local)"

PUSHED=0
on_error() {
  if (( PUSHED )); then
    print -u2 "release: failed after pushing v$V; finish the GitHub release / cask bump by hand."
  else
    print -u2 "release: failed before pushing. To retry: git tag -d v$V && git reset --hard HEAD~1"
  fi
}
trap on_error ZERR

print "==> Building"
"$ROOT/scripts/build-app.sh"
APP="$ROOT/build/Nord Docker Proxy.app"
mkdir -p "$ROOT/dist"
ZIP="$ROOT/dist/nord-docker-proxy-$V.zip"

print "==> Notarizing"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
# Re-zip so the shipped archive carries the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute "$APP" || die "Gatekeeper rejects the stapled app"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

print "==> Publishing"
git -C "$ROOT" push --atomic origin main "v$V"
PUSHED=1
gh release create "v$V" "$ZIP" --repo "$REPO" --title "Nord Docker Proxy $V" \
  --notes "Install: brew install --cask taylorbird/nord-docker-proxy/nord-docker-proxy" --latest

print "==> Bumping the cask"
CASK_JSON=$(gh api "repos/$TAP_REPO/contents/$TAP_CASK")
CASK=$(jq -r .content <<<"$CASK_JSON" | base64 -d \
  | sed -E "s/^  version \"[^\"]*\"/  version \"$V\"/; s/^  sha256 \"[^\"]*\"/  sha256 \"$SHA\"/")
grep -qF "version \"$V\"" <<<"$CASK" && grep -qF "sha256 \"$SHA\"" <<<"$CASK" || die "cask rewrite failed"
jq -n --arg message "nord-docker-proxy $V" --arg content "$(base64 <<<"$CASK")" \
  --arg sha "$(jq -r .sha <<<"$CASK_JSON")" '{message: $message, content: $content, sha: $sha}' \
  | gh api -X PUT "repos/$TAP_REPO/contents/$TAP_CASK" --input - >/dev/null
trap - ZERR
print "==> Released v$V (sha256 $SHA)"
print "    https://github.com/$REPO/releases/tag/v$V"

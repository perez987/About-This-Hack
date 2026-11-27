#!/bin/zsh
# Publishes the DMG that release.sh built:
#   1. a GitHub Release (tag and title <version>, e.g. 5.1.5, no "v" as in earlier releases) in
#      perez987/About-This-Hack holding About.This.Hack.<version>.dmg (and, if it is also in
#      Distribute/, the translucent-window variant About.This.Hack-glass.<version>.dmg)
#   2. the Sparkle update feed (appcast-6.xml at the repository root, on main) pointing at
#      About.This.Hack.<version>.dmg. This is the feed SUFeedURL in Info.plist reads.
#
# Usage (from anywhere), one change per line:
#   RELEASE_NOTES=$'First change\nSecond change' ./Scripts/publish.sh
# The notes are listed on the GitHub Release and added at the top of the appcast-6.xml
# description as "What's New in About This Hack <version>" (any earlier history in the
# description is kept). HTML such as <i>…</i> is allowed.
#
# Needs: release.sh run first; `gh` installed and signed in (gh auth login); the Sparkle EdDSA
# private key in the login keychain (the one matching SUPublicEDKey in Info.plist). Sparkle's
# generate_keys stores it under the account "ed25519" unless --account was used; if you used
# another account, run with SPARKLE_ACCOUNT=<name>.

# This script uses zsh syntax: if started with sh/bash, run it again under zsh.
[ -n "${ZSH_VERSION:-}" ] || exec /bin/zsh "$0" "$@"

set -euo pipefail

SCRIPT_DIR="${0:A:h}"                 # .../About-This-Hack/Scripts
REPO_ROOT="${SCRIPT_DIR:h}"           # .../About-This-Hack (repository root, where appcast-6.xml lives)
XCODE_DIR="$REPO_ROOT/Xcode-project"  # where "About This Hack.xcodeproj" lives
SCHEME="About This Hack"
APP="About This Hack"
ASSET_BASE="About.This.Hack"
GLASS_BASE="About.This.Hack-glass"    # optional translucent-window DMG, uploaded if present
PROJECT="$XCODE_DIR/$SCHEME.xcodeproj"
REPO=perez987/About-This-Hack
BRANCH=main                           # SUFeedURL reads appcast-6.xml from this branch
FEED=appcast-6.xml
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-ed25519}"
WORK="$HOME/Library/Caches/AboutThisHackRelease"
APPCAST="$REPO_ROOT/$FEED"

# --- Checks ---------------------------------------------------------------------------------
command -v gh >/dev/null || { echo "gh is missing: brew install gh && gh auth login"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh isn't signed in: gh auth login"; exit 1; }

SIGN_UPDATE="$WORK/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -x "$SIGN_UPDATE" ]] || { echo "Sparkle's sign_update isn't there — run release.sh first."; exit 1; }

[[ -f "$APPCAST" ]] || { echo "No $APPCAST"; exit 1; }
current_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
[[ "$current_branch" == "$BRANCH" ]] || { echo "Switch to $BRANCH first (now on $current_branch)."; exit 1; }
git -C "$REPO_ROOT" diff --quiet -- "$FEED" \
  || { echo "$FEED has uncommitted changes; commit or discard them first."; exit 1; }

# Reads a build setting of the app target only (the scheme also lists the test target).
# xcodebuild quotes target names with spaces: Build settings for action build and target "About This Hack":
setting() {
  print -r -- "$settings" | awk -F' = ' -v key="$1" -v target="$SCHEME" '
    { sub(/\r$/, "") }
    /^Build settings for action / {
      name = $0; sub(/.* and target /, "", name); sub(/:[ \t]*$/, "", name); gsub(/"/, "", name)
      inapp = (name == target); next
    }
    inapp { k = $1; gsub(/^[ \t]+|[ \t]+$/, "", k); if (k == key) { print $2; exit } }'
}

settings=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>&1) \
  || { print -r -- "$settings"; echo "xcodebuild -showBuildSettings failed"; exit 1; }
VERSION=$(setting MARKETING_VERSION)
BUILD=$(setting CURRENT_PROJECT_VERSION)
MINIMUM=$(setting MACOSX_DEPLOYMENT_TARGET)
[[ -n "$VERSION" && -n "$BUILD" && -n "$MINIMUM" ]] || { print -r -- "$settings" | grep -E "^Build settings for action|MARKETING_VERSION|CURRENT_PROJECT_VERSION" | head -10
     echo "Couldn't read the version from $PROJECT"; exit 1; }
TAG="$VERSION"
ASSET="$ASSET_BASE.$VERSION.dmg"
DMG="$REPO_ROOT/Distribute/$ASSET"
GLASS_DMG="$REPO_ROOT/Distribute/$GLASS_BASE.$VERSION.dmg"

[[ -f "$DMG" ]] || { echo "No $DMG — run release.sh first."; exit 1; }
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Raise the version (and build number) first."
  exit 1
fi

assets=("$DMG")
[[ -f "$GLASS_DMG" ]] && assets+=("$GLASS_DMG")

# --- Release notes --------------------------------------------------------------------------
[[ "${RELEASE_NOTES:-}" != *']]>'* ]] || { echo "The release notes can't contain ]]>."; exit 1; }
changes=("${(@f)${RELEASE_NOTES:-}}")
changes=(${changes:#})                       # drop empty lines
# Every version in appcast-6.xml gets its own "What's New" list, so notes are required.
(( ${#changes} )) || { echo "Set RELEASE_NOTES, e.g. RELEASE_NOTES=\$'First change\\nSecond change' $0"; exit 1; }
notes=$(printf -- '- %s\n' "${changes[@]}")

echo "==> $APP $VERSION ($BUILD) → $REPO $TAG"

# --- Sparkle signature ----------------------------------------------------------------------
echo "==> Signing the update for Sparkle (keychain account: $SPARKLE_ACCOUNT)"
# Prints: sparkle:edSignature="…" length="…"
signature=$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$DMG")
[[ "$signature" == *edSignature=* && "$signature" == *length=* ]] || { echo "sign_update failed: $signature"; exit 1; }

# --- GitHub Release -------------------------------------------------------------------------
echo "==> Creating GitHub Release $TAG with: ${assets[*]:t}"
gh release create "$TAG" "${assets[@]}" --repo "$REPO" --target "$BRANCH" \
  --title "$VERSION" --notes "$notes"

# --- Update feed ----------------------------------------------------------------------------
echo "==> Updating $FEED"
APPCAST="$APPCAST" APPNAME="$APP" VERSION="$VERSION" BUILD="$BUILD" MINIMUM="$MINIMUM" \
SIGNATURE="$signature" PUBDATE="$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")" \
URL="https://github.com/$REPO/releases/download/$TAG/$ASSET" \
CHANGES="${(pj:\n:)changes}" \
/usr/bin/python3 - <<'PY'
import os, re, sys

e = os.environ
path = e["APPCAST"]
feed = os.path.basename(path)
with open(path, encoding="utf-8") as f:
    xml = f.read()

start = xml.find("<item>")
end = xml.find("</item>", start)
if start < 0 or end < 0:
    sys.exit(f"{feed}: no <item> found")
item = xml[start:end]

def replace(pattern, new):
    global item
    item, n = re.subn(pattern, lambda m: new, item, count=1, flags=re.S)
    if n != 1:
        sys.exit(f"{feed}: {pattern!r} not found in <item>")

name, v = e["APPNAME"], e["VERSION"]
sig = re.search(r'sparkle:edSignature="([^"]+)"', e["SIGNATURE"])
length = re.search(r'length="(\d+)"', e["SIGNATURE"])
if not sig or not length:
    sys.exit("sign_update output not understood: " + e["SIGNATURE"])

replace(r"<title>.*?</title>", f"<title>Version {v}</title>")
replace(r"<pubDate>.*?</pubDate>", f"<pubDate>{e['PUBDATE']}</pubDate>")
replace(r"<sparkle:version>.*?</sparkle:version>", f"<sparkle:version>{e['BUILD']}</sparkle:version>")
replace(r"<sparkle:shortVersionString>.*?</sparkle:shortVersionString>",
        f"<sparkle:shortVersionString>{v}</sparkle:shortVersionString>")
replace(r"<sparkle:minimumSystemVersion>.*?</sparkle:minimumSystemVersion>",
        f"<sparkle:minimumSystemVersion>{e['MINIMUM']}</sparkle:minimumSystemVersion>")
replace(r"<enclosure\b.*?/>",
        "<enclosure\n"
        f"                url=\"{e['URL']}\"\n"
        f"                length=\"{length.group(1)}\"\n"
        f"                sparkle:edSignature=\"{sig.group(1)}\"\n"
        "                type=\"application/octet-stream\"\n"
        "            />")

changes = [c.strip() for c in e.get("CHANGES", "").split("\n") if c.strip()]
block = (f"\n\t\t\t\t<h3>What's New in {name} {v}</h3>\n\t\t\t\t<ul>\n"
         + "".join(f"\t\t\t\t\t<li>{c}</li>\n" for c in changes)
         + "\t\t\t\t</ul>")
# Add on top of an existing CDATA history, or turn an empty/plain <description> into one.
item, n = re.subn(r"(<description[^>]*><!\[CDATA\[)", lambda m: m.group(1) + block, item, count=1)
if n != 1:
    item, n = re.subn(r"<description\b[^>]*?(?:/>|>.*?</description>)",
                      lambda m: f'<description xml:lang="en"><![CDATA[{block}\n\t\t\t]]></description>',
                      item, count=1, flags=re.S)
if n != 1:
    sys.exit(f"{feed}: no <description> found in <item>")

with open(path, "w", encoding="utf-8") as f:
    f.write(xml[:start] + item + xml[end:])
PY

git -C "$REPO_ROOT" add "$FEED"
git -C "$REPO_ROOT" commit -q -m "Publish update feed for $APP $VERSION"
git -C "$REPO_ROOT" push -q origin "$BRANCH"
echo "==> Done: https://github.com/$REPO/releases/tag/$TAG"
[[ -f "$GLASS_DMG" ]] || echo "    No $GLASS_BASE.$VERSION.dmg in Distribute/: upload it later with gh release upload $TAG <dmg> --repo $REPO"
echo "    Remember to add the changes to Releases-changelog.md."

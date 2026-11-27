#!/usr/bin/env bash
# One command to release: checks -> build APK -> deploy backend + website -> git commit + tag + push -> GitHub release -> phones are offered the update.
#
#   tool/release.sh "What changed"            normal release (patch version +1, build number +1)
#   tool/release.sh "What changed" --min      also makes it mandatory (phones below this build must update)
#   tool/release.sh "What changed" --dry-run  runs the checks and shows the plan; changes nothing
#
# Must run on THIS Mac: releases are signed with this Mac's key, and Android only updates an app signed with the same key (docs/RELEASING.md).
set -euo pipefail
cd "$(dirname "$0")/.."

MSG="${1:-}"; shift || true
MIN=""; DRY=""
for a in "$@"; do case "$a" in --min) MIN="--min";; --dry-run) DRY=1;; *) echo "Unknown option $a"; exit 2;; esac; done
[ -n "$MSG" ] || { echo 'Usage: tool/release.sh "What changed" [--min] [--dry-run]'; exit 2; }
RELEASES_REPO="SaiVardhan2007/folk-releases"   # small PUBLIC repo that holds only the APK files
run() { if [ -n "$DRY" ]; then echo "[dry-run] $*"; else "$@"; fi; }

command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || { echo "Sign in to GitHub first: gh auth login"; exit 1; }
[ "$(git branch --show-current)" = "main" ] || { echo "Release from the main branch."; exit 1; }
[ -f backend/.dev.vars ] || { echo "backend/.dev.vars is missing."; exit 1; }

# 1. Next version
CUR=$(sed -n 's/^version: *//p' pubspec.yaml); NAME=${CUR%+*}; BUILD=${CUR#*+}
IFS=. read -r MA MI PA <<<"$NAME"
NEW_NAME="$MA.$MI.$((PA+1))"; NEW_BUILD=$((BUILD+1)); TAG="v$NEW_NAME"
echo "== Releasing $TAG (build $NEW_BUILD) from $CUR"
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "Tag $TAG already exists."; exit 1; }

# 2. Checks: nothing broken is ever released
flutter analyze
flutter test
(cd backend && npx tsc --noEmit)

# 3. New database scripts since the last release must already be run (an unapplied one makes endpoints fail)
LAST=$(git describe --tags --abbrev=0 2>/dev/null || true)
NEWPHASE=$( { [ -n "$LAST" ] && git diff --name-only "$LAST" -- 'backend/scripts/phase*.py'; git ls-files --others --exclude-standard 'backend/scripts/phase*.py'; } 2>/dev/null | sort -u || true)
if [ -n "$NEWPHASE" ]; then
  echo "New or changed database scripts since ${LAST:-the start}:"; echo "$NEWPHASE" | sed 's/^/   /'
  [ -n "$DRY" ] || { read -r -p "Have these been run with --commit? (y/N) " ok; [ "$ok" = y ] || { echo "Run them first (python3 -I scripts/<name>.py --commit from backend/)."; exit 1; }; }
fi

# 4. Build first, so a failed build changes nothing
run sed -i '' "s/^version: .*/version: $NEW_NAME+$NEW_BUILD/" pubspec.yaml
run flutter build apk --release --target-platform android-arm64
APK=build/app/outputs/flutter-apk/app-release.apk

# 5. Backend, then the website (same code as the app; index.html is never cached, so browsers load the new release on the next visit)
run bash -c 'cd backend && npx wrangler deploy'
run flutter build web --release
run backend/node_modules/.bin/wrangler pages deploy build/web --project-name folk-web --branch main --commit-dirty=true

# 6. Git: commit everything, tag, push
run git add -A
run git commit -m "Release $NEW_NAME (build $NEW_BUILD): $MSG

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
run git tag "$TAG"
run git push "$(git config branch.main.remote)" main "$TAG"   # the remote main tracks (devshare)

# 7. GitHub release with a fixed file name, so the download link never changes
run gh release create "$TAG" "$APK#FOLK-Tracker.apk" --repo "$RELEASES_REPO" --title "FOLK Tracker $NEW_NAME" --notes "$MSG"

# 8. Last: tell the phones. They see "Update available" when the app next opens or returns to the foreground.
run bash -c "cd backend && python3 -I scripts/publish_update.py $NEW_BUILD \"\$0\" $MIN" "$MSG"
echo "== Done: $TAG is out."

#!/bin/bash
# Publishes a release that `make release` packed (make publish): tags v<version>, pushes the branch
# and the tag, creates the GitHub release with the zip, the DMG and docs/releases/v<version>.md as
# notes, then points the cask in the Homebrew tap at the new zip. Installed copies find the release
# themselves (Updater.swift), so the cask says auto_updates.
set -euo pipefail

version="$1"
dist="$2"
repo="OlehFostyak/Lad"
tap="OlehFostyak/homebrew-tap"
root="$(cd "$(dirname "$0")/.." && pwd)"
zip="$dist/Lad-$version.zip"
dmg="$dist/Lad-$version.dmg"
notes="$root/docs/releases/v$version.md"

fail() {
  echo "error: $*" >&2
  exit 1
}

[ -f "$zip" ] && [ -f "$dmg" ] || fail "$zip or $dmg is missing: run make release first"
[ -f "$notes" ] || fail "$notes is missing: write the release notes first"
[ -z "$(git -C "$root" status --porcelain)" ] || fail "the working tree has uncommitted changes"
if gh release view "v$version" --repo "$repo" >/dev/null 2>&1; then
  fail "release v$version already exists"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The zip must hold this version, signed with Lad's certificate: friends' Accessibility grants
# follow it, and an ad hoc build would lose them on the update.
ditto -x -k "$zip" "$work/app"
built="$(plutil -extract CFBundleShortVersionString raw "$work/app/Lad.app/Contents/Info.plist")"
[ "$built" = "$version" ] || fail "$zip holds Lad $built, not $version"
codesign --verify --deep --strict "$work/app/Lad.app"
codesign -d -r- "$work/app/Lad.app" 2>&1 | grep -q 'certificate' || fail "$zip is not signed with Lad's certificate"

head="$(git -C "$root" rev-parse HEAD)"
if tagged="$(git -C "$root" rev-parse -q --verify "refs/tags/v$version^{commit}")"; then
  [ "$tagged" = "$head" ] || fail "tag v$version points at another commit"
else
  git -C "$root" tag -a "v$version" -m "Lad $version"
fi
git -C "$root" push --quiet origin HEAD "v$version"
gh release create "v$version" "$zip" "$dmg" --repo "$repo" --title "Lad $version" --notes-file "$notes"

sha="$(shasum -a 256 "$zip" | awk '{ print $1 }')"
gh repo clone "$tap" "$work/tap" -- --quiet --depth 1
mkdir -p "$work/tap/Casks"
cat > "$work/tap/Casks/lad.rb" <<CASK
cask "lad" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/$repo/releases/download/v#{version}/Lad-#{version}.zip"
  name "Lad"
  desc "Keyboard layout switcher for Ukrainian and English that keeps what you type local"
  homepage "https://github.com/$repo"

  auto_updates true
  depends_on macos: ">= :tahoe"

  app "Lad.app"

  zap trash: "~/Library/Preferences/dev.oleh.lad.plist"

  caveats <<~EOS
    Lad не нотаризований Apple, тож перший запуск macOS заблокує:
    System Settings → Privacy & Security → «Open Anyway» біля Lad.
    Далі Lad попросить доступ Accessibility: увімкни Lad у списку.
    Оновлення: brew upgrade --cask lad
  EOS
end
CASK
# The tap's commits carry the same author as Lad's.
git -C "$work/tap" add Casks/lad.rb
git -C "$work/tap" -c user.name="$(git -C "$root" config user.name)" -c user.email="$(git -C "$root" config user.email)" \
  commit --quiet -m "lad $version"
git -C "$work/tap" push --quiet
echo "Published Lad $version: https://github.com/$repo/releases/tag/v$version"
echo "Friends install it with: brew install --cask olehfostyak/tap/lad"

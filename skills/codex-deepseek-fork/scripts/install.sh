#!/bin/bash
# Fork the Codex desktop app into a second, independent app (default name "DeepSeek")
# with its own name/icon in the Dock, its own CODEX_HOME, configured from a CC Switch
# Codex provider. The original Codex app and ~/.codex are not modified.
#
# How: APFS-clone the Codex app bundle (near-zero disk), rename it in Info.plist, launch
# it through a wrapper that sets its own CODEX_HOME / user data and turns off Sparkle
# auto-update, then ad-hoc re-sign.
#
# Usage: install.sh [--name DeepSeek] [--provider DeepSeek]
# Env overrides: CODEX_APP=/path/to/Codex.app  INSTALL_DIR=/Applications
# Re-run after the Codex app updates to rebuild the fork from the new version.
set -euo pipefail

APP_NAME="DeepSeek"
PROVIDER_NAME="DeepSeek"
while [ $# -gt 0 ]; do
  case "$1" in
    --name) APP_NAME="$2"; shift 2 ;;
    --provider) PROVIDER_NAME="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SLUG="$(echo "$APP_NAME" | tr '[:upper:] ' '[:lower:]-')"
FORK_BUNDLE_ID="local.codex-fork.$SLUG"
FORK_CODEX_HOME="$HOME/.codex-$SLUG"
FORK_USER_DATA="$HOME/Library/Application Support/Codex ($APP_NAME)"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
FORK_APP="$INSTALL_DIR/$APP_NAME.app"

# 1. Find the Codex desktop app (bundle id com.openai.codex; may be named Codex.app or ChatGPT.app).
if [ -z "${CODEX_APP:-}" ]; then
  CODEX_APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.openai.codex'" | grep '^/Applications/' | head -1 || true)"
fi
if [ -z "$CODEX_APP" ] || [ ! -d "$CODEX_APP" ]; then
  echo "Codex desktop app not found. Install it, or pass CODEX_APP=/path/to/Codex.app" >&2
  exit 1
fi
echo "Codex app: $CODEX_APP"

# 2. Separate CODEX_HOME, configured from the CC Switch provider.
mkdir -p -m 700 "$FORK_CODEX_HOME" "$FORK_USER_DATA"
python3 "$SKILL_DIR/scripts/sync_config.py" --provider "$PROVIDER_NAME" --target "$FORK_CODEX_HOME"

# Share instructions/skills with the main Codex so both behave the same; history stays separate.
for shared_entry in AGENTS.md skills prompts agents rules; do
  source_path="$HOME/.codex/$shared_entry"
  [ -e "$source_path" ] || continue
  [ -e "$FORK_CODEX_HOME/$shared_entry" ] || [ -L "$FORK_CODEX_HOME/$shared_entry" ] && continue
  if [ -L "$source_path" ]; then source_path="$(readlink "$source_path")"; fi
  ln -s "$source_path" "$FORK_CODEX_HOME/$shared_entry"
  echo "  linked $shared_entry -> $source_path"
done

# 3. Quit a running fork, then rebuild the bundle from a fresh clone.
pkill -f -- "^$FORK_APP/Contents/MacOS/" 2>/dev/null && sleep 3 || true
pkill -f -- "--user-data-dir=$(printf '%s' "$FORK_USER_DATA" | sed 's/[()]/\\&/g')" 2>/dev/null && sleep 3 || true
rm -f "$FORK_USER_DATA"/Singleton{Lock,Cookie,Socket}   # stale lock from a killed instance
rm -rf "$FORK_APP"
cp -cR "$CODEX_APP" "$FORK_APP"   # APFS clone: shares disk blocks with the original
echo "Cloned to $FORK_APP"

PLIST="$FORK_APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" >/dev/null 2>&1 || true; }
plist "Set :CFBundleName $APP_NAME"
plist "Set :CFBundleDisplayName $APP_NAME"
plist "Set :CFBundleIdentifier $FORK_BUNDLE_ID"
# Don't compete with the original for its alternate name, URL schemes, file types or exported UTIs.
plist "Delete :CFBundleAlternateNames"
plist "Delete :CFBundleURLTypes"
plist "Delete :CFBundleDocumentTypes"
plist "Delete :UTExportedTypeDeclarations"
plist "Delete :LSHasLocalizedDisplayName"
# Main executable becomes a small wrapper: it sets a separate CODEX_HOME and Electron user data
# (which also disables the single-instance lock), passes --user-data-dir (otherwise Chromium hands
# the launch off to the running original), and turns off Sparkle, which would otherwise install the
# official build over the fork and rename it back. --use-mock-keychain: the re-signed fork would
# otherwise prompt for the original app's "Codex Storage Key" keychain item on every launch.
# exec keeps the pid, so the Dock tile is this app.
ORIGINAL_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$PLIST")"
cat > "$FORK_APP/Contents/MacOS/codex-fork-launcher" <<LAUNCHER
#!/bin/bash
export CODEX_HOME="$FORK_CODEX_HOME"
export CODEX_ELECTRON_USER_DATA_PATH="$FORK_USER_DATA"
export CODEX_SPARKLE_ENABLED=false
exec "\$(dirname "\$0")/$ORIGINAL_EXECUTABLE" --user-data-dir="\$CODEX_ELECTRON_USER_DATA_PATH" --use-mock-keychain "\$@"
LAUNCHER
chmod +x "$FORK_APP/Contents/MacOS/codex-fork-launcher"
plist "Set :CFBundleExecutable codex-fork-launcher"

# Icon: for DeepSeek, build it from the official logo (downloaded now); otherwise, or if that
# fails, use assets/<Name>.icns if present. The asset-catalog icon is dropped so the .icns wins.
FORK_ICNS="$FORK_APP/Contents/Resources/$APP_NAME.icns"
if [ "$SLUG" = "deepseek" ]; then
  bash "$SKILL_DIR/scripts/make_deepseek_icon.sh" "$FORK_ICNS" || echo "  official logo unavailable, using bundled icon"
fi
if [ ! -f "$FORK_ICNS" ] && [ -f "$SKILL_DIR/assets/$APP_NAME.icns" ]; then
  cp "$SKILL_DIR/assets/$APP_NAME.icns" "$FORK_ICNS"
fi
if [ -f "$FORK_ICNS" ]; then
  plist "Delete :CFBundleIconName"
  plist "Set :CFBundleIconFile $APP_NAME.icns"
fi

# 4. Ad-hoc re-sign (the edited Info.plist breaks OpenAI's signature). No hardened runtime,
#    so no entitlements are needed; OpenAI team-bound entitlements would not validate anyway.
xattr -cr "$FORK_APP"
codesign --force --deep --sign - "$FORK_APP" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --deep --strict "$FORK_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$FORK_APP"
touch "$FORK_APP"

echo
echo "Installed $FORK_APP ($(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST"))"
echo "  CODEX_HOME: $FORK_CODEX_HOME"
echo "  user data:  $FORK_USER_DATA"
echo "Re-sync after changing the provider in CC Switch:"
echo "  python3 \"$SKILL_DIR/scripts/sync_config.py\" --provider \"$PROVIDER_NAME\" --target \"$FORK_CODEX_HOME\""

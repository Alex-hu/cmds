#!/usr/bin/env bash
# cmds installer for macOS — downloads a prebuilt binary from GitHub Releases.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Alex-hu/cmds/main/install.sh | bash
#
# Options:
#   --version <tag>   install a specific release tag (default: latest)
#   --dest <dir>      installation directory
#                     (default: /usr/local/bin if writable, else ~/.local/bin)
#   -h, --help        show this help
#
# Release assets are produced by .github/workflows/release.yml as
#   cmds-<tag>-macos-<arm64|x86_64|universal>.tar.gz (+ .sha256)

set -euo pipefail

REPO="Alex-hu/cmds"
VERSION=""
DEST_ARG=""

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  echo "install.sh: $*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      [ $# -ge 2 ] || die "--version requires a value"
      VERSION="$2"
      shift 2
      ;;
    --dest)
      [ $# -ge 2 ] || die "--dest requires a value"
      DEST_ARG="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (see --help)"
      ;;
  esac
done

for cmd in curl tar shasum install; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

[ "$(uname -s)" = "Darwin" ] || die "unsupported OS: $(uname -s) (this build is macOS-only for now)"

# Rosetta 下 uname -m 报 x86_64，优先装原生 arm64
ARCH="$(uname -m)"
translated="$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)"
if [ "$ARCH" = "x86_64" ] && [ "$translated" = "1" ]; then
  ARCH="arm64"
fi
case "$ARCH" in
  arm64 | x86_64) ;;
  *) die "unsupported architecture: $ARCH" ;;
esac

if [ -z "$VERSION" ]; then
  VERSION="$(curl -fsSL --retry 3 "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
  [ -n "$VERSION" ] || die "failed to resolve latest release (is https://github.com/${REPO} public?)"
fi

ASSET="cmds-${VERSION}-macos-${ARCH}.tar.gz"
BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading ${ASSET}"
curl -fSL --retry 3 --progress-bar -o "$TMP/$ASSET" "${BASE_URL}/${ASSET}" \
  || die "download failed — does ${VERSION} ship a macOS ${ARCH} asset?"
curl -fsSL --retry 3 -o "$TMP/$ASSET.sha256" "${BASE_URL}/${ASSET}.sha256"

echo "==> Verifying checksum"
(cd "$TMP" && shasum -a 256 -c "$ASSET.sha256" >/dev/null) || die "checksum mismatch"

tar -xzf "$TMP/$ASSET" -C "$TMP"
[ -f "$TMP/cmds" ] || die "archive does not contain a cmds binary"

if [ -n "$DEST_ARG" ]; then
  DEST="$DEST_ARG"
elif [ -w /usr/local/bin ] 2>/dev/null; then
  DEST="/usr/local/bin"
else
  DEST="$HOME/.local/bin"
fi
mkdir -p "$DEST"
[ -e "$DEST/cmds" ] && echo "==> Replacing existing $DEST/cmds"
install -m 0755 "$TMP/cmds" "$DEST/cmds"

case ":$PATH:" in
  *":$DEST:"*) ;;
  *)
    echo "note: $DEST is not in your PATH; add it with:"
    echo "  echo 'export PATH=\"$DEST:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    ;;
esac

echo "==> Installed: $("$DEST/cmds" version) at $DEST/cmds"

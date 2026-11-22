#!/usr/bin/env sh
# access-desktop-build.sh — build harbor desktop's helper app (harbor/D-95, harbor#1440).
# secret-seam: `security find-identity` lists signing identities (names and hashes, never key material), and
# `security import` installs the local self-signed signing certificate the operator asks for with --make-identity.
#
#   sh bin/access-desktop-build.sh [--out <dir>]   compile, bundle and sign HarborDesktop.app
#   sh bin/access-desktop-build.sh --make-identity  once, by the operator: a local signing certificate
#
# The app lives at a FIXED path ($HOME/.local/lib/harbor by default) because macOS keys the Accessibility,
# Screen Recording and Automation grants to the app's signature: a copy elsewhere is a new app.
# WHY AN IDENTITY: an ad-hoc signature is the binary's hash, so every rebuild was a new app to macOS and lost its grants
# (measured 2026-11-21: Accessibility true → false across one rebuild). Signed with one certificate, the app keeps its
# designated requirement (identifier + certificate) across rebuilds. The certificate is self-signed and local: it is
# never trusted system-wide and signs nothing else.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/library-log.sh"
log_init access-desktop-build
out="$HOME/.local/lib/harbor"
ident="Harbor Desktop Signing"
case "${1:-}" in
  -h|--help) sed -n 2,14p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --out) out="$2" ;;
  --make-identity)
    if security find-identity -p codesigning | grep -q "\"$ident\""; then log_ok "identity exists: $ident"; log_end; exit 0; fi
    t=$(mktemp -d "${TMPDIR:-/tmp}/harbor-desktop-id.XXXXXX"); trap 'rm -rf "$t"' EXIT
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$ident" -keyout "$t/k.pem" -out "$t/c.pem" \
      -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
    openssl pkcs12 -export -legacy -inkey "$t/k.pem" -in "$t/c.pem" -name "$ident" -passout pass:harbor -out "$t/id.p12"
    security import "$t/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P harbor -T /usr/bin/codesign >/dev/null
    if security find-identity -p codesigning | grep -q "\"$ident\""; then log_ok "identity installed: $ident"
    else log_fail "identity not found after import"; log_nofix "harbor#1440"; fi
    log_end; exit $? ;;
  '') ;;
  *) log_fail "unknown option '$1'"; log_fix "sh bin/access-desktop-build.sh --help"; log_end; exit 64 ;;
esac
app="$out/HarborDesktop.app"
work="${TMPDIR:-/tmp}/harbor-desktop-build.$$"
mkdir -p "$work/mc" "$app/Contents/MacOS"
trap 'rm -rf "$work"' EXIT
command -v swiftc >/dev/null 2>&1 || { log_fail "swiftc is missing"; log_fix "xcode-select --install"; log_end; exit 1; }
swiftc -O -swift-version 5 -module-cache-path "$work/mc" \
  -o "$work/HarborDesktop" "$here/access-desktop-helper.swift"
cp "$work/HarborDesktop" "$app/Contents/MacOS/HarborDesktop"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.harbor.desktop</string>
  <key>CFBundleName</key><string>HarborDesktop</string>
  <key>CFBundleExecutable</key><string>HarborDesktop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Harbor's desktop helper runs scripts the operator confirmed, in the apps they allowed.</string>
</dict></plist>
PLIST
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$ident\""; then
  codesign --force --sign "$ident" --identifier dev.harbor.desktop "$app" 2>/dev/null
  log_ok "signed with $ident: grants survive rebuilds"
else
  codesign --force --sign - --identifier dev.harbor.desktop "$app" 2>/dev/null
  log_warn "no '$ident' identity: ad-hoc signed, so macOS drops the grants on every rebuild"
  log_fix "sh bin/access-desktop-build.sh --make-identity"
fi
if codesign --verify "$app" 2>/dev/null; then log_ok "built: $app"; else log_fail "signature does not verify: $app"; log_fix "sh bin/access-desktop-build.sh"; fi
log_end

#!/usr/bin/env bash
#
#   app/build.sh — turn this repository into Kliner.app
#
#   No Xcode project: swiftc from the command line tools, a plist, an icon,
#   and the whole of nimo copied inside. The app is one file people can
#   download, drag into Applications, and delete again by dragging out.
#
#   Run it on a Mac:  bash app/build.sh
#   Out comes:        app/build/Kliner.app  and  app/build/Kliner.app.zip
#
set -eu

root=$(cd -P "$(dirname "$0")/.." && pwd)
cd "$root"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "build.sh: a Mac app can only be built on a Mac" >&2
    exit 1
fi

for tool in swiftc sips iconutil lipo codesign ditto; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "build.sh: $tool is missing — install the Xcode command line tools:" >&2
        echo "  xcode-select --install" >&2
        exit 1
    }
done

version=$(tr -d ' \n' < VERSION)
build="$root/app/build"
app="$build/Kliner.app"

echo "==> nimo $version"

rm -rf "$build"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

# --- the icon -----------------------------------------------------------
# One 1024 square in the repository; every size macOS wants comes out of it
# here, so there is only ever one picture to change.
echo "==> icon"
iconset="$build/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" assets/app/icon-1024.png \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" assets/app/icon-1024.png \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$iconset"

# every picture the app draws itself with, at every scale a Mac may ask for
cp app/Resources/*.png "$app/Contents/Resources/"

# the typeface, which travels with the app rather than being installed
mkdir -p "$app/Contents/Resources/fonts"
cp app/Resources/fonts/* "$app/Contents/Resources/fonts/"

# --- the plist ----------------------------------------------------------
sed "s/__VERSION__/$version/g" app/Info.plist > "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

# --- the program --------------------------------------------------------
# Both architectures, so the same download works on an Intel Mac and on an
# Apple silicon one. Neither of us knows which the person has.
echo "==> compiling"
slices=""
for arch in arm64 x86_64; do
    if swiftc -O -whole-module-optimization \
        -target "${arch}-apple-macos12.0" \
        -o "$build/Kliner-$arch" \
        app/Sources/*.swift 2>"$build/$arch.log"
    then
        slices="$slices $build/Kliner-$arch"
        echo "    $arch"
    else
        echo "    $arch failed:" >&2
        cat "$build/$arch.log" >&2
        # arm64 is not optional; an Intel-only build on a modern Mac is no
        # build at all.
        [ "$arch" = "x86_64" ] || exit 1
    fi
done

# shellcheck disable=SC2086
lipo -create $slices -output "$app/Contents/MacOS/Kliner"
rm -f "$build"/Kliner-arm64 "$build"/Kliner-x86_64
chmod 755 "$app/Contents/MacOS/Kliner"

# --- nimo itself --------------------------------------------------------
# The app carries the program it is a window on. Not the tests, not the
# workflows, not the repository — the parts that run.
echo "==> bundling nimo"
inside="$app/Contents/Resources/nimo"
mkdir -p "$inside"
cp min VERSION LICENSE README.md "$inside/"
cp -R lib "$inside/lib"
cp -R completions "$inside/completions"
chmod 755 "$inside/min"

# --- sign it ------------------------------------------------------------
# Why this is not just `codesign -s -`:
#
# macOS remembers what you have allowed an app to touch by its signature. An
# ad-hoc signature is the file's own hash, so it changes every time a byte of
# the app changes — and every rebuild arrives as a stranger that has to ask
# for your Desktop and your Downloads all over again.
#
# A signing identity of its own fixes that. It is self-signed and nobody else
# trusts it, which is fine: Gatekeeper is not what is being solved here.
# macOS only needs the identity to be *the same one* each time, and then it
# stops asking twice for the same thing.
identity="Kliner Local"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$identity"; then
    echo "==> making a signing identity (once, self-signed, no administrator)"
    work=$(mktemp -d)
    cat > "$work/openssl.cnf" <<CONF
[ req ]
distinguished_name = name
x509_extensions    = codesign
prompt             = no
[ name ]
CN = $identity
[ codesign ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
CONF
    if openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -config "$work/openssl.cnf" \
        -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1 &&
       openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
        -name "$identity" -passout pass: -out "$work/id.p12" >/dev/null 2>&1 &&
       security import "$work/id.p12" -k ~/Library/Keychains/login.keychain-db \
        -P "" -T /usr/bin/codesign >/dev/null 2>&1
    then
        # let codesign use the key without asking every single time
        security set-key-partition-list -S apple-tool:,apple:,codesign: \
            -s -k "" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || true
        echo "    made \"$identity\""
    else
        echo "    could not make one; falling back to an ad-hoc signature"
        identity="-"
    fi
    rm -rf "$work"
fi

echo "==> signing"
if ! codesign --force --deep --sign "$identity" --timestamp=none "$app" >/dev/null 2>&1; then
    echo "    that identity did not work; falling back to an ad-hoc signature" >&2
    codesign --force --deep --sign - --timestamp=none "$app" >/dev/null 2>&1 || {
        echo "build.sh: could not sign the app" >&2
        exit 1
    }
fi
codesign --verify --deep --strict "$app" || {
    echo "build.sh: the signature did not verify" >&2
    exit 1
}

# --- and wrap it --------------------------------------------------------
# ditto, not zip: it is the one that keeps the bundle's symlinks and flags
# intact, and a zip that loses those is an app that will not open.
echo "==> zipping"
( cd "$build" && ditto -c -k --sequesterRsrc --keepParent Kliner.app Kliner.app.zip )

size=$(du -h "$build/Kliner.app.zip" | cut -f1)
echo
echo "    $build/Kliner.app.zip  ($size)"
echo

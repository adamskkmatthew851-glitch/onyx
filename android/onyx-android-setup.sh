#!/data/data/com.termux/files/usr/bin/bash
# Onyx Music Game Toolkit on Android (ARM64)
#
# Runs the full Onyx desktop GUI on an Android phone/tablet using:
#   - Termux          (terminal + package manager)
#   - Termux:X11      (Android app that displays Linux GUI programs)
#   - proot-distro    (Ubuntu ARM64 userland, no root needed)
#   - a native linux-arm64 build of Onyx
#
# Usage (inside Termux):
#   bash onyx-android-setup.sh [URL-or-path-to-onyx-linux-arm64.tar.gz]
# Afterwards start Onyx with:  onyx
set -e

ONYX_TARBALL="${1:-${ONYX_TARBALL:-}}"
DISTRO=ubuntu

if [ -z "$PREFIX" ] || [ ! -d /data/data/com.termux ]; then
  echo "Run this inside the Termux app." >&2; exit 1
fi
if [ "$(uname -m)" != aarch64 ]; then
  echo "This device is $(uname -m); the Onyx build is for 64-bit ARM (aarch64)." >&2; exit 1
fi
if [ -z "$ONYX_TARBALL" ]; then
  echo "Pass the onyx-*-linux-arm64.tar.gz file or its download URL as the first argument." >&2; exit 1
fi

echo "== Termux packages"
yes | pkg update
pkg install -y x11-repo
pkg install -y termux-x11-nightly proot-distro pulseaudio wget

echo "== Storage access (grant the permission if Android asks)"
[ -d "$HOME/storage" ] || termux-setup-storage || true

echo "== Ubuntu userland"
proot-distro list 2>/dev/null | grep -q "Alias: $DISTRO.*installed" || \
  [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO" ] || proot-distro install $DISTRO
ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"

echo "== Onyx runtime libraries"
proot-distro login $DISTRO -- bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates libgl1 libglx-mesa0 libgl1-mesa-dri libglu1-mesa libegl1 \
    libx11-6 libxext6 libxft2 libxinerama1 libxcursor1 libxfixes3 libxrender1 libxrandr2 \
    libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 libcairo2 libglib2.0-0 \
    libfontconfig1 fonts-dejavu-core fonts-noto-cjk \
    libpulse0 libasound2t64 libasound2-plugins zenity xdg-utils \
  || apt-get install -y --no-install-recommends \
    ca-certificates libgl1 libgl1-mesa-dri libglu1-mesa libegl1 \
    libx11-6 libxext6 libxft2 libxinerama1 libxcursor1 libxfixes3 libxrender1 libxrandr2 \
    libpango-1.0-0 libpangocairo-1.0-0 libcairo2 libglib2.0-0 libfontconfig1 \
    fonts-dejavu-core libpulse0 libasound2 zenity xdg-utils
'

echo "== Installing Onyx"
TMP="$HOME/onyx-arm64.tar.gz"
case "$ONYX_TARBALL" in
  http*) wget -O "$TMP" "$ONYX_TARBALL" ;;
  *) cp "$ONYX_TARBALL" "$TMP" ;;
esac
rm -rf "$ROOTFS/opt/onyx"
mkdir -p "$ROOTFS/opt/onyx"
tar xzf "$TMP" -C "$ROOTFS/opt/onyx" --strip-components=1
rm -f "$TMP"
# ALSA -> PulseAudio so OpenAL playback reaches Android's audio output
cat > "$ROOTFS/etc/asound.conf" <<'EOF'
pcm.!default { type pulse }
ctl.!default { type pulse }
EOF

echo "== Launcher"
cat > "$PREFIX/bin/onyx" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# Start sound + display servers, then Onyx inside Ubuntu.
pulseaudio --check 2>/dev/null || pulseaudio --start --exit-idle-time=-1 \
  --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" >/dev/null 2>&1
pgrep -f termux.x11 >/dev/null || (termux-x11 :0 >/dev/null 2>&1 &)
sleep 2
am start -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
exec proot-distro login $DISTRO --shared-tmp -- env \\
  DISPLAY=:0 PULSE_SERVER=tcp:127.0.0.1 LIBGL_ALWAYS_SOFTWARE=1 \\
  FLTK_SCALING_FACTOR="\${ONYX_SCALE:-1.5}" \\
  HOME=/root /opt/onyx/AppRun "\$@"
EOF
chmod +x "$PREFIX/bin/onyx"

echo
echo "Done. Install the Termux:X11 app (https://github.com/termux/termux-x11/releases) if you have not,"
echo "then run:  onyx"
echo "Your phone storage is visible in Onyx under /sdcard (or /storage/emulated/0)."
echo "Set ONYX_SCALE (e.g. ONYX_SCALE=2 onyx) to make the interface bigger."

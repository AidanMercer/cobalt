#!/usr/bin/env bash
# open or raise cobalt:  cobalt.sh
# a second launch just raises the running window and exits, so this is always
# safe to spam from a keybind.
export PYTHONPATH="$(dirname "$(readlink -f "$0")")${PYTHONPATH:+:$PYTHONPATH}"

# help WebRTC screen-share negotiate through the Wayland portal + PipeWire.
# harmless on X11; drop it if a future Qt wires this on by default.
export QTWEBENGINE_CHROMIUM_FLAGS="--enable-features=WebRTCPipeWireCapturer ${QTWEBENGINE_CHROMIUM_FLAGS}"

setsid -f python -m cobalt "$@" >/dev/null 2>&1

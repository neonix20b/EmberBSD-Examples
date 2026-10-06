# Nested Wayland test on EmberBSD

This test runs Qt's official Minimal QML Wayland compositor in an X11 window,
then opens Kate as a native Wayland client. It does not switch the desktop,
replace Xorg or prove native DRM/KMS support.

Tested on 2026-10-06 with the [GNOME UTM setup](../gnome-utm/README.md):
EmberBSD `EMBER64` kernel from `b4f718d`, NetBSD 11/aarch64 userland,
Qt 6.11.1 and Kate 25.08.3 from the `11.0_2026Q2` package catalog.

Install prerequisites as root if absent:

```sh
pkgin -y install qt6-qtdeclarative qt6-qtwayland kate curl
```

From a terminal in the existing X11 desktop, run as the ordinary user:

```sh
sh run.sh
```

The script downloads the unmodified Qt `v6.11.1` example and its BSD license,
verifies both SHA256 sums, and uses software rendering with shared memory.
The private runtime directory, logs and test document are retained beneath
`~/.cache/emberbsd-wayland.*`. Close Kate, or interrupt the script, to stop
the processes it started. No login configuration is changed.

## What was checked

- Kate displayed through Qt's nested compositor.
- Keyboard input produced `wayland ok`, and Ctrl+S saved it to disk.
- A mouse click opened Kate's File menu.
- Kate had `QT_QPA_PLATFORM=wayland` and no `DISPLAY` variable.
- `fstat` showed Kate connected to the private Wayland socket. The compositor
  connected to both that socket and `/tmp/.X11-unix/X0`.

To inspect the transport, use the process IDs printed by the script:

```sh
fstat -p CLIENT_PID
fstat -p COMPOSITOR_PID
```

The compositor may report failure to initialize EGL before falling back to
shared-memory software rendering. Visible output and input must still be
checked; the existence of a socket alone does not establish success.

## GNOME and native Wayland limits

The installed GNOME Shell 40.2 and Mutter 40.2 reject `--wayland` with
`Unknown option --wayland`. The [pkgsrc 2026Q2 Mutter recipe](https://github.com/NetBSD/pkgsrc/blob/pkgsrc-2026Q2/wm/mutter/Makefile)
sets `-Dwayland=false` and `-Dnative_backend=false` unconditionally.
It disables EGL only when EGL is unavailable; this installed Mutter links EGL.
The current UTM guest uses `genfb`/`wsfb`; opening `/dev/dri/card0` or
`/dev/dri/renderD128` as root returns `ENODEV`. Device node names alone are
not evidence of a functioning DRM driver.

Thus this test establishes a working Wayland protocol/client path nested in
Xorg. A native GNOME Wayland session needs additional compositor/backend
and display-driver work. This result says nothing about GPU support on boards.

## Upstream source and license

- [Qt Minimal QML source, v6.11.1](https://github.com/qt/qtwayland/blob/v6.11.1/examples/wayland/minimal-qml/main.qml)
  — SHA256 `24bb1e92588ab689711dd557e67dd0abf9de5282fc3895d9a72b3ee2b2a312cb`.
- [Qt BSD-3-Clause license](https://github.com/qt/qtwayland/blob/v6.11.1/LICENSES/BSD-3-Clause.txt)
  — SHA256 `9f0490f18656c6f2435bd14f603ef0c96434d1825615363dce43abb42ed1dcce`.
- [Official example documentation](https://doc.qt.io/qt-6.11/qtwaylandcompositor-minimal-qml-example.html).

Inputs retrieved on 2026-10-06. Copyright and SPDX identifiers remain in the
original QML file; it is downloaded together with its license, not rewritten.

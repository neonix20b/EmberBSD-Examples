# Native Phosh build probe

**2026-10-06: Phosh 0.58.0 configuration stops at missing GTK3 Wayland.
No Phosh binary or mobile session was produced.**

The probe builds GNOME Bluetooth 46.2 and gmobile 0.1.0, tests them and
installs them into a fresh private prefix. It then attempts to configure
and compile unmodified Phosh 0.58.0. All sources, licenses and logs remain
under the ordinary user's `~/.cache/emberbsd-phosh.*` directory.
It does not change the desktop session or install Phosh system-wide.

## Reproduce

Start with the packages from the [GNOME example](../gnome-utm/README.md).
The probe additionally needs these pkgsrc packages, installed as root:

```sh
pkgin -y install meson ninja-build cmake pkgconf curl libhandy libsoup3 gsound glib2-tools gdbus-codegen
```

Upstream Meson, GLib code generators and build scripts use Python. This
shell helper creates a private `python3` link to `/usr/pkg/bin/python3.13`;
set `PYTHON` to an absolute interpreter path for another pkgsrc version.
It does not add a system-wide alias. Our helper uses POSIX shell.

Copy this directory, including the patch, then run as an ordinary user:

```sh
sh probe.sh
```

For an offline run, pass a directory containing the three pinned archives:

```sh
sh probe.sh /path/to/source-archives
```

Both modes verify every archive's SHA256 before extracting it. Meson's
automatic subproject downloads are disabled. `JOBS` defaults to 3.
Every build stage has its own log. A failed build or test returns nonzero;
successful dependency builds do not imply that Phosh compiled.
The prefix is disposable; remove only the printed probe directory to clean up.

## Native results and limits

The probe ran on NetBSD 11/aarch64, EmberBSD `EMBER64` kernel from `b4f718d`,
GCC 12.5.0, Meson 1.11.1, GLib 2.88.1 and GTK3 3.24.52, with packages from
the `11.0_2026Q2` catalog.

| Component | Result |
|---|---|
| GNOME Bluetooth 46.2 | Unmodified libraries compiled; 2 tests passed, 1 integration test skipped |
| gmobile 0.7.4, separate initial attempt | Compilation failed: Linux `CLOCK_BOOTTIME_ALARM` is unavailable |
| gmobile 0.1.0 | Library compiled; original tests: 5 passed, 1 failed; with the test-only patch: 6 passed |
| Phosh 0.58.0 | Found both private libraries; configuration failed at `gtk+-wayland-3.0` |

Version 0.1.0 is the fallback revision specified by Phosh 0.58.0's own
`subprojects/gmobile.wrap` and meets its declared minimum. This is a
build experiment, not a recommendation to ship the old library.
The 0.7.4 failure was not bypassed by replacing the wake alarm with a
clock that cannot wake a suspended device.

The included test patch checks the existing non-Linux contract of
`gm_device_tree_get_compatibles`: it returns `G_IO_ERROR_NOT_SUPPORTED`.
The original test assumed Linux sysfs for every platform. Linux test
coverage and the library implementation are unchanged. Passing the
patched test does **not** establish native device-tree support.
Bluetooth runtime still needs a compatible BlueZ service and was not tested.

Installed GTK3 has the `x11` option, without `wayland`. The
[pkgsrc GTK3 recipe](https://github.com/NetBSD/pkgsrc/blob/pkgsrc-2026Q2/x11/gtk3/options.mk)
offers a Wayland option, so this particular failure is a package build
configuration issue. We did not rebuild or replace the active GTK stack.

Further mandatory dependencies are also absent from the tested catalog:
`libnm` (NetworkManager), `mm-glib` (ModemManager), and either `libsystemd`
or `libelogind`. Phosh also directly includes Linux rfkill and systemd
headers. There is no build switch to remove all these integrations.
These are source/inventory findings beyond the observed Meson failure,
not compiler errors from a completed Phosh configuration.

Phoc and libfeedback are also missing. A running mobile session would
need a compatible Wayland compositor and further runtime verification.
No phone display, touchscreen, keyboard, rotation, suspend or modem
support is established by this probe.

## Provenance

Official archives downloaded on 2026-10-06 and checked against upstream
checksum files:

| Archive | SHA256 |
|---|---|
| [phosh-0.58.0.tar.xz](https://sources.phosh.mobi/releases/phosh/phosh-0.58.0.tar.xz) | `b936af34ebed15b29d4f941c48aa328a47da9c2e51cbf6ef89040a90f522ed73` |
| [gnome-bluetooth-46.2.tar.xz](https://download.gnome.org/sources/gnome-bluetooth/46/gnome-bluetooth-46.2.tar.xz) | `1b48feec75b8b4f1a6e564cce7cc4ebd35b3225cb8d8be93c8efc44894003635` |
| [gmobile-0.1.0.tar.xz](https://sources.phosh.mobi/releases/gmobile/gmobile-0.1.0.tar.xz) | `47172e7b245fbb30b40c02135d2ff36987e36a8e825f9bf5932acd2aa6eabfcd` |
| [gmobile-0.7.4.tar.xz](https://sources.phosh.mobi/releases/gmobile/gmobile-0.7.4.tar.xz), initial attempt only | `17cdcc27a6eb7fe9d31268893b789ca03e1800312f32a15b25d1fc6cd3f29f32` |

`gmobile-device-tree-test.patch` modifies `tests/test-device-tree.c` from
gmobile 0.1.0, copyright 2022 The Phosh Developers, author Guido Günther,
SPDX `GPL-3.0-or-later`. The local test adjustment was AI-assisted and
has not been submitted to or accepted by upstream. Original notices and
licenses remain in the extracted source tree.

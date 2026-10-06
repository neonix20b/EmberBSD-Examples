# Native Wayland and VirGL in UTM

Experimental runtime checks for the current EmberBSD/NetBSD 11 aarch64 guest.
Build recipes, original source URLs, hashes and portability patches belong to
[EmberBSD Ports](https://github.com/neonix20b/EmberBSD-Ports/tree/main/probes/wayland-utm).
The kernel integration belongs to
[EmberBSD](https://github.com/apovalixin/EmberBSD/blob/main/ember/boot/utm-virgl-design.md).

## Current evidence

On 2026-10-06, the private libdrm 2.4.134, Mesa 21.3.9 (VirGL and softpipe),
wlroots 0.19.3 and labwc 0.9.7 stack compiled natively. Mesa passed 81 tests,
labwc passed three, and libdrm passed three with one device-dependent skip.
The EGL probe below passed all pixels using softpipe and exited normally.
The loaded EGL, GBM, GLES and libdrm libraries came from the private prefix.

At this stage native KMS, native input and VirGL acceleration are unverified.
The working guest still uses its framebuffer kernel and GNOME/Xorg recovery
session. A successful software or nested check is not GPU support.

## EGL allocation and readback

Build the probe as an ordinary user against the private graphics prefix:

```sh
sh build-probe.sh "$HOME/.cache/emberbsd-wayland-build/install" ./egl-readback
LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=softpipe ./egl-readback --software
```

The probe creates 64 texture/framebuffer pairs, paints four quadrants,
waits for rendering, checks every RGBA pixel, and destroys its context.
This detects transfer/lifetime failures and premature process-exit crashes.
The build helper checks pkg-config provenance for EGL, GLES, GBM and libdrm.
NetBSD's system libm may emit its existing compatibility `cabs`/`cabsf` and
`_tgammal` precision warnings while linking this Mesa stack.

Once the kernel implements the standard VirtGPU 3D ABI and UTM provides a
GL-enabled device, run without inherited software overrides:

```sh
unset LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE
./egl-readback /dev/dri/renderD128
```

GPU mode requires a VirGL renderer and rejects softpipe/llvmpipe. It still
requires separate evidence that UTM's host renderer uses the Mac GPU.
Record the actual host backend and device settings; the Metal presentation
window alone does not establish acceleration. An inaccessible render node
is a failed GPU check, not an invitation to widen CREATE_DUMB permissions.

## Native session probe

Preserve the known-good kernel, UTM display settings and login configuration.
Use the existing desktop account. The kernel must expose working DRM/KMS,
and seatd must correctly restore NetBSD's wscons keyboard mode on exit; see
the companion Ports probe. Complete visible KMS checks before this step.

Log out of the graphical desktop and stop its display manager through a
separate administrator connection. Run from a text console as the ordinary
desktop user, keeping that recovery connection available:

```sh
sh run.sh "$HOME/.cache/emberbsd-wayland-build/install" software
# After successful software KMS/input and VirGL pixel checks:
sh run.sh "$HOME/.cache/emberbsd-wayland-build/install" virgl
```

The launcher forces the DRM/libinput backends and card0, creates a private
runtime directory, and uses seatd to give the ordinary user device access.
It starts a separate D-Bus session and native Wayland Kate. Save a sentence,
use menus, test modifiers and pointer coordinates, then close Kate to exit.
Ctrl+Alt+Escape also terminates the compositor. Logs, library paths and the
saved file remain in the printed mode-0700 temporary directory.

Software mode selects wlroots Pixman and software rendering for clients.
VirGL mode selects GLES and removes the known software overrides. The
launcher never creates users, changes passwords, enables automatic login,
or changes the default display manager. Xwayland is disabled in this first
build; native GNOME Wayland remains a separate porting task.

Acceptance also requires VT handoff, crash/exit recovery, same-device
cross-process PRIME sharing, malformed-ioctl checks, allocation stress,
in-flight client termination and a thirty-minute runtime test. Retest the
saved framebuffer/Xorg recovery path after changing the UTM display device.

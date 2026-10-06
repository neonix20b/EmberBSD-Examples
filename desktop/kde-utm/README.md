# KDE desktop in UTM

This example uses an EmberBSD `EMBER64` kernel with NetBSD 11.0/aarch64
userland and X11. The desktop is KDE 4, using the available pkgsrc binary
packages. Dolphin, Konsole and Kate use Qt 6 from the same package catalog.
This is not a Plasma 6 desktop: a complete Plasma 6 workspace was absent
from the tested binary repository.

## Requirements

- Apple Silicon Mac, UTM 4.7.5, QEMU `virt`, UEFI, HVF enabled.
- 4 vCPUs, 4 GiB RAM, at least 24 GiB virtual disk, shared networking.
- `virtio-ramfb` display, USB keyboard and pointing devices, virtio disk.
- Installed NetBSD 11/aarch64 base and X11 sets, working SSH recovery.
- A clean current EmberBSD checkout containing the PCI framebuffer fix
  `b4f718dabd085ed117a24f84d8558e4a43091dc0` and a native NetBSD build guest.
- An existing local non-root account with a password for KDM login.
  The scripts neither create accounts nor change credentials or enable
  automatic login. A cloud-image account with a locked password cannot
  log in to KDM until the operator configures its authentication.

The tested firmware framebuffer is 800×600. There is no accelerated 3D,
automatic resolution switching or tested audio setup. This is a VM
demonstration, not confirmation of graphical support on a physical board.

## Install the kernel

Build from a pinned clean commit in the native NetBSD 11/aarch64 guest:

```sh
sh ember/tools/virtio-pci-rescan-test.sh
sh ember/build-kernel.sh /absolute/output EMBER64
```

Keep the commit, build log and SHA256 hashes with the binary set. Transfer
the new ELF kernel, native image and all three `.kmod` files to the target
VM. Check their hashes on both ends. Use separate output directories for
different builds so a failure cannot reuse an old kernel.

Before the first replacement, preserve `/netbsd`, `/boot/netbsd.img` if
present, and `/stand/evbarm/11.0/modules` under distinct recovery names.
Install the new ELF kernel as `/netbsd` and native image as
`/boot/netbsd.img`. Create a fresh `/stand/evbarm/11.0/modules` containing:

```text
bcm2712btcom/bcm2712btcom.kmod
if_cemac_acpi/if_cemac_acpi.kmod
rp1wmcodec/rp1wmcodec.kmod
```

These board modules are not required by the VM, but must come from the
same build. Do not combine the new kernel with the stock module set.

Create `/boot/boot.cfg` on the EFI partition:

```text
menu=EmberBSD:userconf disable viogpu;boot netbsd
menu=EmberBSD single user:userconf disable viogpu;boot netbsd -s
menu=Boot prompt:prompt
default=1
timeout=5
```

Reboot. Confirm `uname -a` identifies `EMBER64`, SSH still works, and
`dmesg` shows `genfb0` and `wsdisplay0`. The disabled `viogpu` child is
intentional. See the [kernel explanation and integration regression](https://github.com/apovalixin/EmberBSD/blob/main/ember/boot/utm-framebuffer.md).
`virtio-gpu-pci` and standalone `ramfb` were not substitutes for the tested
`virtio-ramfb` setting with UTM's bundled firmware.

## Configure KDE

Install pkgin and select the tested repository:

```text
https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/aarch64/11.0_2026Q2/All
```

Place that URL in `/usr/pkg/etc/pkgin/repositories.conf`, then run as root:

```sh
pkgin update
sh setup.sh YOUR_EXISTING_USER
shutdown -r now
```

`setup.sh` installs KDE and its applications, enables D-Bus and KDM,
selects `wsfb`, disables compositing, and selects KDE in the account's
`.dmrc`. It assigns the `emberdesktop` login class: 8192 open descriptors
per process, with a 16384 hard limit. KDE's kqueue file watchers exhaust
the default 1024-descriptor limit. The kernel file limit is set to 32768;
KDM's greeter also receives the higher soft limit.

The script saves configuration backups with `.before-emberbsd-kde` before
the first change; service-script backups go under `/var/backups/emberbsd-kde`
so rcorder will not execute them. It is intended for a dedicated demo VM; review it before
applying it to a system with custom desktop configuration.

Log in through KDM. Run `sh verify.sh` in a desktop terminal. It checks
KWin and Plasma processes, X11 dimensions, installed applications, a home
directory write, DNS and HTTPS. Also check the UTM window directly:

1. Move the pointer, type in Konsole, and launch Dolphin and Kate.
2. Create, save and reopen a small text file in the home directory.
3. Log out and back in; reboot and repeat the checks.

A successful `xdpyinfo` does not prove the display is visible. Before the
kernel fix it succeeded while UTM showed an inactive display.

## Recovery and limits

Keep SSH available during setup. From the boot menu choose single-user
mode to repair configuration, or boot the preserved kernel at the prompt.
The stock GENERIC64 kernel may need TCG instead of HVF; restore its module
directory as a set when returning to that kernel.

Inspect `/var/log/Xorg.0.log`, `/var/log/kdm.log` and the account's
`.xsession-errors` for failures. If pkg_add reports a malformed archive,
check cached `.tgz` files with `gzip -t`, quarantine only damaged files and
fetch them again from the official repository. Use `pkg_admin check`
after installation. Never count a partial package installation as success.

The tested catalog's `attr-2.5.2` package has two dangling manual-page
aliases (`attr_getf.3` and `attr_setf.3`). These are separate from archive
corruption; they do not prevent these desktop applications from running.

KDE 4 may log unavailable HAL, activity or sound services in this minimal
VM. Hot-plug storage management, sound, clipboard sharing, suspend and
long-running stability require separate validation.

Sources: [pkgsrc package catalog](https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/aarch64/11.0_2026Q2/All/),
[NetBSD QEMU ARM](https://wiki.netbsd.org/ports/evbarm/qemu_arm/),
[wsfb with UEFI](https://wiki.netbsd.org/tutorials/x11/how_to_use_wsfb_uefi_bios_framebuffer/).

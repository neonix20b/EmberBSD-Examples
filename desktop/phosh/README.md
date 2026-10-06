# Phosh recipes live in Ports

The native Phosh recipes and portability patches live in
[EmberBSD Ports](https://github.com/neonix20b/EmberBSD-Ports/tree/main/probes/phosh).

On 2026-10-06, Phosh 0.58.0 was built and launched inside GNOME/X11 using
Phoc and software-rendered Wayland. The app list, GTK3 application launch,
keyboard input and saving a text file were verified. The extended profile
adds Stevia 0.58.0: screen-keyboard clicks entered English and Russian
text in gedit and saved the document. A privately patched GTK 4.22.4 runs
GTK4 Demo and Widget Factory. The extended UI checks used an isolated
Xvfb display through a localhost-only SSH/VNC viewer. This is a nested
session, not a complete phone image or hardware-support claim.

Use the Ports documentation for pinned sources, checksums, prerequisites,
the build/run helpers and the remaining integration limits, including
unavailable platform services and unverified physical touch input. The
system GTK4 package remains unchanged; use the private GTK4 prefix from
Ports for the fixed Wayland shared-memory path.

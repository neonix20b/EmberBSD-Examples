# Phosh build probe moved

The native Phosh build probe and its portability patch now live in
[EmberBSD Ports](https://github.com/neonix20b/EmberBSD-Ports/tree/main/probes/phosh).

The last probe built GNOME Bluetooth and gmobile, then stopped while
configuring Phosh 0.58.0 because GTK3 Wayland was unavailable. It did not
produce a Phosh binary or a working mobile session.

Use the Ports documentation for pinned sources, checksums, prerequisites,
the build helper and the remaining integration limits.

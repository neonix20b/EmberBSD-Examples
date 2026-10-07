# EmberBSD Examples

Standalone examples for [EmberBSD](https://github.com/apovalixin/EmberBSD),
a NetBSD-derived Unix for intelligent devices.

## Purpose

This repository turns EmberBSD capabilities into small, reproducible user
workflows. Each example owns its application code, prerequisites, build and
run instructions, tests and validation limits. Reusable third-party recipes
belong in Ports; kernel and driver fixes belong in the central OS project.

## Examples

- [Local text generation and speech recognition with llama.cpp and whisper.cpp](ai/local-inference/README.md)
- [Answers from local documents with SQLite FTS5 and llama.cpp](ai/local-knowledge/README.md)
- [Simulated device telemetry and commands with Zenoh and ROS 2 Jazzy](robotics/zenoh-ros2/README.md)
- [A software BPSK radio channel with GNU Radio](robotics/gnuradio-channel/README.md)
- [UTM framebuffer validation (retired KDE 4 setup)](desktop/kde-utm/README.md)
- [GNOME desktop in the same UTM guest](desktop/gnome-utm/README.md)
- [Wayland client and compositor nested inside Xorg](desktop/wayland-nested/README.md)
- [Native Wayland and VirGL runtime probes](desktop/wayland-utm/README.md)
- [Plasma Mobile source configuration probe and current blockers](desktop/plasma-mobile/README.md)
- [Native nested Phosh session in EmberBSD Ports](https://github.com/neonix20b/EmberBSD-Ports/tree/main/probes/phosh)

Examples contain no credentials or machine images. Review each example's
requirements and validation limits before applying it to a system.

## Related EmberBSD projects

[EmberBSD](https://github.com/apovalixin/EmberBSD#emberbsd-ecosystem) is the
central project and the entry point for the ecosystem.

- [EmberBSD](https://github.com/apovalixin/EmberBSD) — OS, drivers, boards and system builds.
- [EmberBSD-Ports](https://github.com/neonix20b/EmberBSD-Ports) — third-party recipes, patches and native dependencies used by examples.
- [EmberBSD-Runtime](https://github.com/neonix20b/EmberBSD-Runtime) — application execution and device operations; design stage.
- [EmberBSD-SDK](https://github.com/neonix20b/EmberBSD-SDK) — application contracts and development tools; design stage.
- [Ember-Agent-Skills](https://github.com/neonix20b/Ember-Agent-Skills) — instructions for AI coding assistants and tested contributions.

## Connect developer skills

Use a Codex CLI with plugin support:

```sh
codex plugin marketplace add neonix20b/Ember-Agent-Skills --ref main
codex plugin add emberbsd-development@ember-agent-skills
```

Start a new conversation and ask `$emberbsd-repository-guide` to select an
example, verify its dependencies and explain its tests. Follow the
[installation, verification and update guide](https://github.com/neonix20b/Ember-Agent-Skills#install-in-codex)
for the complete procedure and other assistant environments.

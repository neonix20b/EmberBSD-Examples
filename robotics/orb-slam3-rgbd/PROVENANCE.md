# RGB-D example provenance

This application, its C libpng reader, C++ trajectory evaluator and shell
input checks are original AI-assisted EmberBSD work under [MIT](LICENSE).
The evaluator implements nearest-timestamp association and rigid least-squares
SE(3) alignment in C++; it does not invoke or copy TUM's Python tools.
Alignment fixes scale at one, including an independent synthetic test that
rejects a trajectory scaled by two.

SLAM is provided by the installed
[EmberBSD Ports ORB-SLAM3 profile](https://github.com/neonix20b/EmberBSD-Ports/tree/main/probes/orb-slam3).
That profile pins upstream `v1.0-release`, commit
`0df83dde1c85c7ab91a0d47de7a29685d046f637`, and preserves its GPL-3.0-or-later
license and bundled dependency notices. The example does not contain an ORB
source copy or its vocabulary. Its installed consumer uses the profile's
explicit headless interface and requires `viewer=false`.

[dataset.tsv](dataset.tsv) pins the unmodified TUM RGB-D `freiburg1_desk`
archive, URL and SHA256. TUM releases the data under
[CC BY 4.0](https://cvg.cit.tum.de/data/datasets/rgbd-dataset#license).
Attribute J. Sturm, N. Engelhard, F. Endres, W. Burgard and D. Cremers,
*A Benchmark for the Evaluation of RGB-D SLAM Systems*, IROS 2012.
Images, ground truth and resulting trajectories remain outside Git.

The native validation uses shared OpenCV 5.0.0 and Eigen 5.0.1, Boost 1.91,
and libpng 1.6.58. PNG decoding preserves RGB channel order and raw uint16
depth values. It performs no gamma correction, resizing or depth rescaling.
The original upstream TUM1 calibration supplies the 5000-units-per-metre
factor. No old OpenCV or Eigen copy is introduced for this application.

[README](README.md) records the validation platform, declared acceptance
bounds, measured results and their limits. A short recorded RGB-D sequence
does not establish live camera, IMU, board, long-duration or real-time support.

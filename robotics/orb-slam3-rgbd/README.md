# Offline RGB-D SLAM on TUM fr1/desk

This standalone C++ example estimates a metric camera trajectory from recorded
RGB/depth images using ORB-SLAM3. It compares the saved, optimized trajectory
with TUM ground truth using a rigid SE(3) alignment with scale fixed at one.
EmberBSD Examples owns this application; ORB-SLAM3 owns tracking and mapping.

Two controlled complete-sequence runs passed on EmberBSD AArch64 in a VM.
This does not establish board, live camera, IMU, long-duration stability or
hard real-time support.

## Build

Install the [headless ORB-SLAM3 source profile](https://github.com/oxtech-ember/EmberBSD-Ports/tree/main/probes/orb-slam3)
and its common OpenCV 5.0.0/Eigen 5.0.1 dependencies. The other requirements
are C++17, CMake 3.20+, Ninja and libpng 1.6.58. The program uses libpng directly
because the common OpenCV installation has no PNG codec. It does not require
Pangolin, a display server, ROS, Python or another OpenCV installation.

```sh
cmake -S robotics/orb-slam3-rgbd -B /absolute/example-build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DOPENCV_PREFIX=/absolute/opencv-prefix \
  -DCMAKE_PREFIX_PATH='/absolute/orb-install;/absolute/common-prefix;/usr/pkg' \
  -DCMAKE_BUILD_RPATH='/absolute/orb-install/lib/orb-slam3;/absolute/opencv-prefix/lib;/absolute/common-prefix/lib;/usr/pkg/lib'
cmake --build /absolute/example-build --parallel 1
ctest --test-dir /absolute/example-build --output-on-failure
```

Select the same `OPENCV_PREFIX` used to build ORB. It may equal the common
Eigen prefix or name the sole OpenCV installation separately.

The numerical self-test uses a known rigid transform and rejects a doubled
trajectory scale. It checks nearest-time association without image reuse and
rejects a short exported subset of a longer successfully tracked sequence.
The runtime links the installed ORB libraries rather than a source build tree.

## Dataset and provenance

Use TUM RGB-D `freiburg1_desk` from the
[official dataset page](https://cvg.cit.tum.de/data/datasets/rgbd-dataset/download).
The sequence contains 23.4 seconds and 9.263 metres of ground-truth motion,
including loop closures. [dataset.tsv](dataset.tsv) pins its archive URL and
SHA256; the original archive is 344,011,403 bytes. Download and extraction
require roughly 0.7 GB together; keep both outside Git.

```sh
curl -fL 'https://webshare.cvg.cit.tum.de/g/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_desk.tgz' \
  -o /absolute/tum-rgbd-fr1-desk.tgz
sha256 /absolute/tum-rgbd-fr1-desk.tgz
# Expected: e983d6830916e66dc4a46a71368046b149b283de87769690e7aa4e0b9483530c
tar -xzf /absolute/tum-rgbd-fr1-desk.tgz -C /absolute/dataset-parent
```

The data is [CC BY 4.0](https://cvg.cit.tum.de/data/datasets/rgbd-dataset#license).
Attribute J. Sturm, N. Engelhard, F. Endres, W. Burgard and D. Cremers,
*A Benchmark for the Evaluation of RGB-D SLAM Systems*, IROS 2012.
The original files and timestamps remain unchanged. This example is original
AI-assisted EmberBSD work under [MIT](LICENSE). Linking ORB-SLAM3 also requires
its GPL-3.0-or-later terms and the bundled dependency notices from Ports.

## Run and interpret

```sh
/absolute/example-build/orb-rgbd \
  /absolute/dataset-parent/rgbd_dataset_freiburg1_desk \
  /absolute/orb-install/share/orb-slam3/ORBvoc.txt \
  /absolute/orb-install/share/orb-slam3/settings/TUM1.yaml \
  /absolute/new-results
```

The output directory must be new. The whole bounded sequence is processed;
no frames are dropped to catch up. RGB/depth pairs use the smallest available
timestamp difference within 20 ms, without reusing an image. The original
TUM1 calibration expects RGB8 and grayscale uint16 depth at 640×480, with
5000 depth units per metre and zero denoting invalid depth. The PNG reader
preserves those values and only converts 16-bit byte order where necessary.

Every selected image is decoded before SLAM threads start. Runtime decodes
again, limits OpenCV to one thread, fixes OpenCV and DUtils random seeds at
zero before startup, and follows the recording's time pacing
when tracking is faster than the data. ORB's mapping and loop threads remain
active; scheduling makes repeat runs numerically similar rather than bitwise
identical. Shutdown completes before trajectories are saved. NetBSD checks
that the native thread count returns to its baseline.

Results include `frames.tsv`, `trajectory.txt`, `keyframes.txt` and `metrics.txt`.
Metrics report tracked-frame fraction, timestamp-matched poses, translation
ATE RMSE/maximum in metres, rotation error, startup/tracking/shutdown elapsed
time and peak process RSS in KiB. Ground-truth association allows 20 ms and
requires at least 95% coverage of saved poses. Every exported timestamp must
belong to a selected RGB frame and occur once; every `OK` frame with a finite
pose must be present. Exported `RECENTLY_LOST` poses, if present, remain in
the error evaluation but do not count as successful tracking coverage.
Wall time excludes preflight,
trajectory output and evaluation; tracking-call time excludes decoding and
pacing. RSS is sampled after trajectory evaluation and includes preflight.
Basic metrics are saved before export/evaluation, so a failure still records
tracking, time, peak RSS through shutdown and thread counts. `failure.txt`
records the error, and `evaluation_status` distinguishes incomplete evaluation.

Acceptance bounds were selected before the first measured run: at least 90%
of depth frames must form pairs, at least 90% of paired frames must track,
translation ATE RMSE must be at most 0.10 m and maximum at most 0.30 m.
These are application smoke-test bounds for this short indoor metric RGB-D
sequence; they are not a reproduction of an upstream benchmark score.
Scale is never fitted. A failed bound returns a nonzero status while retaining
the measurements for diagnosis.

To check input handling without running SLAM, append `--validate-only`.
The following negative tests preserve the dataset and create small fixtures:

```sh
sh robotics/orb-slam3-rgbd/check-inputs.sh /absolute/example-build/orb-rgbd \
  /absolute/dataset-parent/rgbd_dataset_freiburg1_desk \
  /absolute/orb-install/share/orb-slam3/ORBvoc.txt \
  /absolute/orb-install/share/orb-slam3/settings/TUM1.yaml /absolute/new-input-tests
```

Missing images, corrupt PNG data and malformed timestamp lists must fail before
starting SLAM or creating a results directory. This fixed dataset/calibration
example is not a general camera driver or an input sandbox.

## Measured validation and limits

On 2026-10-07, two runs passed on an EMBER64 `b4f718d` VM with NetBSD 11.0
userland, GCC 12.5, shared OpenCV 5.0.0/Eigen 5.0.1, and libpng 1.6.58.
The four-vCPU VM was shared with other development work. The application ran
at nice 10 with OpenCV limited to one thread and a 600-second external timeout.
The recorded paired image interval was 19.836 seconds; no frames were skipped.

| Measurement | Controlled run A | Controlled run B |
|---|---:|---:|
| Input RGB / depth images | 613 / 595 | 613 / 595 |
| Associated / tracked / exported poses | 573 / 573 / 573 | 573 / 573 / 573 |
| Ground-truth matches | 573 | 573 |
| ATE RMSE, metres | 0.0176194 | 0.0171225 |
| Maximum ATE, metres | 0.0767547 | 0.0678093 |
| Rotation RMSE, degrees | 2.18022 | 2.30989 |
| Preflight, seconds | 5.475 | 4.479 |
| Startup-through-shutdown wall time, seconds | 40.861 | 45.197 |
| Tracking calls, seconds | 32.923 | 36.626 |
| Shutdown, seconds | 0.0125 | 0.0340 |
| Peak RSS, KiB | 671608 | 669276 |
| Native threads before / after | 1 / 1 | 1 / 1 |

The fixed-scale metric self-test, truncated-export regression and all three
negative-input cases passed. Installed linkage used one OpenCV provider and
the private ORB libraries, without GUI dependencies.

An earlier run without an explicit DUtils seed tracked only 487/573 frames
and created then merged another map. Its saved history repeated 83 timestamps;
the parser rejected it, and its tracking fraction independently failed 90%.
Ports now marks unavailable poses lost with the current timestamp. That fix
does not retroactively accept the failed run. The two controlled passes use
seed zero selected without tuning, but do not establish that seeding caused
or eliminated the earlier failure. Background scheduling remains variable;
these results are numerical repetitions, not bitwise reproducibility or a
stability guarantee. The successful runs did not log a loop closure or GBA
cancellation; Ports tests those cancellation mechanics separately.

[Provenance](PROVENANCE.md) records source ownership, upstream pins and licenses.

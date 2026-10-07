# Software BPSK channel with GNU Radio

This C++ example sends a finite message through GNU Radio's channel model,
adds Gaussian noise and a known carrier frequency offset, then recovers the
message with carrier correction, a matched filter and binary decisions.
It measures bit errors rather than merely checking that a graph starts.

The application belongs to EmberBSD Examples. Build recipes and portability
patches belong to the [GNU Radio source profile in Ports](https://github.com/neonix20b/EmberBSD-Ports/tree/main/probes/gnuradio).
The original fixtures and application were developed with AI assistance.

## Build and run

First build GNU Radio 3.10.12.0 with the Ports profile and its shared FFTW
3.3.11, VOLK 3.3.0 and fmt 12.2.0 dependencies. Use the same C++ toolchain
and ABI for this example. No Python runtime or graphical desktop is required
by the C++ application; the upstream library build uses Python generators.

From the Examples checkout, replace these paths with the actual installations:

```sh
export PATH=/usr/pkg/bin:/usr/bin:/bin:/usr/sbin:/sbin
radio=/absolute/gnuradio-work/install
volk=/absolute/volk-work/install
fftw=/absolute/fftw-work/install
work=/absolute/new/radio-example
cmake -S robotics/gnuradio-channel -B "$work" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=/usr/bin/c++ \
  -DCMAKE_PREFIX_PATH="$radio;$volk;$fftw;/usr/pkg"
cmake --build "$work" --parallel 1
export LD_LIBRARY_PATH="$radio/lib:$volk/lib:$fftw/lib:/usr/pkg/lib"
ctest --test-dir "$work" --verbose
```

CTest creates separate preference, cache, state and VOLK configuration paths
beneath the build directory. It does not change HOME or system settings.
Both cases have a timeout; a failed numerical check returns nonzero.

The normal case sends 2,048 payload bits with a 128-bit preamble and trailing
guard symbols. The model uses eight samples per symbol, noise amplitude 0.04,
unit sample-rate ratio and a carrier offset of 0.013 cycles per sample.
The receiver corrects this known offset and averages each eight-sample symbol.
It uses a fixed four-sample timing phase derived from the channel model's
MMSE interpolator and the causal averaging filter. Without this phase shift,
the averaging window straddles two symbols and loses transitions in noise.
Only the preamble selects the small integer symbol delay; payload bits do not
choose alignment or decision thresholds. The payload must contain no errors.
A second fresh graph with the same seed must produce the same decisions.

The `--no-correction` case deliberately omits carrier correction and requires
more than one third of the payload bits to be wrong. A zero exit status means
this negative control observed the expected failure of reception.
Each case reports recovered symbol count, delay, preamble errors, payload BER
and elapsed wall time, including scheduler startup and shutdown.

## Native verification

On 2026-10-07 the ARM64 EmberBSD/NetBSD 11 VM with GCC 12.5.0 passed both
cases: 2,048/2,048 payload bits recovered, zero preamble errors, and identical
decisions after a fresh graph restart. Without carrier correction, 1,057 of
2,048 bits were wrong (BER 0.516113). The corrected graph recovered 2,238
symbols including guards, with zero integer symbol delay.

The initial source omitted the four-sample timing phase and failed with 537
payload errors. The same numerical checks caught the defect and passed after
the timing correction; the success threshold was not relaxed.
GNU Radio's shared-memory factory probe rejected SysV mappings under this
VM's existing segment limits and selected its working POSIX `shm_open`
factory. No system IPC limits were changed.

## Scope

This is a bounded software channel with deterministic fixtures. It does not
estimate an unknown carrier offset, recover an independent symbol clock,
drive a physical radio or establish real-time performance. SoapySDR and a
device-specific module are separate integration work. No RF is transmitted.

## License

Original example code is [MIT licensed](LICENSE). GNU Radio is a separate
GPL-3.0-or-later dependency; distributing a linked executable requires
compliance with its license and the licenses of the linked dependencies.
Ports preserves their upstream notices and source provenance.

// SPDX-License-Identifier: MIT
// Copyright (c) 2026 EmberBSD contributors
// AI-assisted software radio demonstration; original deterministic fixtures.
#include <gnuradio/top_block.h>
#include <gnuradio/blocks/complex_to_real.h>
#include <gnuradio/blocks/rotator_cc.h>
#include <gnuradio/blocks/skiphead.h>
#include <gnuradio/blocks/vector_sink.h>
#include <gnuradio/blocks/vector_source.h>
#include <gnuradio/channels/channel_model.h>
#include <gnuradio/digital/binary_slicer_fb.h>
#include <gnuradio/filter/fir_filter_blk.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>
#include <unistd.h>

namespace {
constexpr unsigned samples_per_symbol = 8;
constexpr unsigned preamble = 128;
constexpr unsigned payload = 2048;
constexpr unsigned tail = 64;
constexpr double frequency_offset = 0.013;
constexpr double pi = 3.14159265358979323846;
// At mu=0 channel_model's eight-tap MMSE interpolator advances three
// samples. The causal eight-sample average at n=0 would straddle adjacent
// symbols equally. Sampling four samples later centers its full window.
constexpr unsigned sampling_phase = 4;

void require(bool condition, const char* message)
{
    if (!condition)
        throw std::runtime_error(message);
}

std::vector<std::uint8_t> message()
{
    std::vector<std::uint8_t> bits(preamble + payload + tail);
    std::uint32_t state = 0x61736e74;
    for (auto& bit : bits) {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        bit = static_cast<std::uint8_t>((state >> 19) & 1);
    }
    return bits;
}

std::vector<std::uint8_t> receive(const std::vector<std::uint8_t>& bits,
                                bool correction)
{
    std::vector<gr_complex> samples;
    samples.reserve(bits.size() * samples_per_symbol);
    for (auto bit : bits)
        samples.insert(samples.end(), samples_per_symbol,
                       gr_complex(bit ? 1.0f : -1.0f, 0.0f));

    auto graph = gr::make_top_block("EmberBSD software BPSK channel");
    auto source = gr::blocks::vector_source_c::make(samples, false);
    auto channel = gr::channels::channel_model::make(
        0.04, frequency_offset, 1.0, {gr_complex(1.0f, 0.0f)}, 42, true);
    auto carrier = gr::blocks::rotator_cc::make(
        correction ? -2 * pi * frequency_offset : 0.0);
    auto timing = gr::blocks::skiphead::make(sizeof(gr_complex), sampling_phase);
    auto matched_filter = gr::filter::fir_filter_ccf::make(
        samples_per_symbol,
        std::vector<float>(samples_per_symbol, 1.0f / samples_per_symbol));
    auto real = gr::blocks::complex_to_real::make();
    auto slicer = gr::digital::binary_slicer_fb::make();
    auto sink = gr::blocks::vector_sink_b::make();
    graph->connect(source, 0, channel, 0);
    graph->connect(channel, 0, carrier, 0);
    graph->connect(carrier, 0, timing, 0);
    graph->connect(timing, 0, matched_filter, 0);
    graph->connect(matched_filter, 0, real, 0);
    graph->connect(real, 0, slicer, 0);
    graph->connect(slicer, 0, sink, 0);
    // Finite source: run() must drain the graph and join its scheduler threads.
    graph->run();
    return sink->data();
}

struct Result {
    unsigned errors;
    unsigned preamble_errors;
    int delay;
};

Result compare(const std::vector<std::uint8_t>& sent,
               const std::vector<std::uint8_t>& received)
{
    require(received.size() >= preamble + payload + 4, "truncated output stream");
    require(received.size() <= sent.size() + 4, "unexpected extra output samples");
    for (auto bit : received)
        require(bit <= 1, "nonbinary slicer output");
    // Determine the small integer delay from known preamble only. Payload
    // bits are never used to select the delay or the decision threshold.
    unsigned best = std::numeric_limits<unsigned>::max();
    int delay = 0;
    for (int candidate = -4; candidate <= 4; ++candidate) {
        unsigned errors = 0;
        for (int i = 16; i < static_cast<int>(preamble) - 16; ++i)
            errors += sent[i] != received[i + candidate];
        if (errors < best) {
            best = errors;
            delay = candidate;
        }
    }
    unsigned errors = 0;
    for (unsigned i = preamble; i < preamble + payload; ++i)
        errors += sent[i] != received[static_cast<int>(i) + delay];
    return {errors, best, delay};
}
} // namespace

int main(int argc, char** argv)
{
    try {
        require(argc == 1 || (argc == 2 && std::string(argv[1]) == "--no-correction"),
                "Usage: ember-radio-channel [--no-correction]");
        const bool correction = argc == 1;
        // A broken scheduler must not leave this bounded demonstration running.
        alarm(40);
        const auto start = std::chrono::steady_clock::now();
        const auto sent = message();
        const auto received = receive(sent, correction);
        const auto result = compare(sent, received);
        if (correction && (result.preamble_errors || result.errors))
            std::cerr << "reception failed: symbols=" << received.size()
                      << " delay=" << result.delay << " preamble_errors=" << result.preamble_errors
                      << " payload_errors=" << result.errors << '\n';
        if (correction) {
            require(result.preamble_errors == 0, "preamble recovery failed");
            require(result.errors == 0, "payload recovery failed");
            const auto repeated = receive(sent, true);
            require(repeated == received, "restart with fixed seed changed output");
        } else {
            require(result.errors > payload / 3, "negative control did not expose carrier error");
        }
        const double elapsed = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - start).count();
        alarm(0);
        std::cout << "carrier_correction=" << (correction ? "on" : "off")
                  << " samples_per_symbol=" << samples_per_symbol
                  << " sampling_phase=" << sampling_phase
                  << " frequency_offset=" << frequency_offset
                  << " received_symbols=" << received.size()
                  << " delay_symbols=" << result.delay
                  << " preamble_errors=" << result.preamble_errors
                  << " payload_bits=" << payload
                  << " bit_errors=" << result.errors
                  << " ber=" << static_cast<double>(result.errors) / payload
                  << " elapsed_seconds=" << elapsed << '\n';
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return EXIT_FAILURE;
    }
}

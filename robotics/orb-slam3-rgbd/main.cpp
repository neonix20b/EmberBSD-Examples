// SPDX-License-Identifier: MIT
#include "dataset.hpp"
#include "png-reader.h"
#include <System.h>
#include <Thirdparty/DBoW2/DUtils/Random.h>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <sys/resource.h>
#ifdef __NetBSD__
#include <sys/types.h>
#include <sys/sysctl.h>
#include <unistd.h>
#endif

using Clock = std::chrono::steady_clock;
namespace fs = std::filesystem;

static void require(bool condition, const std::string &message)
{
    if (!condition) throw std::runtime_error(message);
}

static void save_report(const fs::path &output, const std::string &report)
{
    std::ofstream summary(output / "metrics.txt");
    summary << report;
    summary.close();
    require(summary.good(), "metrics output write failed");
}

static int thread_count()
{
#ifdef __NetBSD__
    kinfo_proc2 process{};
    int mib[] = {CTL_KERN, KERN_PROC2, KERN_PROC_PID, getpid(), sizeof(process), 1};
    size_t size = sizeof(process);
    require(sysctl(mib, 6, &process, &size, nullptr, 0) == 0 && size == sizeof(process), "cannot obtain thread count");
    return process.p_nlwps;
#else
    return -1;
#endif
}

struct Image {
    std::unique_ptr<void, decltype(&std::free)> bytes{nullptr, &std::free};
    cv::Mat matrix;
    Image(const fs::path &path, bool depth)
    {
        void *buffer = nullptr;
        char error[256]{};
        require(fs::is_regular_file(path), "missing image: " + path.string());
        const bool valid = read_tum_png(path.c_str(), depth, &buffer, error, sizeof(error));
        require(valid, "invalid PNG: " + path.string() + ": " + error);
        bytes.reset(buffer);
        matrix = cv::Mat(480, 640, depth ? CV_16UC1 : CV_8UC3, bytes.get());
    }
};

struct Session {
    ORB_SLAM3::System system;
    bool stopped = false;
    Session(const std::string &vocabulary, const std::string &settings)
        : system(vocabulary, settings, ORB_SLAM3::System::RGBD, false) {}
    void stop() { if (!stopped) { system.Shutdown(); stopped = true; } }
    ~Session() { stop(); }
};

int main(int argc, char **argv)
{
    fs::path results;
    try {
        if (argc == 2 && std::string(argv[1]) == "--self-test") {
            dataset_self_test();
            std::cout << "PASS dataset association and metric SE(3) alignment\n";
            return 0;
        }
        require(argc == 5 || argc == 6,
            "usage: orb-rgbd DATASET VOCABULARY SETTINGS NEW_OUTPUT [--validate-only]");
        const bool validate_only = argc == 6 && std::string(argv[5]) == "--validate-only";
        require(argc == 5 || validate_only, "unknown option");
        const fs::path root(argv[1]), vocabulary(argv[2]), settings(argv[3]), output(argv[4]);
        require(fs::is_directory(root), "missing dataset directory");
        require(fs::is_regular_file(vocabulary) && fs::file_size(vocabulary) > 1000000, "missing or truncated vocabulary");
        require(fs::is_regular_file(settings), "missing settings");
        require(!fs::exists(output), "output directory already exists");
        cv::setNumThreads(1);
        cv::setRNGSeed(0);
        DUtils::Random::SeedRandOnce(0);
        cv::FileStorage calibration(settings.string(), cv::FileStorage::READ);
        require(calibration.isOpened() && static_cast<int>(calibration["Camera.width"]) == 640 &&
            static_cast<int>(calibration["Camera.height"]) == 480 &&
            static_cast<int>(calibration["Camera.RGB"]) == 1 &&
            std::abs(static_cast<double>(calibration["RGBD.DepthMapFactor"]) - 5000) < 1e-9,
            "this example requires original TUM1 RGB/uint16-depth calibration");
        calibration.release();
        const auto rgb = read_images(root / "rgb.txt");
        const auto depth = read_images(root / "depth.txt");
        const auto pairs = associate(rgb, depth);
        require(pairs.size() >= 100 && pairs.size() >= 0.90 * depth.size(), "insufficient RGB/depth associations");
        const auto truth = read_poses(root / "groundtruth.txt");
        // Validate every selected input before creating SLAM worker threads.
        const auto preflight_start = Clock::now();
        for (const Pair &pair : pairs) {
            Image color(root / pair.rgb.path, false);
            Image distance(root / pair.depth.path, true);
        }
        const double preflight_seconds = std::chrono::duration<double>(Clock::now() - preflight_start).count();
        std::cout << "validated rgb=" << rgb.size() << " depth=" << depth.size()
            << " pairs=" << pairs.size() << " preflight_seconds=" << preflight_seconds << '\n';
        if (validate_only) return 0;
        require(fs::create_directory(output), "cannot create output directory");
        results = output;
        const int threads_before = thread_count();
        const auto start = Clock::now();
        Session slam(vocabulary.string(), settings.string());
        const double startup_seconds = std::chrono::duration<double>(Clock::now() - start).count();
        const auto tracking_start = Clock::now();
        size_t tracked = 0;
        std::vector<double> input_times, tracked_times;
        double tracking_seconds = 0;
        std::ofstream frames(output / "frames.tsv");
        require(frames.good(), "cannot write frame results");
        frames << "timestamp\tdepth_timestamp\tstate\ttracking_seconds\n" << std::setprecision(17);
        for (const Pair &pair : pairs) {
            // Follow source timestamps when processing is faster than the data.
            // Slow processing never invents or skips frames to catch up.
            std::this_thread::sleep_until(tracking_start + std::chrono::duration_cast<Clock::duration>(
                std::chrono::duration<double>(pair.rgb.time - pairs.front().rgb.time)));
            Image color(root / pair.rgb.path, false);
            Image distance(root / pair.depth.path, true);
            const auto begin = Clock::now();
            const auto pose = slam.system.TrackRGBD(color.matrix, distance.matrix, pair.rgb.time);
            const double seconds = std::chrono::duration<double>(Clock::now() - begin).count();
            tracking_seconds += seconds;
            const int state = slam.system.GetTrackingState();
            input_times.push_back(pair.rgb.time);
            if (state == ORB_SLAM3::Tracking::OK && pose.matrix().allFinite()) {
                ++tracked;
                tracked_times.push_back(pair.rgb.time);
            }
            frames << pair.rgb.time << '\t' << pair.depth.time << '\t' << state << '\t' << seconds << '\n';
            require(frames.good(), "frame output write failed");
        }
        frames.close();
        const auto shutdown_start = Clock::now();
        slam.stop();
        const double shutdown_seconds = std::chrono::duration<double>(Clock::now() - shutdown_start).count();
        const double wall_seconds = std::chrono::duration<double>(Clock::now() - start).count();
        const int threads_after = thread_count();
        const double fraction = static_cast<double>(tracked) / pairs.size();
        struct rusage usage{};
        require(getrusage(RUSAGE_SELF, &usage) == 0, "cannot obtain peak RSS");
        long peak_rss_kib = usage.ru_maxrss;
#ifdef __APPLE__
        peak_rss_kib /= 1024;
#endif
        std::ostringstream report;
        report << std::setprecision(9)
            << "rgb_input_frames=" << rgb.size() << '\n' << "depth_input_frames=" << depth.size() << '\n'
            << "association_fraction=" << static_cast<double>(pairs.size()) / depth.size() << '\n'
            << "paired_duration_seconds=" << pairs.back().rgb.time - pairs.front().rgb.time << '\n'
            << "frames=" << pairs.size() << '\n' << "tracked=" << tracked << '\n'
            << "tracking_fraction=" << fraction << '\n'
            << "dutils_seed=0\nopencv_seed=0\n"
            << "preflight_seconds=" << preflight_seconds << '\n'
            << "startup_seconds=" << startup_seconds << '\n' << "tracking_call_seconds=" << tracking_seconds << '\n'
            << "shutdown_seconds=" << shutdown_seconds << '\n' << "wall_seconds=" << wall_seconds << '\n'
            << "threads_before=" << threads_before << '\n' << "threads_after=" << threads_after << '\n';
        // Keep measurements even when trajectory export or evaluation fails.
        save_report(output, report.str() + "peak_rss_kib=" + std::to_string(peak_rss_kib) +
            "\nevaluation_status=not_completed\n");
        require(threads_before < 0 || threads_after == threads_before, "SLAM threads survived Shutdown");
        require(tracked >= 3, "SLAM did not establish a trajectory");
        slam.system.SaveTrajectoryTUM((output / "trajectory.txt").string());
        slam.system.SaveKeyFrameTrajectoryTUM((output / "keyframes.txt").string());
        const auto estimated = read_poses(output / "trajectory.txt");
        verify_export(estimated, input_times, tracked_times);
        const auto metric = evaluate(estimated, truth);
        require(getrusage(RUSAGE_SELF, &usage) == 0, "cannot obtain final peak RSS");
        peak_rss_kib = usage.ru_maxrss;
#ifdef __APPLE__
        peak_rss_kib /= 1024;
#endif
        report << "peak_rss_kib=" << peak_rss_kib << '\n'
            << "exported_poses=" << estimated.size() << '\n'
            << "exported_ok_frames=" << tracked_times.size() << '\n'
            << "groundtruth_matches=" << metric.matches << '\n'
            << "ate_rmse_m=" << metric.rmse << '\n' << "ate_max_m=" << metric.maximum << '\n'
            << "rotation_rmse_degrees=" << metric.rotation_rmse_degrees << '\n'
            << "alignment_scale=1\nevaluation_status=complete\n";
        std::cout << report.str();
        save_report(output, report.str());
        require(fraction >= 0.90, "tracking fraction below predeclared 90% threshold");
        require(metric.rmse <= 0.10 && metric.maximum <= 0.30, "trajectory exceeds predeclared metric error bounds");
        std::cout << "PASS complete TUM fr1/desk RGB-D trajectory\n";
        return 0;
    } catch (const std::exception &error) {
        if (!results.empty()) {
            std::ofstream failure(results / "failure.txt");
            failure << error.what() << '\n';
        }
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}

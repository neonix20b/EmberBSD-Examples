// SPDX-License-Identifier: MIT
#include "dataset.hpp"
#include <Eigen/SVD>
#include <algorithm>
#include <cmath>
#include <fstream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <tuple>

static void require(bool condition, const std::string &message)
{
    if (!condition) throw std::runtime_error(message);
}

template<class Reader>
static void lines(const std::filesystem::path &path, Reader reader)
{
    std::ifstream input(path);
    require(input.good(), "cannot open input: " + path.string());
    std::string line;
    size_t number = 0;
    while (std::getline(input, line)) {
        ++number;
        std::istringstream data(line);
        data >> std::ws;
        if (data.eof() || data.peek() == '#') continue;
        require(reader(data), "invalid input line " + std::to_string(number) + ": " + path.string());
        std::string extra;
        require(!(data >> extra), "unexpected field: " + path.string());
    }
    require(!input.bad(), "input read error: " + path.string());
}

std::vector<ImageEntry> read_images(const std::filesystem::path &path)
{
    std::vector<ImageEntry> result;
    lines(path, [&](std::istringstream &line) {
        ImageEntry entry;
        if (!(line >> entry.time >> entry.path) || !std::isfinite(entry.time)) return false;
        std::filesystem::path name(entry.path);
        if (name.is_absolute() || name.extension() != ".png") return false;
        for (const auto &component : name)
            if (component == ".." || component == ".") return false;
        if (!result.empty() && entry.time <= result.back().time) return false;
        result.push_back(entry);
        return true;
    });
    require(!result.empty(), "empty image list: " + path.string());
    return result;
}

std::vector<Pair> associate(const std::vector<ImageEntry> &rgb, const std::vector<ImageEntry> &depth)
{
    // TUM-style greedy minimum time difference, with no reused image.
    std::vector<std::tuple<double, size_t, size_t>> candidates;
    for (size_t i = 0; i < rgb.size(); ++i) {
        const auto first = std::lower_bound(depth.begin(), depth.end(), rgb[i].time - 0.020,
            [](const ImageEntry &entry, double time) { return entry.time < time; });
        for (auto entry = first; entry != depth.end() && entry->time <= rgb[i].time + 0.020; ++entry)
            candidates.emplace_back(std::abs(rgb[i].time - entry->time), i, entry - depth.begin());
    }
    std::sort(candidates.begin(), candidates.end());
    std::vector<bool> used_rgb(rgb.size()), used_depth(depth.size());
    std::vector<Pair> result;
    for (const auto &[difference, i, j] : candidates) {
        (void)difference;
        if (!used_rgb[i] && !used_depth[j]) {
            result.push_back({rgb[i], depth[j]});
            used_rgb[i] = used_depth[j] = true;
        }
    }
    std::sort(result.begin(), result.end(), [](const Pair &a, const Pair &b) { return a.rgb.time < b.rgb.time; });
    return result;
}

std::vector<Pose> read_poses(const std::filesystem::path &path)
{
    std::vector<Pose> result;
    lines(path, [&](std::istringstream &line) {
        Pose pose;
        double x, y, z, w;
        if (!(line >> pose.time >> pose.position.x() >> pose.position.y() >> pose.position.z() >> x >> y >> z >> w))
            return false;
        pose.rotation = Eigen::Quaterniond(w, x, y, z);
        if (!std::isfinite(pose.time) || !pose.position.allFinite() || !pose.rotation.coeffs().allFinite() ||
            std::abs(pose.rotation.norm() - 1) > 0.01) return false;
        if (!result.empty() && pose.time <= result.back().time) return false;
        pose.rotation.normalize();
        result.push_back(pose);
        return true;
    });
    require(result.size() >= 3, "trajectory requires at least three poses: " + path.string());
    return result;
}

void verify_export(const std::vector<Pose> &estimated, const std::vector<double> &inputs,
    const std::vector<double> &tracked)
{
    // Upstream writes six decimal places. One microsecond allows rounding,
    // not association with a different camera frame.
    auto input_index = [&](double time) {
        auto next = std::lower_bound(inputs.begin(), inputs.end(), time);
        auto nearest = next;
        if (next != inputs.begin() && (next == inputs.end() ||
            time - *(next - 1) < *next - time)) nearest = next - 1;
        require(nearest != inputs.end() && std::abs(*nearest - time) <= 1e-6,
            "export timestamp is not a selected RGB frame");
        return static_cast<size_t>(nearest - inputs.begin());
    };
    std::vector<bool> exported(inputs.size());
    for (const Pose &pose : estimated) {
        const size_t index = input_index(pose.time);
        require(!exported[index], "export reused a selected RGB timestamp");
        exported[index] = true;
    }
    for (double time : tracked)
        require(exported[input_index(time)], "export omitted an OK tracked frame");
}

Metrics evaluate(const std::vector<Pose> &estimated, const std::vector<Pose> &truth)
{
    std::vector<std::pair<Pose, Pose>> pairs;
    for (const Pose &pose : estimated) {
        auto next = std::lower_bound(truth.begin(), truth.end(), pose.time,
            [](const Pose &entry, double time) { return entry.time < time; });
        auto nearest = next;
        if (next != truth.begin() && (next == truth.end() ||
            pose.time - (next - 1)->time < next->time - pose.time)) nearest = next - 1;
        if (nearest != truth.end() && std::abs(nearest->time - pose.time) <= 0.020)
            pairs.emplace_back(pose, *nearest);
    }
    require(pairs.size() >= 3 && pairs.size() >= estimated.size() * 0.95, "insufficient ground-truth timestamp coverage");
    Eigen::Vector3d from = Eigen::Vector3d::Zero(), to = from;
    for (const auto &pair : pairs) { from += pair.first.position; to += pair.second.position; }
    from /= pairs.size(); to /= pairs.size();
    Eigen::Matrix3d covariance = Eigen::Matrix3d::Zero();
    for (const auto &pair : pairs)
        covariance += (pair.first.position - from) * (pair.second.position - to).transpose();
    Eigen::JacobiSVD<Eigen::Matrix3d> svd(covariance, Eigen::ComputeFullU | Eigen::ComputeFullV);
    require(svd.singularValues()[1] > 1e-8, "degenerate trajectory alignment");
    Eigen::Matrix3d correction = Eigen::Matrix3d::Identity();
    correction(2, 2) = (svd.matrixV() * svd.matrixU().transpose()).determinant() < 0 ? -1 : 1;
    const Eigen::Matrix3d rotation = svd.matrixV() * correction * svd.matrixU().transpose();
    const Eigen::Vector3d translation = to - rotation * from;
    double square = 0, maximum = 0, angle_square = 0;
    for (const auto &pair : pairs) {
        const double error = (rotation * pair.first.position + translation - pair.second.position).norm();
        square += error * error;
        maximum = std::max(maximum, error);
        const Eigen::Matrix3d delta = pair.second.rotation.toRotationMatrix().transpose() *
            rotation * pair.first.rotation.toRotationMatrix();
        const double angle = Eigen::AngleAxisd(delta).angle() * 180 / std::acos(-1.0);
        angle_square += angle * angle;
    }
    return {pairs.size(), std::sqrt(square / pairs.size()), maximum, std::sqrt(angle_square / pairs.size())};
}

void dataset_self_test()
{
    const auto pairs = associate({{1.0, "a"}, {1.03, "b"}, {2.0, "c"}}, {{1.018, "d"}, {2.01, "e"}});
    require(pairs.size() == 2 && pairs[0].rgb.path == "b" && pairs[1].rgb.path == "c", "timestamp association regression");
    std::vector<Pose> estimated, truth;
    const Eigen::Quaterniond rotation(Eigen::AngleAxisd(0.6, Eigen::Vector3d(1, 2, 3).normalized()));
    const Eigen::Vector3d offset(4, -1, 3);
    for (int i = 0; i != 10; ++i) {
        const Eigen::Vector3d point(std::sin(i), std::cos(i), i * 0.3);
        estimated.push_back({i * 0.04, point, Eigen::Quaterniond::Identity()});
        truth.push_back({i * 0.04, rotation * point + offset, rotation});
    }
    const auto rigid = evaluate(estimated, truth);
    require(rigid.rmse < 1e-12 && rigid.maximum < 1e-12 &&
        rigid.rotation_rmse_degrees < 1e-10, "rigid alignment regression");
    std::vector<double> times;
    for (const auto &pose : estimated) times.push_back(pose.time);
    verify_export(estimated, times, times);
    bool rejected = false;
    try {
        verify_export(std::vector<Pose>(estimated.begin(), estimated.begin() + 3), times, times);
    } catch (const std::runtime_error &) { rejected = true; }
    require(rejected, "short trajectory subset must not pass export coverage");
    for (auto &pose : estimated) pose.position *= 2;
    require(evaluate(estimated, truth).rmse > 0.5, "metric alignment must not fit scale");
}

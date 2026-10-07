// SPDX-License-Identifier: MIT
#pragma once
#include <Eigen/Core>
#include <Eigen/Geometry>
#include <filesystem>
#include <string>
#include <vector>

struct ImageEntry { double time; std::string path; };
struct Pair { ImageEntry rgb, depth; };
struct Pose { double time; Eigen::Vector3d position; Eigen::Quaterniond rotation; };
struct Metrics { size_t matches; double rmse, maximum, rotation_rmse_degrees; };
std::vector<ImageEntry> read_images(const std::filesystem::path &);
std::vector<Pair> associate(const std::vector<ImageEntry> &, const std::vector<ImageEntry> &);
std::vector<Pose> read_poses(const std::filesystem::path &);
Metrics evaluate(const std::vector<Pose> &, const std::vector<Pose> &);
void verify_export(const std::vector<Pose> &, const std::vector<double> &inputs,
    const std::vector<double> &tracked);
void dataset_self_test();

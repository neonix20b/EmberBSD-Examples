#include <chrono>
#include <cstdio>
#include <fstream>
#include <functional>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <rclcpp/rclcpp.hpp>
#include "ember_zenoh_bridge/msg/state.hpp"
#include "ember_zenoh_bridge/msg/command.hpp"
#include "ember_zenoh_bridge/msg/ack.hpp"
#include "protocol.h"

namespace msg = ember_zenoh_bridge::msg;
using Clock = std::chrono::steady_clock;

class Probe : public rclcpp::Node {
public:
    Probe() : Node("ember_robot_probe") {
        auto qos = rclcpp::QoS(10).reliable().durability_volatile();
        pub_ = create_publisher<msg::Command>("ember/command", qos);
        states_ = create_subscription<msg::State>("ember/state", qos,
            [this](msg::State::ConstSharedPtr state) { state_ = *state; received_ = Clock::now(); });
        acks_ = create_subscription<msg::Ack>("ember/ack", qos,
            [this](msg::Ack::ConstSharedPtr ack) { ack_ = *ack; have_ack_ = true; });
    }
    void run(const std::string &mode, const char *file) {
        wait([this] { return state_.boot_id && pub_->get_subscription_count() &&
            received_ + std::chrono::milliseconds(500) > Clock::now(); }, "fresh state/discovery");
        const auto baseline = state_.applied_count;
        const auto boot = state_.boot_id;
        if (mode == "--reconnect") {
            std::ifstream input(file, std::ios::binary);
            uint8_t wire[ROBOT_WIRE_SIZE]; robot_frame old{};
            input.read(reinterpret_cast<char *>(wire), sizeof(wire));
            if (!input || input.peek() != EOF || robot_decode(&old, wire, sizeof(wire)))
                throw std::runtime_error("Invalid saved command");
            if (old.boot != boot) throw std::runtime_error("Controller restarted during reconnect test");
            send(old, ROBOT_EXPIRED, baseline);
        } else if (std::ifstream(file).good()) {
            throw std::runtime_error("Refusing to overwrite saved command");
        }
        if (state_.command_id == std::numeric_limits<uint64_t>::max() ||
            baseline == std::numeric_limits<uint32_t>::max())
            throw std::runtime_error("Counter exhausted");
        robot_frame command{};
        command.kind = ROBOT_COMMAND; command.boot = boot;
        command.stamp_ms = state_.device_ms;
        command.command_id = state_.command_id + 1;
        command.setpoint = 25000;
        send(command, ROBOT_OK, baseline + 1);
        wait([&] { return state_.boot_id == boot && state_.applied_count == baseline + 1 &&
            state_.setpoint_millidegrees == 25000; }, "applied state");
        if (mode == "--save") {
            uint8_t wire[ROBOT_WIRE_SIZE]; robot_encode(wire, &command);
            std::ofstream output(file, std::ios::binary);
            output.write(reinterpret_cast<const char *>(wire), sizeof(wire));
            output.close();
            if (!output) throw std::runtime_error("Cannot save command");
        }
        command.stamp_ms = state_.device_ms;
        send(command, ROBOT_REPLAY, baseline + 1);
        if (command.command_id == std::numeric_limits<uint64_t>::max())
            throw std::runtime_error("No remaining test command ID");
        ++command.command_id;
        command.boot ^= 1;
        send(command, ROBOT_BOOT, baseline + 1);
        command.boot = boot; command.stamp_ms = 0;
        send(command, ROBOT_EXPIRED, baseline + 1);
        command.stamp_ms = state_.device_ms; command.setpoint = 100001;
        send(command, ROBOT_RANGE, baseline + 1);
        std::printf("PASS: typed state, command, ack, replay, boot, expiry and range; applied=%u\n",
            baseline + 1);
    }

private:
    void wait(const std::function<bool()> &predicate, const char *operation) {
        const auto deadline = Clock::now() + std::chrono::seconds(20);
        do {
            rclcpp::spin_some(shared_from_this());
            if (predicate()) return;
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        } while (rclcpp::ok() && Clock::now() < deadline);
        throw std::runtime_error(std::string("Timeout: ") + operation);
    }
    void send(const robot_frame &f, uint8_t expected, uint32_t count) {
        msg::Command command;
        command.boot_id = f.boot; command.device_ms = f.stamp_ms;
        command.command_id = f.command_id; command.setpoint_millidegrees = f.setpoint;
        have_ack_ = false;
        pub_->publish(command);
        wait([&] { return have_ack_ && ack_.command_id == f.command_id; }, "command acknowledgement");
        if (ack_.status != expected || ack_.applied_count != count)
            throw std::runtime_error("Wrong acknowledgement status or execution count");
        std::printf("ACK id=%llu status=%u applied=%u\n",
            static_cast<unsigned long long>(f.command_id), ack_.status, ack_.applied_count);
    }
    msg::State state_;
    msg::Ack ack_;
    bool have_ack_ = false;
    Clock::time_point received_{};
    rclcpp::Publisher<msg::Command>::SharedPtr pub_;
    rclcpp::Subscription<msg::State>::SharedPtr states_;
    rclcpp::Subscription<msg::Ack>::SharedPtr acks_;
};

int main(int argc, char **argv) {
    if (argc != 3 || (std::string(argv[1]) != "--save" && std::string(argv[1]) != "--reconnect")) {
        std::fprintf(stderr, "Usage: robot-probe --save|--reconnect COMMAND_FILE\n");
        return 2;
    }
    rclcpp::init(argc, argv);
    int result = 0;
    try { std::make_shared<Probe>()->run(argv[1], argv[2]); }
    catch (const std::exception &e) { std::fprintf(stderr, "%s\n", e.what()); result = 1; }
    rclcpp::shutdown();
    return result;
}

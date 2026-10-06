#include <cstdio>
#include <memory>
#include <stdexcept>
#include <rclcpp/rclcpp.hpp>
#include "ember_zenoh_bridge/msg/state.hpp"
#include "ember_zenoh_bridge/msg/command.hpp"
#include "ember_zenoh_bridge/msg/ack.hpp"
#include "link.h"

namespace msg = ember_zenoh_bridge::msg;

class Bridge : public rclcpp::Node {
public:
    explicit Bridge(const char *endpoint) : Node("ember_zenoh_bridge") {
        auto qos = rclcpp::QoS(10).reliable().durability_volatile();
        state_ = create_publisher<msg::State>("ember/state", qos);
        ack_ = create_publisher<msg::Ack>("ember/ack", qos);
        command_ = create_subscription<msg::Command>("ember/command", qos,
            [this](msg::Command::ConstSharedPtr command) {
                robot_frame f{};
                f.kind = ROBOT_COMMAND;
                f.boot = command->boot_id;
                f.stamp_ms = command->device_ms;
                f.command_id = command->command_id;
                f.setpoint = command->setpoint_millidegrees;
                if (robot_link_put(link_, &f) < 0)
                    RCLCPP_ERROR(get_logger(), "Command not sent; no automatic retry");
            });
        link_ = robot_link_open(endpoint, 0, receive, this);
        if (!link_) throw std::runtime_error("Cannot connect Zenoh peer");
        RCLCPP_INFO(get_logger(), "READY: explicit Zenoh-to-ROS 2 bridge");
    }
    ~Bridge() override { robot_link_close(link_); }

private:
    static void receive(const robot_frame *f, void *context) {
        auto self = static_cast<Bridge *>(context);
        if (f->kind == ROBOT_STATE) {
            msg::State state;
            state.boot_id = f->boot; state.device_ms = f->stamp_ms;
            state.command_id = f->command_id;
            state.measured_millidegrees = f->measured;
            state.setpoint_millidegrees = f->setpoint;
            state.applied_count = f->applied;
            self->state_->publish(state);
        } else if (f->kind == ROBOT_ACK) {
            msg::Ack ack;
            ack.boot_id = f->boot; ack.device_ms = f->stamp_ms;
            ack.command_id = f->command_id; ack.status = f->status;
            ack.setpoint_millidegrees = f->setpoint;
            ack.applied_count = f->applied;
            self->ack_->publish(ack);
        }
    }
    robot_link *link_ = nullptr;
    rclcpp::Publisher<msg::State>::SharedPtr state_;
    rclcpp::Publisher<msg::Ack>::SharedPtr ack_;
    rclcpp::Subscription<msg::Command>::SharedPtr command_;
};

int main(int argc, char **argv) {
    if (argc != 2) {
        std::fprintf(stderr, "Usage: robot-bridge tcp/DEVICE_ADDRESS:PORT\n");
        return 2;
    }
    rclcpp::init(argc, argv);
    int result = 0;
    try {
        auto node = std::make_shared<Bridge>(argv[1]);
        rclcpp::spin(node);
    } catch (const std::exception &e) {
        std::fprintf(stderr, "%s\n", e.what());
        result = 1;
    }
    rclcpp::shutdown();
    return result;
}

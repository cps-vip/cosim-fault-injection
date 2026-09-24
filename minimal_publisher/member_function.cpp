#include <memory>
#include <string>
#include <map>
#include <iostream>
#include <sstream>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"
#include "rclcpp_action/rclcpp_action.hpp"
#include "nav2_msgs/action/navigate_to_pose.hpp"
#include "geometry_msgs/msg/pose_stamped.hpp"
#include "/home/ubuntu/software/HELICS/src/helics/cpp98/helics.hpp"

using namespace std::chrono_literals;
using namespace helicscpp;

class MinimalPublisher : public rclcpp::Node
{
public:
    using NavigateToPose = nav2_msgs::action::NavigateToPose;
    using GoalHandleNavigateToPose = rclcpp_action::ClientGoalHandle<NavigateToPose>;

    MinimalPublisher()
    : Node("minimal_publisher"), count_(0)
    {
        // ROS2 publisher
        publisher_ = this->create_publisher<std_msgs::msg::String>("topic", 10);

        // Create NAV2 action client
        nav_client_ = rclcpp_action::create_client<NavigateToPose>(
            this,
            "navigate_to_pose");

        // HELICS ValueFederate from your config
        fed_ = std::make_unique<ValueFederate>("/home/ubuntu/ros2_ws/ROS2_config_cc.json");
        fed_->registerInterfaces("/home/ubuntu/ros2_ws/ROS2_config_cc.json");

        // Register publications/subscriptions
        int pubCount = fed_->getPublicationCount();
        int subCount = fed_->getInputCount();
        for (int i = 0; i < pubCount; ++i) {
            pubId_["m" + std::to_string(i)] = fed_->getPublication(i);
        }
        for (int i = 0; i < subCount; ++i) {
            Input sub = fed_->getInput(i);
            sub.setDefault("");
            subId_["m" + std::to_string(i)] = sub;
        }

        // Enter HELICS execution mode
        fed_->enterInitializingMode();
        fed_->enterExecutingMode();

        // ROS2 timer to periodically request HELICS time and publish
        timer_ = this->create_wall_timer(100ms, std::bind(&MinimalPublisher::timer_callback, this));
    }

private:
    void goal_response_callback(const GoalHandleNavigateToPose::SharedPtr & goal_handle)
    {
        if (!goal_handle) {
            RCLCPP_ERROR(this->get_logger(), "Goal was rejected by server");
        } else {
            RCLCPP_INFO(this->get_logger(), "Goal accepted by server, waiting for result");
        }
    }

    void feedback_callback(
        GoalHandleNavigateToPose::SharedPtr,
        const std::shared_ptr<const NavigateToPose::Feedback> feedback)
    {
        RCLCPP_DEBUG(this->get_logger(), 
            "Distance remaining: %f", feedback->distance_remaining);
    }

    void result_callback(const GoalHandleNavigateToPose::WrappedResult & result)
    {
        switch (result.code) {
            case rclcpp_action::ResultCode::SUCCEEDED:
                RCLCPP_INFO(this->get_logger(), "Goal succeeded!");
                break;
            case rclcpp_action::ResultCode::ABORTED:
                RCLCPP_ERROR(this->get_logger(), "Goal was aborted");
                break;
            case rclcpp_action::ResultCode::CANCELED:
                RCLCPP_ERROR(this->get_logger(), "Goal was canceled");
                break;
            default:
                RCLCPP_ERROR(this->get_logger(), "Unknown result code");
        }
    }

    void timer_callback()
    {
        std_msgs::msg::String msg;

        // Minimal HELICS time request logic
        static int grantedTime = -1;
        int t = grantedTime + 60; // advance by 60s per callback
        grantedTime = fed_->requestTime(t);

        // Iterate over subscriptions to check for relay trip/fault
        for (auto& [key, sub] : subId_) {
            std::string coords_str = sub.getString(); // get coordinates from CC
            
            if (!coords_str.empty()) {
                RCLCPP_INFO(this->get_logger(), "Received coordinates: '%s'", coords_str.c_str());
                
                // Parse coordinates from string format "x,y"
                if (parse_and_send_nav_goal(coords_str)) {
                    msg.data = "Navigation goal sent to: " + coords_str;
                } else {
                    msg.data = "Failed to parse coordinates: " + coords_str;
                }
                
                RCLCPP_INFO(this->get_logger(), "Publishing: '%s'", msg.data.c_str());
                publisher_->publish(msg);
            }
        }
    }

    bool parse_and_send_nav_goal(const std::string& coords_str)
    {
        try {
            // Parse "x,y" format
            size_t comma_pos = coords_str.find(',');
            if (comma_pos == std::string::npos) {
                RCLCPP_ERROR(this->get_logger(), "Invalid coordinate format: %s", coords_str.c_str());
                return false;
            }

            double x = std::stod(coords_str.substr(0, comma_pos));
            double y = std::stod(coords_str.substr(comma_pos + 1));

            RCLCPP_INFO(this->get_logger(), "Parsed coordinates: x=%f, y=%f", x, y);

            // Wait for action server with retries
            RCLCPP_INFO(this->get_logger(), "Waiting for navigate_to_pose action server...");
            for (int retry = 0; retry < 10; ++retry) {
                if (nav_client_->wait_for_action_server(2s)) {
                    RCLCPP_INFO(this->get_logger(), "Action server found on attempt %d", retry + 1);
                    break;
                }
                if (retry < 9) {
                    RCLCPP_WARN(this->get_logger(), 
                        "Action server not available (attempt %d/10), retrying...", retry + 1);
                } else {
                    RCLCPP_ERROR(this->get_logger(), 
                        "Navigation action server not available after 10 attempts (20 seconds total)");
                    return false;
                }
            }

            // Create goal
            auto goal_msg = NavigateToPose::Goal();
            goal_msg.pose.header.frame_id = "map";
            goal_msg.pose.header.stamp = this->get_clock()->now();
            goal_msg.pose.pose.position.x = x;
            goal_msg.pose.pose.position.y = y;
            goal_msg.pose.pose.position.z = 0.0;
            goal_msg.pose.pose.orientation.x = 0.0;
            goal_msg.pose.pose.orientation.y = 0.0;
            goal_msg.pose.pose.orientation.z = 0.0;
            goal_msg.pose.pose.orientation.w = 1.0;

            // Send goal
            auto send_goal_options = rclcpp_action::Client<NavigateToPose>::SendGoalOptions();
            send_goal_options.goal_response_callback = 
                std::bind(&MinimalPublisher::goal_response_callback, this, std::placeholders::_1);
            send_goal_options.feedback_callback = 
                std::bind(&MinimalPublisher::feedback_callback, this, std::placeholders::_1, std::placeholders::_2);
            send_goal_options.result_callback = 
                std::bind(&MinimalPublisher::result_callback, this, std::placeholders::_1);

            RCLCPP_INFO(this->get_logger(), "Sending navigation goal to (%.2f, %.2f)", x, y);
            nav_client_->async_send_goal(goal_msg, send_goal_options);

            return true;
        } catch (const std::exception& e) {
            RCLCPP_ERROR(this->get_logger(), "Exception parsing coordinates: %s", e.what());
            return false;
        }
    }

    rclcpp::Publisher<std_msgs::msg::String>::SharedPtr publisher_;
    rclcpp::TimerBase::SharedPtr timer_;
    rclcpp_action::Client<NavigateToPose>::SharedPtr nav_client_;
    std::unique_ptr<ValueFederate> fed_;
    std::map<std::string, Publication> pubId_;
    std::map<std::string, Input> subId_;
    size_t count_;
};

int main(int argc, char* argv[])
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<MinimalPublisher>());
    rclcpp::shutdown();
    return 0;
}
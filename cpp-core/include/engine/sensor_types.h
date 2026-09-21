#pragma once

// Sensor events consumed by the navigation engine. All of them are independent of
// any operating system or sensor API: a USB IMU driver, a ROS bridge, a file replay
// or the Android sensor stack only have to produce these three structs.
//
// Time is seconds on ONE monotonic clock shared by every stream; the origin is
// arbitrary. IMU axes are the engine's native body frame, FRD (x forward, y right,
// z down); the CSV reader converts from the more common FLU on the way in.

#include <limits>
#include <variant>

#include "common/types.h"

namespace gati {

constexpr double kNoValue = std::numeric_limits<double>::quiet_NaN();

struct ImuSample {
    double t{0.0};
    Vector3d accel{};   // specific force, m/s^2 (a resting, level IMU reads z = -9.8)
    Vector3d gyro{};    // angular rate, rad/s
    Vector3d mag{};     // microtesla; carried through but not used by the filter
    bool hasMag{false};
};

struct GnssFix {
    double t{0.0};
    double lat{0.0};              // degrees
    double lon{0.0};              // degrees
    double alt{kNoValue};         // metres above the ellipsoid or MSL, NaN = unknown
    double speed{kNoValue};       // ground speed, m/s, NaN = unknown
    double course{kNoValue};      // degrees clockwise from north, NaN = unknown
    double accuracy{5.0};         // 1-sigma horizontal position error per axis, m
};

struct TruthPoint {
    double t{0.0};
    double lat{0.0};              // degrees
    double lon{0.0};              // degrees
};

using SensorEvent = std::variant<ImuSample, GnssFix, TruthPoint>;

inline double eventTime(const SensorEvent& e) {
    return std::visit([](const auto& v) { return v.t; }, e);
}

}  // namespace gati

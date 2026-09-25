#pragma once

// Scripted vehicle trajectories with the IMU, GNSS and truth streams a perfect (or
// deliberately noisy) sensor set would produce. Used by the unit tests and by the
// 200 Hz benchmark; it is the only place where the engine's own kinematic
// conventions are re-derived, so it doubles as an independent physics check.

#include <cstdint>
#include <vector>

#include "engine/types.h"
#include "engine/sensor_types.h"

namespace gati {

struct Maneuver {
    double duration{0.0};       // s
    double accel{0.0};          // m/s^2 along the vehicle
    double yawRateDeg{0.0};     // deg/s, clockwise positive (heading rate)
};

struct SyntheticConfig {
    double lat0Deg{52.4};
    double lon0Deg{-1.5};
    double alt0{100.0};
    double heading0Deg{0.0};
    double speed0{0.0};
    double imuRateHz{200.0};
    double gnssRateHz{1.0};     // 0 = no GNSS events
    double truthRateHz{10.0};   // 0 = no truth events
    double gnssAccuracy{2.0};   // reported 1-sigma, m
    std::vector<Maneuver> plan;

    // Error injection (all zero = a perfect sensor set).
    double accelNoiseStd{0.0};  // per-sample, m/s^2
    double gyroNoiseStd{0.0};   // per-sample, rad/s
    Vector3d accelBias{};       // added to the FRD accelerometer, m/s^2
    Vector3d gyroBias{};        // added to the FRD gyro, rad/s
    double gnssPosNoiseStd{0.0};  // per-axis position noise on fixes, m
    std::uint32_t seed{1};
};

struct SyntheticDrive {
    std::vector<SensorEvent> events;   // time ordered: IMU, then GNSS, then truth at equal times
    double duration{0.0};
    double distance{0.0};              // path length, m
};

SyntheticDrive generateDrive(const SyntheticConfig& config);

}  // namespace gati

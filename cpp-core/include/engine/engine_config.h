#pragma once

// Every tunable of the navigation engine in one place (the C++ counterpart of the
// Dart core's nav_config.dart). Nothing under src/engine hard-codes a threshold.
//
// Noise values are continuous-time densities, so the same configuration is valid
// at 10 Hz and at 200 Hz: a per-sample standard deviation s measured at rate fs
// converts as density = s / sqrt(fs).

#include <string>

namespace gati {

struct EngineConfig {
    // ---- inertial sensor noise (continuous time)
    // Defaults for the IO-VNBD vehicle ESP/CAN proxy IMU. The two white-noise densities were
    // identified on trip M (Driver B, 106 km) from the integrated-IMU error against the GNSS
    // speed/heading change over 10 s windows (tools/identify_imu_noise.py); they are far above a
    // data sheet because they include scale and mounting error. The bias walks and floors are
    // assumed values. The set was the best of 8 candidates on trip M (mean of the 30/60/120 s
    // median blackout drifts); other trips are hold-out (see the evidence document).
    double accelNoise{0.8};           // m/s^2/sqrt(Hz), velocity random walk density
    double gyroNoise{0.011};          // rad/s/sqrt(Hz), angle random walk density
    double accelBiasWalk{5e-4};       // m/s^2/sqrt(s)
    double gyroBiasWalk{2e-5};        // rad/s/sqrt(s)
    // Floors on how well the biases can ever be claimed to be known (an over-
    // confident bias variance is what makes a filter wrong AND sure of itself).
    double minAccelBiasSigma{0.02};   // m/s^2
    double minGyroBiasSigma{5e-4};    // rad/s

    // ---- initial uncertainty
    double initVelSigma{0.5};             // m/s
    double initTiltSigmaDeg{3.0};         // roll/pitch when levelled while moving
    double initTiltSigmaStaticDeg{1.0};   // roll/pitch when levelled at rest
    double initHeadingSigmaDeg{5.0};      // heading taken from GNSS course
    double initAccelBiasSigma{0.1};       // m/s^2
    double initGyroBiasSigma{0.01};       // rad/s

    // ---- alignment
    double alignWindow{2.0};          // s of IMU averaged to level the attitude
    double alignMinSpeed{3.0};        // m/s GNSS speed needed to trust the course
    double levelDeparture{0.6};       // m/s^2, specific-force change that ends the at-rest average

    // ---- GNSS
    double gnssMinSigma{2.0};         // m, floor on the reported accuracy
    double gnssSpeedSigma{0.2};       // m/s
    double gnssCourseSigmaDeg{1.5};   // deg
    double gnssMinCourseSpeed{2.0};   // m/s, below this the course is not used
    double gnssZeroSpeed{0.15};       // m/s, below this the vehicle is stopped
    double gnssAltSigma{5.0};         // m
    double gnssTimeout{3.0};          // s without an accepted fix => dead reckoning
    double gateScale{1.0};            // multiplies the chi-square gate (99 %)
    int gnssRejectLimit{3};           // consecutive rejections before a hard reset
    bool useGnssAltitude{true};

    // ---- vehicle constraints and stillness
    bool nhcEnabled{true};
    double nhcInterval{0.1};          // s between non-holonomic updates
    double nhcLateralSigma{0.3};      // m/s
    double nhcVerticalSigma{0.5};     // m/s
    double nhcMinSpeed{2.0};          // m/s
    double nhcMaxYawRate{0.5};        // rad/s, constraint suspended above this
    bool zuptEnabled{true};
    double zuptInterval{0.1};         // s between zero-velocity updates
    double zuptSigma{0.05};           // m/s
    double zuptGyroRms{0.05};         // rad/s, stillness threshold on |gyro - bias|
    double zuptAccelStd{0.6};         // m/s^2, stillness threshold on the accel scatter (rest p95 = 0.56)
    double zuptHold{1.0};             // s the sensor must stay still first
    double stillWindow{1.0};          // s, time constant of the stillness statistics
    double zaruInterval{1.0};         // s between zero-angular-rate updates
    double zuptMaxSpeed{1.5};         // m/s, never zero a speed above this ...
    double zuptSpeedSigmas{2.0};      // ... unless it is within this many 1-sigma of zero,
    double zuptSpeedCap{4.0};         // m/s, but never zero more than this (cruising looks still)
    double zuptMaxGnssSpeed{0.6};     // m/s, a fresh GNSS speed above this vetoes stillness
    bool zaruEnabled{true};

    // ---- guards
    double maxImuDt{0.5};             // s, a longer gap is integrated as this long
    double maxAccel{100.0};           // m/s^2
    double maxGyro{35.0};             // rad/s

    // The default configuration by name (kept for call sites that read better with it).
    static EngineConfig vehicleGrade();

    // Sets one named numeric or boolean field (booleans take 0 or 1). Returns false
    // for an unknown name, so a typo on a command line cannot pass silently.
    bool apply(const std::string& key, double value);
};

}  // namespace gati

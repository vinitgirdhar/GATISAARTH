#pragma once

// GatiSaarth edge navigation engine: strapdown INS in a local-level (NED) frame with a
// 15-state error-state Kalman filter. Independent of any sensor API: feed it ImuSample
// and GnssFix events from any source (see sensor_source.h) and read NavOutput.
//
// Error state (true = nominal + error; attitude: true = Exp(dpsi) * nominal, nav frame):
//   dp[3] NED metres, dv[3] m/s, dpsi[3] rad, d(accel bias)[3] m/s^2, d(gyro bias)[3] rad/s.
// Measurements: GNSS position / velocity / altitude, zero-velocity (ZUPT), zero angular
// rate (ZARU), non-holonomic constraint (NHC) and an external forward speed.
//
// The class is a plain value type (no heap): copying it forks the filter, which is how
// the replay harness starts many GNSS-outage experiments from one pass over a trip.

#include <array>
#include <cstdint>

#include "engine/types.h"
#include "engine/engine_config.h"
#include "engine/kalman_update.h"
#include "engine/linalg.h"
#include "engine/sensor_types.h"

namespace gati {

enum class NavMode : std::uint8_t { Uninitialised, Aligning, Gnss, DeadReckoning };
const char* toString(NavMode mode);

struct NavOutput {
    double t{0.0};
    double lat{kNoValue}, lon{kNoValue}, alt{kNoValue};   // deg, deg, m
    double vNorth{0.0}, vEast{0.0}, vDown{0.0};           // m/s
    double speed{0.0};                                    // ground speed, m/s
    double headingDeg{kNoValue};                          // body x axis, clockwise from north
    double rollDeg{0.0}, pitchDeg{0.0};
    double sigmaHoriz{kNoValue};                          // m, sqrt(var_N + var_E)
    double sigmaSpeed{kNoValue};                          // m/s
    double sigmaHeadingDeg{kNoValue};
    NavMode mode{NavMode::Uninitialised};
    bool valid{false};
};

struct UpdateCounter {
    std::uint64_t accepted{0}, rejected{0}, failed{0};
    double nisSum{0.0};
    double meanNis() const {
        const std::uint64_t n = accepted + rejected;
        return n == 0 ? 0.0 : nisSum / static_cast<double>(n);
    }
};

struct EngineStats {
    std::uint64_t imuUsed{0}, imuInvalid{0}, imuOutOfOrder{0}, imuGaps{0}, diverged{0};
    std::uint64_t gnssSeen{0}, gnssInvalid{0}, gnssResets{0}, velocityResets{0};
    UpdateCounter gnssPosition, gnssVelocity, gnssAltitude, nhc, zupt, zaru, forwardSpeed;
    double alignedAt{kNoValue};
};

class NavEngine {
public:
    explicit NavEngine(const EngineConfig& config = EngineConfig{});

    void pushImu(const ImuSample& sample);
    void pushGnss(const GnssFix& fix);
    // Body-x (forward) speed from an external estimator such as an odometer or a model.
    void pushForwardSpeed(double t, double speed, double sigma);

    NavOutput output() const;
    const EngineStats& stats() const { return stats_; }
    const EngineConfig& config() const { return cfg_; }
    bool aligned() const { return running_; }
    Vector3d accelBias() const { return x_.ba; }   // m/s^2, subtracted from the accelerometer
    Vector3d gyroBias() const { return x_.bg; }    // rad/s, subtracted from the gyro
    void reset();

private:
    using Cov = Mat<15, 15>;
    struct Nominal {
        double lat{0.0}, lon{0.0}, h{0.0};   // radians, radians, metres
        Vector3d v{};                        // NED m/s
        Quaterniond q{1.0, 0.0, 0.0, 0.0};   // body -> nav
        Vector3d ba{}, bg{};
    };
    struct Stillness {
        bool init{false};
        Vector3d meanF{}, meanW{};
        double fVar{0.0}, gyroSq{0.0}, quietFor{0.0}, span{0.0};
    };
    struct Level {
        bool init{false}, frozen{false};
        Vector3d meanF{};
        double span{0.0}, restSpan{0.0};
    };

    bool validImu(const ImuSample& s) const;
    bool validGnss(const GnssFix& g) const;
    void trackStillness(const ImuSample& s, double dt);
    bool stationary() const;
    void accumulateLevel(const ImuSample& s, double dt);
    bool tryAlign(const GnssFix& fix);
    void predict(const ImuSample& s, double dt);
    void applyConstraints(const ImuSample& s);
    void inject(const std::array<double, 15>& dx);
    void finishCovariance();
    bool healthy() const;

    void updateGnssPosition(const GnssFix& fix);
    void updateGnssVelocity(const GnssFix& fix);
    void updateGnssAltitude(const GnssFix& fix);
    void updateZupt(double sigma);
    void updateZaru();
    void updateNhc();
    void resetPosition(const GnssFix& fix, double sigma);
    void resetVelocityAndHeading(const GnssFix& fix);
    bool gnssSaysMoving(double now) const;

    template <int M>
    UpdateStatus run(const Mat<M, 15>& H, const std::array<double, M>& residual,
                     const std::array<double, M>& sigma, double gate, UpdateCounter& counter);

    EngineConfig cfg_;
    EngineStats stats_;
    Nominal x_;
    Cov P_;
    Stillness still_;
    Level level_;
    GnssFix lastFix_;
    bool running_{false}, haveImu_{false}, haveFix_{false};
    double lastImuT_{0.0}, lastGnssAcceptedT_{0.0};
    double nextNhcT_{0.0}, nextZuptT_{0.0}, nextZaruT_{0.0};
    int positionRejectStreak_{0}, velocityRejectStreak_{0};
};

}  // namespace gati

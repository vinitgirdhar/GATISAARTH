#include "engine/synthetic.h"

#include <algorithm>
#include <cmath>
#include <random>

#include "engine/geo.h"
#include "engine/linalg.h"

namespace gati {

namespace {

struct Kin {
    double lat{0.0}, lon{0.0}, h{0.0};   // radians, radians, metres
    double psi{0.0}, speed{0.0};         // heading (rad, clockwise from north), ground speed
};

constexpr int kSubSteps = 8;

// Advance the planar kinematics by dt with constant accel and heading rate.
Kin advance(Kin k, double accel, double psiRate, double dt) {
    const double h = dt / kSubSteps;
    for (int i = 0; i < kSubSteps; ++i) {
        const double vMid = std::max(0.0, k.speed + 0.5 * accel * h);
        const double psiMid = k.psi + 0.5 * psiRate * h;
        const double rm = geo::meridianRadius(k.lat) + k.h;
        const double rn = geo::primeVerticalRadius(k.lat) + k.h;
        k.lat += vMid * std::cos(psiMid) / rm * h;
        k.lon += vMid * std::sin(psiMid) / (rn * std::cos(k.lat)) * h;
        k.speed = std::max(0.0, k.speed + accel * h);
        k.psi += psiRate * h;
    }
    return k;
}

// Ideal FRD accelerometer and gyro for level planar motion at state k.
void idealImu(const Kin& k, double accel, double psiRate, Vector3d& f, Vector3d& w) {
    const double sl = std::sin(k.lat), cl = std::cos(k.lat);
    const double rm = geo::meridianRadius(k.lat) + k.h;
    const double rn = geo::primeVerticalRadius(k.lat) + k.h;
    const Vector3d v{k.speed * std::cos(k.psi), k.speed * std::sin(k.psi), 0.0};
    const Vector3d vDot{accel * std::cos(k.psi) - k.speed * psiRate * std::sin(k.psi),
                        accel * std::sin(k.psi) + k.speed * psiRate * std::cos(k.psi), 0.0};
    const Vector3d wie{geo::kEarthRate * cl, 0.0, -geo::kEarthRate * sl};
    const Vector3d wen{v.y / rn, -v.x / rm, -v.y * std::tan(k.lat) / rn};
    // Somigliana gravity (same closed form the engine uses through earth_model.h).
    const double s2 = sl * sl;
    const double g = 9.7803253359 * (1.0 + 0.00193185265241 * s2) / std::sqrt(1.0 - geo::kEccSq * s2) - 3.086e-6 * k.h;
    const Vector3d fNav = vDot - Vector3d{0.0, 0.0, g} + cross(wie * 2.0 + wen, v);
    const double c = std::cos(k.psi), s = std::sin(k.psi);   // C_bn for level yaw-only attitude
    f = {c * fNav.x + s * fNav.y, -s * fNav.x + c * fNav.y, fNav.z};
    const Vector3d earth = wie + wen;
    w = Vector3d{c * earth.x + s * earth.y, -s * earth.x + c * earth.y, earth.z} + Vector3d{0.0, 0.0, psiRate};
}

struct Noise {
    std::mt19937 rng;
    std::normal_distribution<double> unit{0.0, 1.0};
    double next(double sigma) { return sigma > 0.0 ? sigma * unit(rng) : 0.0; }
};

int stepsPer(double imuRate, double rate) {
    return rate > 0.0 ? std::max(1, static_cast<int>(std::lround(imuRate / rate))) : 0;
}

}  // namespace

SyntheticDrive generateDrive(const SyntheticConfig& c) {
    SyntheticDrive drive;
    const double dt = 1.0 / c.imuRateHz;
    const int gnssEvery = stepsPer(c.imuRateHz, c.gnssRateHz);
    const int truthEvery = stepsPer(c.imuRateHz, c.truthRateHz);
    Noise noise{std::mt19937(c.seed)};

    Kin k;
    k.lat = c.lat0Deg * geo::kDegToRad;
    k.lon = c.lon0Deg * geo::kDegToRad;
    k.h = c.alt0;
    k.psi = c.heading0Deg * geo::kDegToRad;
    k.speed = c.speed0;

    std::int64_t step = 0;
    for (const Maneuver& m : c.plan) {
        const std::int64_t steps = static_cast<std::int64_t>(std::llround(m.duration * c.imuRateHz));
        const double psiRate = m.yawRateDeg * geo::kDegToRad;
        for (std::int64_t i = 0; i < steps; ++i) {
            ++step;
            // Sample = value over the step, evaluated at its midpoint.
            const Kin mid = advance(k, m.accel, psiRate, 0.5 * dt);
            const Kin next = advance(k, m.accel, psiRate, dt);
            ImuSample imu;
            imu.t = static_cast<double>(step) * dt;
            idealImu(mid, m.accel, psiRate, imu.accel, imu.gyro);
            imu.accel = imu.accel + c.accelBias +
                        Vector3d{noise.next(c.accelNoiseStd), noise.next(c.accelNoiseStd), noise.next(c.accelNoiseStd)};
            imu.gyro = imu.gyro + c.gyroBias +
                       Vector3d{noise.next(c.gyroNoiseStd), noise.next(c.gyroNoiseStd), noise.next(c.gyroNoiseStd)};
            drive.distance += 0.5 * (k.speed + next.speed) * dt;
            k = next;
            drive.events.emplace_back(imu);

            if (gnssEvery > 0 && step % gnssEvery == 0) {
                GnssFix fix;
                fix.t = imu.t;
                const double rm = geo::meridianRadius(k.lat) + k.h;
                const double rn = geo::primeVerticalRadius(k.lat) + k.h;
                fix.lat = (k.lat + noise.next(c.gnssPosNoiseStd) / rm) * geo::kRadToDeg;
                fix.lon = (k.lon + noise.next(c.gnssPosNoiseStd) / (rn * std::cos(k.lat))) * geo::kRadToDeg;
                fix.alt = k.h;
                fix.speed = k.speed;
                fix.course = geo::wrap360Deg(k.psi * geo::kRadToDeg);
                fix.accuracy = c.gnssAccuracy;
                drive.events.emplace_back(fix);
            }
            if (truthEvery > 0 && step % truthEvery == 0) {
                drive.events.emplace_back(TruthPoint{imu.t, k.lat * geo::kRadToDeg, k.lon * geo::kRadToDeg});
            }
        }
    }
    drive.duration = static_cast<double>(step) * dt;
    return drive;
}

}  // namespace gati

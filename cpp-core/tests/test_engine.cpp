// Physics checks of the navigation engine against scripted trajectories.

#include <cmath>
#include <cstdio>

#include "check.h"
#include "engine/geo.h"
#include "engine/nav_engine.h"
#include "engine/synthetic.h"
#include "engine/earth.h"

using namespace gati;

namespace {

struct RunResult {
    NavOutput out;
    TruthPoint truth{};
    EngineStats stats;
};

// Replays a synthetic drive; GNSS fixes in [denyFrom, denyTo) are withheld, and
// `firstFixOnly` feeds a single fix (for pure-INS checks).
RunResult replay(const SyntheticDrive& drive, const EngineConfig& cfg, double denyFrom = 1e18, double denyTo = 1e18,
                 bool firstFixOnly = false, double courseErrorDeg = 0.0) {
    NavEngine engine(cfg);
    RunResult r;
    int fixes = 0;
    for (const SensorEvent& e : drive.events) {
        if (const auto* imu = std::get_if<ImuSample>(&e)) {
            engine.pushImu(*imu);
        } else if (const auto* gnss = std::get_if<GnssFix>(&e)) {
            const bool denied = gnss->t >= denyFrom && gnss->t < denyTo;
            if (denied || (firstFixOnly && fixes >= 1)) continue;
            GnssFix fix = *gnss;
            if (fixes == 0 && !engine.aligned()) fix.course += courseErrorDeg;
            ++fixes;
            engine.pushGnss(fix);
        } else if (const auto* truth = std::get_if<TruthPoint>(&e)) {
            r.truth = *truth;
        }
    }
    r.out = engine.output();
    r.stats = engine.stats();
    return r;
}

double errorMeters(const RunResult& r) {
    return geo::distanceMeters(r.out.lat * geo::kDegToRad, r.out.lon * geo::kDegToRad, r.truth.lat * geo::kDegToRad,
                               r.truth.lon * geo::kDegToRad);
}

double headingErrorDeg(double a, double b) { return std::fabs(geo::wrapPi((a - b) * geo::kDegToRad)) * geo::kRadToDeg; }

SyntheticConfig baseDrive(double rateHz) {
    SyntheticConfig c;
    c.imuRateHz = rateHz;
    c.heading0Deg = 30.0;   // not a cardinal direction: exercises both N and E paths
    c.plan = {{10.0, 0.0, 0.0}, {10.0, 1.5, 0.0}, {100.0, 0.0, 0.0}};
    return c;
}

void gravityMatchesKnownValue() {
    CHECK_NEAR(normalGravity(52.4, 0.0), 9.8128, 0.002);   // 52.4 deg N, sea level
    CHECK_NEAR(normalGravity(0.0, 0.0), 9.7803, 0.001);    // equator
    CHECK_NEAR(normalGravity(90.0, 0.0), 9.8322, 0.001);   // pole
}

void straightLineOutageStaysOnTrack() {
    const SyntheticDrive drive = generateDrive(baseDrive(100.0));   // 120 s, 15 m/s from t = 20 s
    const RunResult r = replay(drive, EngineConfig::vehicleGrade(), 40.0, 1e18);   // no GNSS after 40 s
    const double travelled = 15.0 * 80.0;   // metres covered without GNSS (t = 40 .. 120 s)
    std::printf("  straight: outage error %.3f m over %.0f m, speed %.3f, heading %.3f\n", errorMeters(r), travelled,
                r.out.speed, r.out.headingDeg);
    CHECK(r.out.valid);
    CHECK(r.out.mode == NavMode::DeadReckoning);
    CHECK(errorMeters(r) < 0.01 * travelled);          // < 1 % of the distance; an ideal IMU does far better
    CHECK_NEAR(r.out.speed, 15.0, 0.1);
    CHECK_NEAR(r.out.headingDeg, 30.0, 0.5);
    CHECK(r.stats.alignedAt >= 12.0 && r.stats.alignedAt < 16.0);
}

void turnKeepsHeadingAndPosition() {
    SyntheticConfig c = baseDrive(100.0);
    c.plan = {{10.0, 0.0, 0.0}, {10.0, 1.5, 0.0}, {20.0, 0.0, 0.0}, {30.0, 0.0, 3.0}, {30.0, 0.0, 0.0}};   // 90 deg right
    const SyntheticDrive drive = generateDrive(c);   // 100 s; GNSS denied from t = 40 s, through the turn
    const RunResult r = replay(drive, EngineConfig::vehicleGrade(), 40.0, 1e18);
    std::printf("  turn: error %.3f m, heading %.3f deg (expect 120)\n", errorMeters(r), r.out.headingDeg);
    CHECK(headingErrorDeg(r.out.headingDeg, 120.0) < 1.0);
    CHECK(errorMeters(r) < 3.0);
}

// Independent physics check: a perfect stationary IMU sees Earth rate and gravity; with
// every aiding source off, the pure INS must stay put. A wrong sign anywhere in the
// Earth-rate or gravity handling shows up as hundreds of metres in ten minutes.
void stationaryInsHoldsPositionForTenMinutes() {
    SyntheticConfig c;
    c.imuRateHz = 100.0;
    c.plan = {{600.0, 0.0, 0.0}};
    const SyntheticDrive drive = generateDrive(c);
    EngineConfig cfg = EngineConfig::vehicleGrade();
    cfg.alignMinSpeed = 0.0;
    cfg.zuptEnabled = cfg.zaruEnabled = cfg.nhcEnabled = false;
    cfg.useGnssAltitude = false;
    const RunResult r = replay(drive, cfg, 1e18, 1e18, /*firstFixOnly=*/true);
    std::printf("  stationary 600 s pure INS: drift %.4f m\n", errorMeters(r));
    CHECK(r.out.valid);
    CHECK(errorMeters(r) < 1.0);
}

// A 10 degree error in the initial heading must be removed by GNSS velocity + NHC.
void wrongInitialHeadingConverges() {
    SyntheticConfig c = baseDrive(50.0);
    c.plan = {{10.0, 0.0, 0.0}, {10.0, 1.5, 0.0}, {30.0, 0.0, 1.0}, {30.0, 0.0, -1.0}, {40.0, 0.0, 0.0}};
    const SyntheticDrive drive = generateDrive(c);
    const RunResult wrong = replay(drive, EngineConfig::vehicleGrade(), 1e18, 1e18, false, 10.0);
    std::printf("  wrong heading start: final heading error %.3f deg, position error %.2f m\n",
                headingErrorDeg(wrong.out.headingDeg, 30.0), errorMeters(wrong));
    CHECK(headingErrorDeg(wrong.out.headingDeg, 30.0) < 1.5);
    CHECK(errorMeters(wrong) < 5.0);
}

void outlierFixIsRejectedThenAcceptedWhenPersistent() {
    const SyntheticDrive drive = generateDrive(baseDrive(50.0));
    NavEngine engine(EngineConfig::vehicleGrade());
    GnssFix lastGood;
    int fixIndex = 0;
    for (const SensorEvent& e : drive.events) {
        if (const auto* imu = std::get_if<ImuSample>(&e)) {
            engine.pushImu(*imu);
        } else if (const auto* gnss = std::get_if<GnssFix>(&e)) {
            GnssFix fix = *gnss;
            lastGood = fix;
            if (fix.t >= 60.0 && fix.t < 63.0) fix.lat += 0.005;   // ~550 m north, three seconds in a row
            engine.pushGnss(fix);
            ++fixIndex;
            if (fix.t == 60.0) {
                const NavOutput o = engine.output();
                CHECK(geo::distanceMeters(o.lat * geo::kDegToRad, o.lon * geo::kDegToRad, lastGood.lat * geo::kDegToRad,
                                          lastGood.lon * geo::kDegToRad) < 10.0);   // first outlier ignored
            }
        }
    }
    // Three bad fixes in a row: the third is accepted by a reset onto it (the filter, not the
    // fix, is presumed wrong); then three true fixes are rejected and the second reset returns.
    CHECK(engine.stats().gnssPosition.rejected >= 5);
    CHECK(engine.stats().gnssResets == 2);
    const NavOutput end = engine.output();
    CHECK(geo::distanceMeters(end.lat * geo::kDegToRad, end.lon * geo::kDegToRad, lastGood.lat * geo::kDegToRad,
                              lastGood.lon * geo::kDegToRad) < 5.0);
    CHECK(fixIndex > 100);
}

void nonFiniteAndOutOfOrderInputIsCounted() {
    NavEngine engine;
    ImuSample s;
    s.t = 1.0;
    s.accel = {0.0, 0.0, -9.8};
    engine.pushImu(s);
    s.accel.x = std::nan("");
    engine.pushImu(s);
    s.accel.x = 0.0;
    s.t = 0.5;   // goes backwards
    engine.pushImu(s);
    GnssFix bad;
    bad.lat = 0.0;
    bad.lon = 0.0;   // null island
    engine.pushGnss(bad);
    CHECK(engine.stats().imuInvalid == 1);
    CHECK(engine.stats().imuOutOfOrder == 1);
    CHECK(engine.stats().gnssInvalid == 1);
    CHECK(!engine.output().valid);
}

}  // namespace

int main() {
    gravityMatchesKnownValue();
    straightLineOutageStaysOnTrack();
    turnKeepsHeadingAndPosition();
    stationaryInsHoldsPositionForTenMinutes();
    wrongInitialHeadingConverges();
    outlierFixIsRejectedThenAcceptedWhenPersistent();
    nonFiniteAndOutOfOrderInputIsCounted();
    return gati_test::finish("test_engine");
}

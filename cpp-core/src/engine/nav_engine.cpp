#include "engine/nav_engine.h"

#include <algorithm>
#include <cmath>

#include "engine/geo.h"
#include "engine/kalman_update.h"
#include "ins/earth_model.h"
#include "ins/mechanization.h"

namespace gati {

namespace {

constexpr double kChi2Gate1 = 6.635;   // 99 % chi-square, 1 degree of freedom
constexpr double kChi2Gate2 = 9.210;   // 99 %, 2 degrees of freedom
constexpr double kMinCosLat = 1e-6;
constexpr double kMaxSpeed = 200.0;    // m/s, beyond this the state is declared diverged

double sq(double x) { return x * x; }

double cosLatitude(double lat) { return std::max(std::cos(lat), kMinCosLat); }

}  // namespace

const char* toString(NavMode mode) {
    switch (mode) {
        case NavMode::Uninitialised: return "uninitialised";
        case NavMode::Aligning: return "aligning";
        case NavMode::Gnss: return "gnss";
        case NavMode::DeadReckoning: return "dead_reckoning";
    }
    return "unknown";
}

NavEngine::NavEngine(const EngineConfig& config) : cfg_(config) {}

void NavEngine::reset() { *this = NavEngine(cfg_); }

// ---------------------------------------------------------------- validation

bool NavEngine::validImu(const ImuSample& s) const {
    return std::isfinite(s.t) && isFinite(s.accel) && isFinite(s.gyro) && norm(s.accel) <= cfg_.maxAccel &&
           norm(s.gyro) <= cfg_.maxGyro;
}

bool NavEngine::validGnss(const GnssFix& g) const {
    if (!std::isfinite(g.t) || !std::isfinite(g.lat) || !std::isfinite(g.lon)) return false;
    if (std::fabs(g.lat) > 90.0 || std::fabs(g.lon) > 180.0) return false;
    if (g.lat == 0.0 && g.lon == 0.0) return false;   // "null island": a receiver with no fix
    if (std::isfinite(g.speed) && (g.speed < 0.0 || g.speed > 150.0)) return false;
    return true;
}

bool NavEngine::healthy() const {
    const bool finite = std::isfinite(x_.lat) && std::isfinite(x_.lon) && std::isfinite(x_.h) && isFinite(x_.v) &&
                        std::isfinite(x_.q[0]) && std::isfinite(x_.q[1]) && std::isfinite(x_.q[2]) &&
                        std::isfinite(x_.q[3]);
    if (!finite || norm(x_.v) > kMaxSpeed) return false;
    for (int i = 0; i < 15; ++i)
        if (!std::isfinite(P_(i, i))) return false;
    return true;
}

// ---------------------------------------------------------------- stillness and levelling

void NavEngine::trackStillness(const ImuSample& s, double dt) {
    if (!still_.init) {
        still_ = Stillness{};
        still_.init = true;
        still_.meanF = s.accel;
        still_.meanW = s.gyro;
        still_.gyroSq = dot(s.gyro, s.gyro);
        return;
    }
    const double alpha = 1.0 - std::exp(-dt / cfg_.stillWindow);
    still_.meanF = still_.meanF + (s.accel - still_.meanF) * alpha;
    still_.meanW = still_.meanW + (s.gyro - still_.meanW) * alpha;
    const Vector3d dF = s.accel - still_.meanF;
    const Vector3d w = s.gyro - x_.bg;
    still_.fVar += alpha * (dot(dF, dF) - still_.fVar);
    still_.gyroSq += alpha * (dot(w, w) - still_.gyroSq);
    still_.span += dt;
    const bool quiet = still_.span >= cfg_.stillWindow && std::sqrt(still_.fVar) < cfg_.zuptAccelStd &&
                       std::sqrt(still_.gyroSq) < cfg_.zuptGyroRms;
    still_.quietFor = quiet ? still_.quietFor + dt : 0.0;
}

bool NavEngine::stationary() const { return still_.quietFor >= cfg_.zuptHold; }

// Before alignment, average the specific force to find "up". While the last GNSS fix
// says the vehicle is at rest the average is the true gravity direction; once it starts
// moving, an average taken at rest is frozen and kept, because accelerating would bias it.
void NavEngine::accumulateLevel(const ImuSample& s, double dt) {
    if (!level_.init) {
        level_ = Level{};
        level_.init = true;
        level_.meanF = s.accel;
        return;
    }
    if (level_.frozen) return;
    const bool fresh = haveFix_ && (s.t - lastFix_.t) < cfg_.gnssTimeout && std::isfinite(lastFix_.speed);
    const bool moving = fresh && lastFix_.speed >= 0.5;
    // A GNSS fix notices motion up to one fix interval late, so also freeze the moment
    // the specific force leaves the rest value: accelerating must not tilt the average.
    const bool restKnown = level_.restSpan >= cfg_.alignWindow;
    if (restKnown && (moving || norm(s.accel - level_.meanF) > cfg_.levelDeparture)) {
        level_.frozen = true;
        return;
    }
    if (moving) level_.restSpan = 0.0;
    if (fresh && !moving) level_.restSpan += dt;
    const double alpha = 1.0 - std::exp(-dt / (0.5 * cfg_.alignWindow));
    level_.meanF = level_.meanF + (s.accel - level_.meanF) * alpha;
    level_.span += dt;
}

bool NavEngine::tryAlign(const GnssFix& fix) {
    if (!haveImu_ || !level_.init || level_.span < cfg_.alignWindow) return false;
    if (!(fix.speed >= cfg_.alignMinSpeed) || !std::isfinite(fix.course)) return false;

    const Vector3d f = level_.meanF;
    const double roll = std::atan2(-f.y, -f.z);
    const double pitch = std::atan2(f.x, std::sqrt(f.y * f.y + f.z * f.z));
    const double yaw = fix.course * geo::kDegToRad;

    x_ = Nominal{};
    x_.q = quatFromEuler(roll, pitch, yaw);
    x_.lat = fix.lat * geo::kDegToRad;
    x_.lon = fix.lon * geo::kDegToRad;
    x_.h = std::isfinite(fix.alt) ? fix.alt : 0.0;
    x_.v = {fix.speed * std::cos(yaw), fix.speed * std::sin(yaw), 0.0};

    const double pSigma = std::max(std::isfinite(fix.accuracy) && fix.accuracy > 0.0 ? fix.accuracy : cfg_.gnssMinSigma,
                                   cfg_.gnssMinSigma);
    const double tilt = (level_.frozen ? cfg_.initTiltSigmaStaticDeg : cfg_.initTiltSigmaDeg) * geo::kDegToRad;
    const double yawSigma = cfg_.initHeadingSigmaDeg * geo::kDegToRad;
    P_ = Cov{};
    const double variance[15] = {sq(pSigma), sq(pSigma), sq(2.0 * pSigma),
                                 sq(cfg_.initVelSigma), sq(cfg_.initVelSigma), sq(cfg_.initVelSigma),
                                 sq(tilt), sq(tilt), sq(yawSigma),
                                 sq(cfg_.initAccelBiasSigma), sq(cfg_.initAccelBiasSigma), sq(cfg_.initAccelBiasSigma),
                                 sq(cfg_.initGyroBiasSigma), sq(cfg_.initGyroBiasSigma), sq(cfg_.initGyroBiasSigma)};
    for (int i = 0; i < 15; ++i) P_(i, i) = variance[i];

    running_ = true;
    stats_.alignedAt = fix.t;
    lastGnssAcceptedT_ = fix.t;
    nextNhcT_ = nextZuptT_ = nextZaruT_ = fix.t;
    positionRejectStreak_ = velocityRejectStreak_ = 0;
    return true;
}

// ---------------------------------------------------------------- strapdown prediction

void NavEngine::predict(const ImuSample& s, double dt) {
    const double cosLat = cosLatitude(x_.lat);
    const double latDeg = x_.lat * geo::kRadToDeg;
    const double rm = geo::meridianRadius(x_.lat) + x_.h;
    const double rn = geo::primeVerticalRadius(x_.lat) + x_.h;

    const Vector3d f = s.accel - x_.ba;
    const Vector3d w = s.gyro - x_.bg;

    // Earth rate and transport rate, navigation frame.
    const Vector3d wie{geo::kEarthRate * cosLat, 0.0, -geo::kEarthRate * std::sin(x_.lat)};
    const Vector3d wen{x_.v.y / rn, -x_.v.x / rm, -x_.v.y * std::tan(x_.lat) / rn};

    // Attitude: body rate relative to the navigation frame, in the body frame.
    const Vector3d wnb = w - transposed(dcmFromQuat(x_.q)) * (wie + wen);
    Quaterniond qMid = x_.q;
    updateAttitudeQuaternion(qMid, wnb, 0.5 * dt);
    Quaterniond qNext = x_.q;
    updateAttitudeQuaternion(qNext, wnb, dt);

    // Velocity: specific force rotated with the mid-step attitude, gravity, Coriolis.
    const Vector3d fn = transformAccelToNavFrame(f, qMid);
    const Vector3d gravity{0.0, 0.0, calculateSomiglianaGravity(latDeg, x_.h)};
    const Vector3d accel = fn + gravity + computeCoriolisCorrection(x_.v, latDeg) - cross(wen, x_.v);
    const Vector3d vNext = x_.v + accel * dt;
    const Vector3d vMean = (x_.v + vNext) * 0.5;

    x_.lat += vMean.x / rm * dt;
    x_.lon += vMean.y / (rn * cosLat) * dt;
    x_.h -= vMean.z * dt;
    x_.v = vNext;
    x_.q = qNext;

    // Covariance: Phi = I + F dt + (F dt)^2 / 2 with the error-state Jacobian F.
    const Mat<3, 3> c = dcmFromQuat(qMid);
    const Mat<3, 3> sk = skew(fn);
    Cov F;
    for (int r = 0; r < 3; ++r) {
        F(r, 3 + r) = 1.0;
        for (int k = 0; k < 3; ++k) {
            F(3 + r, 6 + k) = -sk(r, k);
            F(3 + r, 9 + k) = -c(r, k);
            F(6 + r, 12 + k) = -c(r, k);
        }
    }
    const Cov phi = identity<15>() + F * dt + (F * F) * (0.5 * dt * dt);
    Cov q;
    const double velVar = sq(cfg_.accelNoise) * dt;
    const double attVar = sq(cfg_.gyroNoise) * dt;
    for (int i = 0; i < 3; ++i) {
        q(i, i) = velVar * dt * dt / 3.0;
        q(3 + i, 3 + i) = velVar;
        q(6 + i, 6 + i) = attVar;
        q(9 + i, 9 + i) = sq(cfg_.accelBiasWalk) * dt;
        q(12 + i, 12 + i) = sq(cfg_.gyroBiasWalk) * dt;
    }
    P_ = phi * P_ * transposed(phi) + q;
    finishCovariance();
}

void NavEngine::finishCovariance() {
    for (int i = 0; i < 15; ++i)
        for (int j = i + 1; j < 15; ++j) {
            const double m = 0.5 * (P_(i, j) + P_(j, i));
            P_(i, j) = P_(j, i) = m;
        }
    for (int i = 0; i < 3; ++i) {
        P_(9 + i, 9 + i) = std::max(P_(9 + i, 9 + i), sq(cfg_.minAccelBiasSigma));
        P_(12 + i, 12 + i) = std::max(P_(12 + i, 12 + i), sq(cfg_.minGyroBiasSigma));
    }
}

void NavEngine::inject(const std::array<double, 15>& dx) {
    const double rm = geo::meridianRadius(x_.lat) + x_.h;
    const double rn = geo::primeVerticalRadius(x_.lat) + x_.h;
    x_.lat += dx[0] / rm;
    x_.lon += dx[1] / (rn * cosLatitude(x_.lat));
    x_.h -= dx[2];
    x_.v = x_.v + Vector3d{dx[3], dx[4], dx[5]};
    x_.q = quatNormalized(quatMul(quatFromRotationVector({dx[6], dx[7], dx[8]}), x_.q));
    x_.ba = x_.ba + Vector3d{dx[9], dx[10], dx[11]};
    x_.bg = x_.bg + Vector3d{dx[12], dx[13], dx[14]};
}

template <int M>
UpdateStatus NavEngine::run(const Mat<M, 15>& H, const std::array<double, M>& residual,
                            const std::array<double, M>& sigma, double gate, UpdateCounter& counter) {
    std::array<double, 15> dx{};
    const UpdateResult result = kalmanUpdate<M>(P_, H, residual, sigma, gate, dx);
    switch (result.status) {
        case UpdateStatus::Accepted:
            ++counter.accepted;
            counter.nisSum += result.nis;
            inject(dx);
            finishCovariance();
            break;
        case UpdateStatus::Rejected:
            ++counter.rejected;
            counter.nisSum += result.nis;
            break;
        case UpdateStatus::Failed:
            ++counter.failed;
            break;
    }
    return result.status;
}

// ---------------------------------------------------------------- vehicle constraints

// A fresh GNSS speed is direct evidence of motion. Smooth cruising looks perfectly still
// to an inertial stillness test, so without this veto a wrong low speed estimate could
// be held at zero by ZUPT forever.
bool NavEngine::gnssSaysMoving(double now) const {
    return haveFix_ && (now - lastFix_.t) < cfg_.gnssTimeout && std::isfinite(lastFix_.speed) &&
           lastFix_.speed > cfg_.zuptMaxGnssSpeed;
}

void NavEngine::applyConstraints(const ImuSample& s) {
    const double speed = std::hypot(x_.v.x, x_.v.y);
    // Inertial stillness cannot tell smooth cruising from rest, so only speeds the filter
    // itself cannot distinguish from zero (or below a small fixed guard) are ever zeroed.
    const double sigmaSpeed = std::sqrt(std::max(0.0, P_(3, 3) + P_(4, 4)));
    const double zuptSpeedLimit = std::min(cfg_.zuptSpeedCap, std::max(cfg_.zuptMaxSpeed, cfg_.zuptSpeedSigmas * sigmaSpeed));
    if (stationary() && speed < zuptSpeedLimit && !gnssSaysMoving(s.t)) {
        if (cfg_.zuptEnabled && s.t >= nextZuptT_) {
            updateZupt(cfg_.zuptSigma);
            nextZuptT_ = s.t + cfg_.zuptInterval;
        }
        if (cfg_.zaruEnabled && s.t >= nextZaruT_) {
            updateZaru();
            nextZaruT_ = s.t + cfg_.zaruInterval;
        }
        return;
    }
    const double yawRate = std::fabs(s.gyro.z - x_.bg.z);
    if (cfg_.nhcEnabled && speed >= cfg_.nhcMinSpeed && yawRate < cfg_.nhcMaxYawRate && s.t >= nextNhcT_) {
        updateNhc();
        nextNhcT_ = s.t + cfg_.nhcInterval;
    }
}

void NavEngine::updateZupt(double sigma) {
    Mat<3, 15> H;
    for (int i = 0; i < 3; ++i) H(i, 3 + i) = 1.0;
    run<3>(H, {-x_.v.x, -x_.v.y, -x_.v.z}, {sigma, sigma, sigma}, 0.0, stats_.zupt);
}

void NavEngine::updateZaru() {
    const Mat<3, 3> cbn = transposed(dcmFromQuat(x_.q));
    const Vector3d earthInBody = cbn * Vector3d{geo::kEarthRate * std::cos(x_.lat), 0.0, -geo::kEarthRate * std::sin(x_.lat)};
    const Vector3d r = still_.meanW - earthInBody - x_.bg;
    const double sigma = std::max(cfg_.gyroNoise / std::sqrt(2.0 * cfg_.stillWindow), 1e-6);
    Mat<3, 15> H;
    for (int i = 0; i < 3; ++i) H(i, 12 + i) = 1.0;
    run<3>(H, {r.x, r.y, r.z}, {sigma, sigma, sigma}, 0.0, stats_.zaru);
}

// Non-holonomic constraint: a road vehicle has no sideways or vertical velocity.
// v_body = C_bn v; d(v_body) = C_bn dv + C_bn [v]x dpsi.
void NavEngine::updateNhc() {
    const Mat<3, 3> cbn = transposed(dcmFromQuat(x_.q));
    const Vector3d vb = cbn * x_.v;
    const Mat<3, 3> hAtt = cbn * skew(x_.v);
    Mat<2, 15> H;
    for (int row = 0; row < 2; ++row)
        for (int k = 0; k < 3; ++k) {
            H(row, 3 + k) = cbn(row + 1, k);
            H(row, 6 + k) = hAtt(row + 1, k);
        }
    run<2>(H, {-vb.y, -vb.z}, {cfg_.nhcLateralSigma, cfg_.nhcVerticalSigma}, 13.82 * cfg_.gateScale, stats_.nhc);
}

void NavEngine::pushForwardSpeed(double t, double speed, double sigma) {
    (void)t;
    if (!running_ || !std::isfinite(speed) || !(sigma > 0.0)) return;
    const Mat<3, 3> cbn = transposed(dcmFromQuat(x_.q));
    const Vector3d vb = cbn * x_.v;
    const Mat<3, 3> hAtt = cbn * skew(x_.v);
    Mat<1, 15> H;
    for (int k = 0; k < 3; ++k) {
        H(0, 3 + k) = cbn(0, k);
        H(0, 6 + k) = hAtt(0, k);
    }
    run<1>(H, {speed - vb.x}, {sigma}, kChi2Gate1 * cfg_.gateScale, stats_.forwardSpeed);
}

// ---------------------------------------------------------------- GNSS

void NavEngine::resetPosition(const GnssFix& fix, double sigma) {
    x_.lat = fix.lat * geo::kDegToRad;
    x_.lon = fix.lon * geo::kDegToRad;
    for (int i = 0; i < 15; ++i) {
        P_(0, i) = P_(i, 0) = 0.0;
        P_(1, i) = P_(i, 1) = 0.0;
    }
    P_(0, 0) = P_(1, 1) = sq(sigma);
    positionRejectStreak_ = 0;
    ++stats_.gnssResets;
}

// Repeated velocity rejections mean the velocity and heading estimates are grossly wrong
// (the filter, not the fix): take them from the fix and widen their uncertainty.
void NavEngine::resetVelocityAndHeading(const GnssFix& fix) {
    const double course = fix.course * geo::kDegToRad;
    x_.v = {fix.speed * std::cos(course), fix.speed * std::sin(course), 0.0};
    double roll = 0.0, pitch = 0.0, yaw = 0.0;
    eulerFromQuat(x_.q, roll, pitch, yaw);
    x_.q = quatFromEuler(roll, pitch, course);
    for (int i : {3, 4, 5, 8})
        for (int j = 0; j < 15; ++j) P_(i, j) = P_(j, i) = 0.0;
    for (int i : {3, 4, 5}) P_(i, i) = sq(cfg_.initVelSigma);
    P_(8, 8) = sq(cfg_.initHeadingSigmaDeg * geo::kDegToRad);
    velocityRejectStreak_ = 0;
    ++stats_.velocityResets;
}

void NavEngine::updateGnssPosition(const GnssFix& fix) {
    const double accuracy = std::isfinite(fix.accuracy) && fix.accuracy > 0.0 ? fix.accuracy : 5.0;
    const double sigma = std::max(accuracy, cfg_.gnssMinSigma);
    const double rm = geo::meridianRadius(x_.lat) + x_.h;
    const double rn = geo::primeVerticalRadius(x_.lat) + x_.h;
    const double dN = (fix.lat * geo::kDegToRad - x_.lat) * rm;
    const double dE = geo::wrapPi(fix.lon * geo::kDegToRad - x_.lon) * rn * cosLatitude(x_.lat);

    Mat<2, 15> H;
    H(0, 0) = 1.0;
    H(1, 1) = 1.0;
    const UpdateStatus status = run<2>(H, {dN, dE}, {sigma, sigma}, kChi2Gate2 * cfg_.gateScale, stats_.gnssPosition);
    if (status == UpdateStatus::Accepted) {
        positionRejectStreak_ = 0;
        lastGnssAcceptedT_ = fix.t;
    } else if (status == UpdateStatus::Rejected && ++positionRejectStreak_ >= cfg_.gnssRejectLimit) {
        // The filter, not the fix, is probably wrong (a long outage): take the fix.
        resetPosition(fix, sigma);
        lastGnssAcceptedT_ = fix.t;
    }
}

void NavEngine::updateGnssVelocity(const GnssFix& fix) {
    if (!std::isfinite(fix.speed)) return;
    if (fix.speed < cfg_.gnssZeroSpeed) {
        updateZupt(cfg_.zuptSigma);   // Doppler speed says stopped
        return;
    }
    if (fix.speed < cfg_.gnssMinCourseSpeed || !std::isfinite(fix.course)) return;
    const double course = fix.course * geo::kDegToRad;
    const double sigma = std::sqrt(sq(cfg_.gnssSpeedSigma) + sq(fix.speed * cfg_.gnssCourseSigmaDeg * geo::kDegToRad));
    Mat<2, 15> H;
    H(0, 3) = 1.0;
    H(1, 4) = 1.0;
    const UpdateStatus status =
        run<2>(H, {fix.speed * std::cos(course) - x_.v.x, fix.speed * std::sin(course) - x_.v.y}, {sigma, sigma},
               kChi2Gate2 * cfg_.gateScale, stats_.gnssVelocity);
    if (status == UpdateStatus::Accepted) velocityRejectStreak_ = 0;
    else if (status == UpdateStatus::Rejected && ++velocityRejectStreak_ >= cfg_.gnssRejectLimit) resetVelocityAndHeading(fix);
}

void NavEngine::updateGnssAltitude(const GnssFix& fix) {
    if (!cfg_.useGnssAltitude || !std::isfinite(fix.alt)) return;
    Mat<1, 15> H;
    H(0, 2) = 1.0;   // down-position error = height estimate - measured height
    run<1>(H, {x_.h - fix.alt}, {cfg_.gnssAltSigma}, kChi2Gate1 * cfg_.gateScale, stats_.gnssAltitude);
}

void NavEngine::pushGnss(const GnssFix& fix) {
    ++stats_.gnssSeen;
    if (!validGnss(fix)) {
        ++stats_.gnssInvalid;
        return;
    }
    lastFix_ = fix;
    haveFix_ = true;
    if (!running_) {
        tryAlign(fix);
        return;
    }
    updateGnssPosition(fix);
    updateGnssVelocity(fix);
    updateGnssAltitude(fix);
}

// ---------------------------------------------------------------- IMU entry point

void NavEngine::pushImu(const ImuSample& s) {
    if (!validImu(s)) {
        ++stats_.imuInvalid;
        return;
    }
    if (!haveImu_) {
        haveImu_ = true;
        lastImuT_ = s.t;
        trackStillness(s, 0.0);
        accumulateLevel(s, 0.0);
        return;
    }
    double dt = s.t - lastImuT_;
    if (!(dt > 0.0)) {
        ++stats_.imuOutOfOrder;
        return;
    }
    lastImuT_ = s.t;
    trackStillness(s, dt);
    if (!running_) {
        accumulateLevel(s, dt);
        return;
    }
    if (dt > cfg_.maxImuDt) {
        ++stats_.imuGaps;
        dt = cfg_.maxImuDt;
    }
    predict(s, dt);
    if (!healthy()) {
        // Numerical divergence: drop the solution and re-align on the next usable fix.
        ++stats_.diverged;
        const EngineStats keep = stats_;
        *this = NavEngine(cfg_);
        stats_ = keep;
        haveImu_ = true;
        lastImuT_ = s.t;
        return;
    }
    applyConstraints(s);
    ++stats_.imuUsed;
}

// ---------------------------------------------------------------- output

NavOutput NavEngine::output() const {
    NavOutput o;
    if (!running_) {
        if (!haveFix_) return o;
        o.t = haveImu_ ? std::max(lastImuT_, lastFix_.t) : lastFix_.t;
        o.lat = lastFix_.lat;
        o.lon = lastFix_.lon;
        o.alt = lastFix_.alt;
        o.speed = std::isfinite(lastFix_.speed) ? lastFix_.speed : 0.0;
        o.headingDeg = lastFix_.course;
        o.sigmaHoriz = std::isfinite(lastFix_.accuracy) ? lastFix_.accuracy : 5.0;
        o.mode = NavMode::Aligning;
        o.valid = true;
        return o;
    }
    double roll = 0.0, pitch = 0.0, yaw = 0.0;
    eulerFromQuat(x_.q, roll, pitch, yaw);
    o.t = lastImuT_;
    o.lat = x_.lat * geo::kRadToDeg;
    o.lon = x_.lon * geo::kRadToDeg;
    o.alt = x_.h;
    o.vNorth = x_.v.x;
    o.vEast = x_.v.y;
    o.vDown = x_.v.z;
    o.speed = std::hypot(x_.v.x, x_.v.y);
    o.headingDeg = geo::wrap360Deg(yaw * geo::kRadToDeg);
    o.rollDeg = roll * geo::kRadToDeg;
    o.pitchDeg = pitch * geo::kRadToDeg;
    o.sigmaHoriz = std::sqrt(std::max(0.0, P_(0, 0) + P_(1, 1)));
    o.sigmaSpeed = std::sqrt(std::max(0.0, P_(3, 3) + P_(4, 4)));
    o.sigmaHeadingDeg = std::sqrt(std::max(0.0, P_(8, 8))) * geo::kRadToDeg;
    o.mode = (lastImuT_ - lastGnssAcceptedT_ > cfg_.gnssTimeout) ? NavMode::DeadReckoning : NavMode::Gnss;
    o.valid = true;
    return o;
}

}  // namespace gati

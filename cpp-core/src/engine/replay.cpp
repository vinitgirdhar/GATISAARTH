#include "engine/replay.h"

#include <algorithm>
#include <cmath>
#include <limits>

#include "engine/geo.h"

namespace gati {

namespace {

constexpr double kMaxTruthGap = 1.5;      // s: truth samples further apart than this are a hole
constexpr double kMinTruthSpeed = 2.0;    // m/s: below this the truth course is not defined
constexpr double kEndTolerance = 0.5;     // s: engine output may stop this far before the window end

// ---------------------------------------------------------------- truth track

struct TruthTrack {
    std::vector<double> t, lat, lon;   // lat/lon in degrees

    bool position(double time, double& la, double& lo) const {
        if (t.empty() || time < t.front() || time > t.back()) return false;
        const std::size_t i = static_cast<std::size_t>(std::lower_bound(t.begin(), t.end(), time) - t.begin());
        if (i == 0) {
            la = lat[0];
            lo = lon[0];
            return true;
        }
        const double span = t[i] - t[i - 1];
        if (span > kMaxTruthGap) return false;
        const double w = span > 0.0 ? (time - t[i - 1]) / span : 0.0;
        la = lat[i - 1] + w * (lat[i] - lat[i - 1]);
        lo = lon[i - 1] + w * (lon[i] - lon[i - 1]);
        return true;
    }

    // Course (deg clockwise from north) from a +-0.5 s baseline; false when too slow.
    bool course(double time, double& courseDeg) const {
        double la0 = 0, lo0 = 0, la1 = 0, lo1 = 0;
        if (!position(time - 0.5, la0, lo0) || !position(time + 0.5, la1, lo1)) return false;
        const geo::NorthEast d = geo::offsetMeters(la0 * geo::kDegToRad, lo0 * geo::kDegToRad, la1 * geo::kDegToRad,
                                                   lo1 * geo::kDegToRad);
        if (std::hypot(d.north, d.east) < kMinTruthSpeed) return false;   // 1 s baseline: metres = m/s
        courseDeg = geo::wrap360Deg(std::atan2(d.east, d.north) * geo::kRadToDeg);
        return true;
    }

    // Path length over [a, b] as the sum of chords at most 1 s long (sums the truth's
    // millimetre noise over a second, not over a tenth, when the vehicle is stopped).
    bool pathLength(double a, double b, double& length) const {
        const int n = std::max(1, static_cast<int>(std::ceil(b - a)));
        double la0 = 0, lo0 = 0;
        if (!position(a, la0, lo0)) return false;
        length = 0.0;
        for (int i = 1; i <= n; ++i) {
            double la1 = 0, lo1 = 0;
            if (!position(a + (b - a) * i / n, la1, lo1)) return false;
            length += geo::distanceMeters(la0 * geo::kDegToRad, lo0 * geo::kDegToRad, la1 * geo::kDegToRad,
                                          lo1 * geo::kDegToRad);
            la0 = la1;
            lo0 = lo1;
        }
        return true;
    }
};

// ---------------------------------------------------------------- engine trajectory helpers

using Trajectory = std::vector<NavOutput>;

std::size_t indexAtOrBefore(const Trajectory& traj, double time) {
    const auto it = std::upper_bound(traj.begin(), traj.end(), time,
                                     [](double v, const NavOutput& o) { return v < o.t; });
    return it == traj.begin() ? 0 : static_cast<std::size_t>(it - traj.begin()) - 1;
}

bool enginePosition(const Trajectory& traj, double time, double& lat, double& lon) {
    if (traj.empty() || time < traj.front().t || time > traj.back().t) return false;
    const std::size_t i = indexAtOrBefore(traj, time);
    if (i + 1 >= traj.size()) {
        lat = traj[i].lat;
        lon = traj[i].lon;
        return true;
    }
    const double span = traj[i + 1].t - traj[i].t;
    const double w = span > 0.0 ? (time - traj[i].t) / span : 0.0;
    lat = traj[i].lat + w * (traj[i + 1].lat - traj[i].lat);
    lon = traj[i].lon + w * (traj[i + 1].lon - traj[i].lon);
    return true;
}

double metersBetween(double la0, double lo0, double la1, double lo1) {
    return geo::distanceMeters(la0 * geo::kDegToRad, lo0 * geo::kDegToRad, la1 * geo::kDegToRad, lo1 * geo::kDegToRad);
}

double percentile(std::vector<double> v, double p) {
    if (v.empty()) return 0.0;
    std::sort(v.begin(), v.end());
    return v[static_cast<std::size_t>(p * static_cast<double>(v.size() - 1))];
}

double mean(const std::vector<double>& v) {
    if (v.empty()) return 0.0;
    double s = 0.0;
    for (double x : v) s += x;
    return s / static_cast<double>(v.size());
}

// ---------------------------------------------------------------- window scoring

WindowResult skipped(WindowResult w, const char* reason) {
    w.scored = false;
    w.skipReason = reason;
    return w;
}

// Scores one GNSS-denied window [start, start + length] (absolute times) from the engine
// trajectory that covers it. `t0` only converts to the relative times of the result.
WindowResult evaluateWindow(const Trajectory& traj, const TruthTrack& truth, double t0, double start, double length,
                            double minDistance) {
    WindowResult w;
    w.start = start - t0;
    w.length = length;
    const double end = start + length;
    if (traj.empty() || traj.back().t < end - kEndTolerance || traj.front().t > start + 1e-9)
        return skipped(w, "engine output does not cover the window");
    if (!truth.pathLength(start, end, w.distance)) return skipped(w, "truth has a gap in the window");
    if (w.distance < minDistance) return skipped(w, "too little travel");

    double tla = 0, tlo = 0, ela = 0, elo = 0;
    if (!truth.position(end, tla, tlo) || !enginePosition(traj, std::min(end, traj.back().t), ela, elo))
        return skipped(w, "no position at the window end");
    w.endError = metersBetween(ela, elo, tla, tlo);
    if (truth.position(start, tla, tlo) && enginePosition(traj, start, ela, elo))
        w.startError = metersBetween(ela, elo, tla, tlo);

    const auto first = std::lower_bound(truth.t.begin(), truth.t.end(), start);
    for (auto it = first; it != truth.t.end() && *it <= end; ++it) {
        const std::size_t k = static_cast<std::size_t>(it - truth.t.begin());
        if (enginePosition(traj, *it, ela, elo)) w.maxError = std::max(w.maxError, metersBetween(ela, elo, truth.lat[k], truth.lon[k]));
    }

    // Hold-last-velocity baseline: the position and velocity the engine had at the start.
    const NavOutput& s0 = traj[indexAtOrBefore(traj, start)];
    const double lat0 = s0.lat * geo::kDegToRad;
    const double holdLat = s0.lat + (s0.vNorth * length / (geo::meridianRadius(lat0) + s0.alt)) * geo::kRadToDeg;
    const double holdLon = s0.lon + (s0.vEast * length / ((geo::primeVerticalRadius(lat0) + s0.alt) * std::cos(lat0))) * geo::kRadToDeg;
    w.holdError = truth.position(end, tla, tlo) ? metersBetween(holdLat, holdLon, tla, tlo) : 0.0;

    const NavOutput& e1 = traj[indexAtOrBefore(traj, end)];
    w.sigmaEnd = e1.sigmaHoriz;
    double truthCourse = 0.0;
    if (truth.course(end, truthCourse) && std::isfinite(e1.headingDeg))
        w.headingError = std::fabs(geo::wrapPi((e1.headingDeg - truthCourse) * geo::kDegToRad)) * geo::kRadToDeg;
    w.driftPercent = 100.0 * w.endError / w.distance;
    w.holdDriftPercent = 100.0 * w.holdError / w.distance;
    w.scored = true;
    return w;
}

LengthSummary summarize(const std::vector<WindowResult>& windows, double length) {
    LengthSummary s;
    s.length = length;
    std::vector<double> drift, endErr, hold, heading;
    std::size_t under10 = 0, covered = 0;
    for (const WindowResult& w : windows) {
        if (w.length != length) continue;
        if (!w.scored) {
            ++s.skipped;
            continue;
        }
        drift.push_back(w.driftPercent);
        endErr.push_back(w.endError);
        hold.push_back(w.holdDriftPercent);
        if (std::isfinite(w.headingError)) heading.push_back(w.headingError);
        under10 += w.driftPercent < 10.0;
        covered += w.endError <= 3.0 * w.sigmaEnd;
    }
    s.scored = drift.size();
    if (s.scored == 0) return s;
    const double n = static_cast<double>(s.scored);
    s.medianDrift = percentile(drift, 0.5);
    s.meanDrift = mean(drift);
    s.p90Drift = percentile(drift, 0.9);
    s.maxDrift = *std::max_element(drift.begin(), drift.end());
    s.fractionUnder10 = static_cast<double>(under10) / n;
    s.medianEndError = percentile(endErr, 0.5);
    s.p90EndError = percentile(endErr, 0.9);
    s.medianHoldDrift = percentile(hold, 0.5);
    s.coverage3Sigma = static_cast<double>(covered) / n;
    if (!heading.empty()) s.medianHeadingError = percentile(heading, 0.5);
    return s;
}

// ---------------------------------------------------------------- stream inspection

struct Streams {
    TruthTrack truth;
    double first{0.0}, last{0.0};
};

void inspect(const std::vector<SensorEvent>& events, ReplayReport& report, Streams& streams) {
    std::vector<double> dts;
    double prevImu = 0.0;
    bool haveImu = false;
    double sumF = 0.0;
    std::size_t nF = 0;
    streams.first = events.empty() ? 0.0 : eventTime(events.front());
    streams.last = events.empty() ? 0.0 : eventTime(events.back());
    for (const SensorEvent& e : events) {
        if (const auto* s = std::get_if<ImuSample>(&e)) {
            ++report.imuCount;
            if (haveImu) dts.push_back(s->t - prevImu);
            prevImu = s->t;
            haveImu = true;
            if (nF < 500) {
                sumF += norm(s->accel);
                ++nF;
            }
        } else if (std::holds_alternative<GnssFix>(e)) {
            ++report.gnssCount;
        } else {
            const auto& p = std::get<TruthPoint>(e);
            ++report.truthCount;
            streams.truth.t.push_back(p.t);
            streams.truth.lat.push_back(p.lat);
            streams.truth.lon.push_back(p.lon);
        }
    }
    report.firstTime = streams.first;
    report.duration = streams.last - streams.first;
    const double dt = percentile(dts, 0.5);
    report.imuRateHz = dt > 0.0 ? 1.0 / dt : 0.0;
    if (report.imuCount == 0) report.warnings.emplace_back("no IMU samples in the stream");
    if (nF > 0 && (sumF / static_cast<double>(nF) < 7.0 || sumF / static_cast<double>(nF) > 12.0))
        report.warnings.emplace_back("mean |accelerometer| over the first samples is " + std::to_string(sumF / static_cast<double>(nF)) +
                                     " m/s^2, expected about 9.8: are the units g instead of m/s^2?");
    if (report.gnssCount == 0) report.warnings.emplace_back("no GNSS fixes: the engine cannot align or aim");
    if (report.truthCount == 0) report.warnings.emplace_back("no truth track: errors and drift are not computed");
}

// ---------------------------------------------------------------- passes over the stream

struct Snapshot {
    NavEngine engine;
    std::size_t nextEvent{0};
    NavOutput at;
};

// One pass; GNSS in [deniedFrom, deniedTo) is withheld. Optionally takes engine copies
// for the sweep (every stride, once aligned and settled, while a full window still fits).
Trajectory runPass(const std::vector<SensorEvent>& events, const EngineConfig& cfg, double deniedFrom, double deniedTo,
                   const ReplayOptions* sweep, double windowMax, double lastTime, std::vector<Snapshot>* snapshots,
                   std::vector<bool>* deniedFlags, EngineStats* stats) {
    NavEngine engine(cfg);
    Trajectory traj;
    double nextStart = std::numeric_limits<double>::quiet_NaN();
    for (std::size_t i = 0; i < events.size(); ++i) {
        const SensorEvent& e = events[i];
        if (const auto* imu = std::get_if<ImuSample>(&e)) {
            engine.pushImu(*imu);
            const NavOutput out = engine.output();
            if (!out.valid) continue;
            traj.push_back(out);
            if (deniedFlags) deniedFlags->push_back(imu->t >= deniedFrom && imu->t < deniedTo);
            if (!sweep || !snapshots || !engine.aligned()) continue;
            if (std::isnan(nextStart)) nextStart = engine.stats().alignedAt + sweep->sweepSettle;
            if (imu->t >= nextStart && imu->t + windowMax <= lastTime) {
                snapshots->push_back({engine, i + 1, out});
                nextStart = imu->t + sweep->sweepStride;
            }
        } else if (const auto* gnss = std::get_if<GnssFix>(&e)) {
            if (!(gnss->t >= deniedFrom && gnss->t < deniedTo)) engine.pushGnss(*gnss);
        }
    }
    if (stats) *stats = engine.stats();
    return traj;
}

Trajectory runFork(Snapshot snap, const std::vector<SensorEvent>& events, double until) {
    Trajectory traj{snap.at};
    for (std::size_t i = snap.nextEvent; i < events.size(); ++i) {
        if (eventTime(events[i]) > until) break;
        if (const auto* imu = std::get_if<ImuSample>(&events[i])) {
            snap.engine.pushImu(*imu);
            const NavOutput out = snap.engine.output();
            if (out.valid) traj.push_back(out);
        }
    }
    return traj;
}

ContinuousError continuousError(const Trajectory& traj, const TruthTrack& truth, double from, double skipFrom,
                                double skipTo) {
    std::vector<double> errors;
    double ela = 0, elo = 0;
    for (std::size_t k = 0; k < truth.t.size(); ++k) {
        const double t = truth.t[k];
        if (t < from || (t >= skipFrom && t < skipTo)) continue;
        if (enginePosition(traj, t, ela, elo)) errors.push_back(metersBetween(ela, elo, truth.lat[k], truth.lon[k]));
    }
    ContinuousError c;
    c.samples = errors.size();
    if (errors.empty()) return c;
    c.median = percentile(errors, 0.5);
    c.p95 = percentile(errors, 0.95);
    c.max = *std::max_element(errors.begin(), errors.end());
    return c;
}

}  // namespace

ReplayReport runReplay(const std::vector<SensorEvent>& events, const ReplayOptions& options) {
    ReplayReport report;
    Streams streams;
    inspect(events, report, streams);
    if (report.imuCount == 0) return report;

    const bool scripted = options.outageStart >= 0.0 && options.outageLength > 0.0;
    const double deniedFrom = scripted ? streams.first + options.outageStart : 1e300;
    const double deniedTo = scripted ? deniedFrom + options.outageLength : 1e300;
    const double windowMax =
        options.sweepLengths.empty() ? 0.0 : *std::max_element(options.sweepLengths.begin(), options.sweepLengths.end());

    // Main pass without GNSS loss; with a sweep it also spawns the outage forks.
    std::vector<Snapshot> snapshots;
    const Trajectory clean = runPass(events, options.config, 1e300, 1e300, windowMax > 0.0 ? &options : nullptr, windowMax,
                                     streams.last, &snapshots, nullptr, &report.stats);
    if (scripted) {
        report.trajectory = runPass(events, options.config, deniedFrom, deniedTo, nullptr, 0.0, streams.last, nullptr,
                                    &report.denied, nullptr);
        report.hasScripted = true;
        report.scripted = evaluateWindow(report.trajectory, streams.truth, streams.first, deniedFrom, options.outageLength,
                                         options.minDistance);
    } else {
        report.trajectory = clean;
        report.denied.assign(clean.size(), false);
    }
    if (report.truthCount > 0 && !clean.empty()) {
        const double from = std::isfinite(report.stats.alignedAt) ? report.stats.alignedAt + options.sweepSettle : streams.first;
        report.continuous = continuousError(report.trajectory, streams.truth, from, deniedFrom, deniedTo + 5.0);
    }
    for (const Snapshot& snap : snapshots) {
        const Trajectory fork = runFork(snap, events, snap.at.t + windowMax);
        for (double length : options.sweepLengths)
            report.windows.push_back(evaluateWindow(fork, streams.truth, streams.first, snap.at.t, length, options.minDistance));
    }
    for (double length : options.sweepLengths) report.summaries.push_back(summarize(report.windows, length));
    return report;
}

}  // namespace gati

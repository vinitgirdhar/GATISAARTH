#include <cmath>
#include <cstdio>
#include <ostream>
#include <sstream>

#include "engine/replay.h"

namespace gati {

namespace {

std::string num(double v, int digits = 4) {
    if (!std::isfinite(v)) return "null";
    char buf[48];
    std::snprintf(buf, sizeof buf, "%.*g", digits + 4, v);
    return buf;
}

std::string escape(const std::string& s) {
    std::string out;
    for (char c : s) {
        if (c == '"' || c == '\\') out += '\\';
        out += c;
    }
    return out;
}

std::string updateJson(const UpdateCounter& c) {
    std::ostringstream o;
    o << "{\"accepted\":" << c.accepted << ",\"rejected\":" << c.rejected << ",\"failed\":" << c.failed
      << ",\"mean_nis\":" << num(c.meanNis()) << "}";
    return o.str();
}

std::string windowJson(const WindowResult& w) {
    std::ostringstream o;
    o << "{\"start_s\":" << num(w.start) << ",\"length_s\":" << num(w.length) << ",\"scored\":" << (w.scored ? "true" : "false");
    if (!w.scored) {
        o << ",\"skip_reason\":\"" << escape(w.skipReason) << "\"}";
        return o.str();
    }
    o << ",\"distance_m\":" << num(w.distance) << ",\"end_error_m\":" << num(w.endError)
      << ",\"start_error_m\":" << num(w.startError) << ",\"max_error_m\":" << num(w.maxError)
      << ",\"drift_percent\":" << num(w.driftPercent) << ",\"hold_velocity_error_m\":" << num(w.holdError)
      << ",\"hold_velocity_drift_percent\":" << num(w.holdDriftPercent) << ",\"heading_error_deg\":" << num(w.headingError)
      << ",\"engine_sigma_end_m\":" << num(w.sigmaEnd) << "}";
    return o.str();
}

std::string summaryJson(const LengthSummary& s) {
    std::ostringstream o;
    o << "{\"length_s\":" << num(s.length) << ",\"windows_scored\":" << s.scored << ",\"windows_skipped\":" << s.skipped
      << ",\"drift_percent\":{\"median\":" << num(s.medianDrift) << ",\"mean\":" << num(s.meanDrift)
      << ",\"p90\":" << num(s.p90Drift) << ",\"max\":" << num(s.maxDrift) << "}"
      << ",\"fraction_windows_under_10_percent\":" << num(s.fractionUnder10)
      << ",\"end_error_m\":{\"median\":" << num(s.medianEndError) << ",\"p90\":" << num(s.p90EndError) << "}"
      << ",\"hold_velocity_median_drift_percent\":" << num(s.medianHoldDrift)
      << ",\"coverage_3_sigma\":" << num(s.coverage3Sigma) << ",\"median_heading_error_deg\":" << num(s.medianHeadingError)
      << "}";
    return o.str();
}

}  // namespace

void writeTrajectoryCsv(std::ostream& out, const ReplayReport& r) {
    out << "t,lat,lon,alt,speed,heading_deg,roll_deg,pitch_deg,sigma_h_m,sigma_heading_deg,mode,gnss_denied\n";
    char buf[320];
    for (std::size_t i = 0; i < r.trajectory.size(); ++i) {
        const NavOutput& o = r.trajectory[i];
        std::snprintf(buf, sizeof buf, "%.4f,%.9f,%.9f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%s,%d\n", o.t - r.firstTime, o.lat,
                      o.lon, o.alt, o.speed, o.headingDeg, o.rollDeg, o.pitchDeg, o.sigmaHoriz, o.sigmaHeadingDeg,
                      toString(o.mode), i < r.denied.size() && r.denied[i] ? 1 : 0);
        out << buf;
    }
}

void writeWindowsCsv(std::ostream& out, const ReplayReport& r) {
    out << "start_s,length_s,scored,skip_reason,distance_m,end_error_m,start_error_m,max_error_m,drift_percent,hold_error_m,"
           "hold_drift_percent,heading_error_deg,sigma_end_m\n";
    char buf[320];
    for (const WindowResult& w : r.windows) {
        std::snprintf(buf, sizeof buf, "%.1f,%.0f,%d,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f\n", w.start, w.length, w.scored ? 1 : 0,
                      w.skipReason.c_str(), w.distance, w.endError, w.startError, w.maxError, w.driftPercent, w.holdError,
                      w.holdDriftPercent, w.headingError, w.sigmaEnd);
        out << buf;
    }
}

void printSummary(std::ostream& out, const ReplayReport& r, const ReplayOptions& options) {
    char buf[400];
    std::snprintf(buf, sizeof buf, "stream: imu=%zu gnss=%zu truth=%zu duration=%.1f s imu_rate=%.2f Hz\n", r.imuCount,
                  r.gnssCount, r.truthCount, r.duration, r.imuRateHz);
    out << buf;
    for (const std::string& w : r.warnings) out << "warning: " << w << "\n";
    std::snprintf(buf, sizeof buf,
                  "engine: aligned at t=%.1f s | imu used=%llu invalid=%llu out_of_order=%llu gaps=%llu | gnss pos acc=%llu rej=%llu resets=%llu "
                  "(mean NIS %.2f, ideal 2) vel acc=%llu rej=%llu | nhc=%llu zupt=%llu zaru=%llu\n",
                  std::isfinite(r.stats.alignedAt) ? r.stats.alignedAt - r.firstTime : -1.0,
                  static_cast<unsigned long long>(r.stats.imuUsed), static_cast<unsigned long long>(r.stats.imuInvalid),
                  static_cast<unsigned long long>(r.stats.imuOutOfOrder), static_cast<unsigned long long>(r.stats.imuGaps),
                  static_cast<unsigned long long>(r.stats.gnssPosition.accepted),
                  static_cast<unsigned long long>(r.stats.gnssPosition.rejected),
                  static_cast<unsigned long long>(r.stats.gnssResets), r.stats.gnssPosition.meanNis(),
                  static_cast<unsigned long long>(r.stats.gnssVelocity.accepted),
                  static_cast<unsigned long long>(r.stats.gnssVelocity.rejected),
                  static_cast<unsigned long long>(r.stats.nhc.accepted), static_cast<unsigned long long>(r.stats.zupt.accepted),
                  static_cast<unsigned long long>(r.stats.zaru.accepted));
    out << buf;
    if (r.continuous.samples > 0) {
        std::snprintf(buf, sizeof buf, "with GNSS: position error vs truth median %.2f m, p95 %.2f m, max %.2f m (%zu samples)\n",
                      r.continuous.median, r.continuous.p95, r.continuous.max, r.continuous.samples);
        out << buf;
    }
    if (r.hasScripted) {
        const WindowResult& w = r.scripted;
        if (!w.scored) {
            out << "scripted outage: not scored (" << w.skipReason << ")\n";
        } else {
            std::snprintf(buf, sizeof buf,
                          "scripted outage t=%.0f..%.0f s: distance %.1f m, error at end %.2f m -> drift %.2f %% (max error %.2f m, hold-velocity "
                          "baseline %.2f %%), heading error %.1f deg, engine 1-sigma %.1f m\n",
                          w.start, w.start + w.length, w.distance, w.endError, w.driftPercent, w.maxError, w.holdDriftPercent,
                          w.headingError, w.sigmaEnd);
            out << buf;
        }
    }
    if (!r.summaries.empty()) {
        std::snprintf(buf, sizeof buf, "sweep (stride %.0f s, settle %.0f s after alignment, >= %.0f m travelled):\n",
                      options.sweepStride, options.sweepSettle, options.minDistance);
        out << buf;
        out << "  len[s] scored skip | drift%% median  mean   p90   max | <10%% | end err m med  p90 | hold%% med | 3sig | hdg deg med\n";
        for (const LengthSummary& s : r.summaries) {
            std::snprintf(buf, sizeof buf, "  %6.0f %6zu %4zu | %13.1f %5.1f %5.1f %5.1f | %3.0f%% | %14.1f %5.1f | %8.1f | %3.0f%% | %6.1f\n",
                          s.length, s.scored, s.skipped, s.medianDrift, s.meanDrift, s.p90Drift, s.maxDrift,
                          100.0 * s.fractionUnder10, s.medianEndError, s.p90EndError, s.medianHoldDrift, 100.0 * s.coverage3Sigma,
                          std::isfinite(s.medianHeadingError) ? s.medianHeadingError : -1.0);
            out << buf;
        }
    }
}

std::string toJson(const ReplayReport& r, const ReplayOptions& options) {
    std::ostringstream o;
    o << "{\"stream\":{\"imu\":" << r.imuCount << ",\"gnss\":" << r.gnssCount << ",\"truth\":" << r.truthCount
      << ",\"duration_s\":" << num(r.duration) << ",\"imu_rate_hz\":" << num(r.imuRateHz) << "},\"warnings\":[";
    for (std::size_t i = 0; i < r.warnings.size(); ++i) o << (i ? "," : "") << "\"" << escape(r.warnings[i]) << "\"";
    o << "],\"engine\":{\"aligned_at_s\":" << num(std::isfinite(r.stats.alignedAt) ? r.stats.alignedAt - r.firstTime : kNoValue)
      << ",\"imu_used\":" << r.stats.imuUsed << ",\"imu_invalid\":" << r.stats.imuInvalid
      << ",\"imu_out_of_order\":" << r.stats.imuOutOfOrder << ",\"imu_gaps\":" << r.stats.imuGaps
      << ",\"diverged\":" << r.stats.diverged << ",\"gnss_resets\":" << r.stats.gnssResets
      << ",\"gnss_position\":" << updateJson(r.stats.gnssPosition) << ",\"gnss_velocity\":" << updateJson(r.stats.gnssVelocity)
      << ",\"gnss_altitude\":" << updateJson(r.stats.gnssAltitude) << ",\"nhc\":" << updateJson(r.stats.nhc)
      << ",\"zupt\":" << updateJson(r.stats.zupt) << ",\"zaru\":" << updateJson(r.stats.zaru) << "}"
      << ",\"continuous_error_m\":{\"samples\":" << r.continuous.samples << ",\"median\":" << num(r.continuous.median)
      << ",\"p95\":" << num(r.continuous.p95) << ",\"max\":" << num(r.continuous.max) << "}";
    if (r.hasScripted) o << ",\"scripted_window\":" << windowJson(r.scripted);
    o << ",\"sweep\":{\"stride_s\":" << num(options.sweepStride) << ",\"settle_s\":" << num(options.sweepSettle)
      << ",\"min_distance_m\":" << num(options.minDistance) << ",\"lengths\":[";
    for (std::size_t i = 0; i < r.summaries.size(); ++i) o << (i ? "," : "") << summaryJson(r.summaries[i]);
    o << "]}}";
    return o.str();
}

}  // namespace gati

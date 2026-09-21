#pragma once

// Replays a recorded sensor stream through the navigation engine and scores it against
// a ground-truth track: continuous error with GNSS, and the SIH metric, the position
// drift as a percentage of the distance travelled while GNSS is withheld.
//
// Two ways to withhold GNSS:
//  * a scripted window (outageStart/outageLength, seconds since the first event): one
//    pass with the fixes dropped, trajectory recorded;
//  * a sweep: one normal pass, and at every stride the engine is COPIED and run on
//    without GNSS for the longest window, then scored at each requested length.
//    The engine cannot see the future, so its state 10 s into a 120 s window equals
//    its state at the end of a 10 s one.
// Truth is used only for scoring; the engine never sees it.

#include <iosfwd>
#include <string>
#include <vector>

#include "engine/engine_config.h"
#include "engine/nav_engine.h"
#include "engine/sensor_types.h"

namespace gati {

struct ReplayOptions {
    EngineConfig config;
    double outageStart{-1.0};                 // s since first event; < 0 = no scripted window
    double outageLength{0.0};                 // s
    std::vector<double> sweepLengths;         // window lengths for the sweep, empty = no sweep
    double sweepStride{20.0};                 // s between window starts
    double sweepSettle{10.0};                 // s after alignment before the first window
    double minDistance{30.0};                 // m of truth travel below which a window is skipped
};

struct WindowResult {
    double start{0.0}, length{0.0};           // s since first event
    double distance{0.0};                     // truth path length, m
    double endError{0.0}, startError{0.0}, maxError{0.0};   // m
    double holdError{0.0};                    // m, hold-last-velocity baseline
    double headingError{kNoValue};            // deg at the end, NaN if truth speed too low
    double sigmaEnd{0.0};                     // m, engine's own 1-sigma at the end
    double driftPercent{0.0}, holdDriftPercent{0.0};
    bool scored{false};
    std::string skipReason;
};

struct LengthSummary {
    double length{0.0};
    std::size_t scored{0}, skipped{0};
    double medianDrift{0.0}, meanDrift{0.0}, p90Drift{0.0}, maxDrift{0.0};   // percent
    double fractionUnder10{0.0};              // of scored windows with drift < 10 %
    double medianEndError{0.0}, p90EndError{0.0};                             // m
    double medianHoldDrift{0.0};              // percent, hold-last-velocity baseline
    double coverage3Sigma{0.0};               // fraction with endError <= 3 * sigmaEnd
    double medianHeadingError{kNoValue};      // deg
};

struct ContinuousError {
    std::size_t samples{0};
    double median{0.0}, p95{0.0}, max{0.0};   // m, engine vs truth while GNSS is on
};

struct ReplayReport {
    std::size_t imuCount{0}, gnssCount{0}, truthCount{0};
    double duration{0.0}, imuRateHz{0.0};
    std::vector<std::string> warnings;
    EngineStats stats;                        // of the main pass
    std::vector<NavOutput> trajectory;        // one per IMU sample (masked pass if scripted)
    std::vector<bool> denied;                 // parallel to trajectory: GNSS withheld here
    ContinuousError continuous;
    bool hasScripted{false};
    WindowResult scripted;
    std::vector<WindowResult> windows;
    std::vector<LengthSummary> summaries;     // one per sweep length
    double firstTime{0.0};
};

ReplayReport runReplay(const std::vector<SensorEvent>& events, const ReplayOptions& options);

void writeTrajectoryCsv(std::ostream& out, const ReplayReport& report);
void writeWindowsCsv(std::ostream& out, const ReplayReport& report);   // one row per sweep window
void printSummary(std::ostream& out, const ReplayReport& report, const ReplayOptions& options);
std::string toJson(const ReplayReport& report, const ReplayOptions& options);

}  // namespace gati

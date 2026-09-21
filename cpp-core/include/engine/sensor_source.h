#pragma once

// Input abstraction for the edge engine. Anything that can produce time-ordered
// SensorEvents (a CSV file, a pipe from a USB-IMU driver, a ROS bridge, a UDP
// receiver) implements ISensorSource; the engine never sees the transport.
//
// CsvSensorSource is the reference implementation. One row may carry any subset of
// three groups, so streams at different rates share one file:
//
//   t                         seconds, any origin, non-decreasing
//   ax ay az gx gy gz         IMU: m/s^2 specific force, rad/s      (all six or none)
//   mx my mz                  magnetometer, microtesla (optional, carried, unused)
//   gnss_lat gnss_lon         degrees                               (both or neither)
//   gnss_alt gnss_speed gnss_course gnss_acc   optional: m, m/s, deg clockwise from
//                             north, 1-sigma horizontal position error in m
//   truth_lat truth_lon       degrees: ground truth for scoring only (both or neither)
//
// Header names are case-insensitive, column order is free, unknown columns are ignored,
// '#' starts a comment line, an empty cell means "absent", fields are not quoted.

#include <deque>
#include <iosfwd>
#include <string>
#include <unordered_map>
#include <vector>

#include "engine/sensor_types.h"

namespace gati {

// Axis convention of the IMU columns. FLU = x forward, y left, z up (ROS REP-103, most
// USB IMUs, an Android phone lying flat: a resting IMU reads az = +9.8). FRD = x forward,
// y right, z down (aerospace: a resting IMU reads az = -9.8). The engine works in FRD.
enum class AxisConvention { Flu, Frd };

class ISensorSource {
public:
    virtual ~ISensorSource() = default;
    // Next event in time order. Returns false at end of stream or on failure; a failure
    // leaves a non-empty error() (with the line number for file-based sources).
    virtual bool next(SensorEvent& event) = 0;
    virtual const std::string& error() const = 0;
};

class CsvSensorSource : public ISensorSource {
public:
    explicit CsvSensorSource(std::istream& in, AxisConvention axes = AxisConvention::Flu);
    bool next(SensorEvent& event) override;
    const std::string& error() const override { return error_; }

private:
    bool readHeader();
    bool parseRow(const std::string& line);
    bool fail(const std::string& message);

    std::istream& in_;
    AxisConvention axes_;
    std::unordered_map<std::string, int> columns_;
    std::deque<SensorEvent> pending_;
    std::string error_;
    std::size_t line_{0};
    double lastTime_{-1e300};
    bool headerRead_{false};
};

struct LoadedStream {
    std::vector<SensorEvent> events;
    std::string error;   // empty when the whole stream was read
};

LoadedStream loadAll(ISensorSource& source);

// Writes events in the CSV format above (one event per row, FLU or FRD as asked).
void writeCsv(std::ostream& out, const std::vector<SensorEvent>& events, AxisConvention axes = AxisConvention::Flu);

}  // namespace gati

#include "engine/sensor_source.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <istream>
#include <optional>
#include <ostream>
#include <sstream>

namespace gati {

namespace {

std::string trim(const std::string& s) {
    std::size_t a = 0, b = s.size();
    while (a < b && std::isspace(static_cast<unsigned char>(s[a]))) ++a;
    while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1]))) --b;
    return s.substr(a, b - a);
}

std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

std::vector<std::string> split(const std::string& line) {
    std::vector<std::string> out;
    std::string field;
    std::istringstream ss(line);
    while (std::getline(ss, field, ',')) out.push_back(trim(field));
    if (!line.empty() && line.back() == ',') out.emplace_back();
    return out;
}

// A cell as a number: nullopt for an empty cell, false in `ok` for text that is not one.
std::optional<double> number(const std::string& cell, bool& ok) {
    ok = true;
    if (cell.empty()) return std::nullopt;
    char* end = nullptr;
    const double v = std::strtod(cell.c_str(), &end);
    if (end == cell.c_str() || *end != '\0') {
        ok = false;
        return std::nullopt;
    }
    return v;
}

constexpr const char* kKnown[] = {"t",  "ax", "ay", "az", "gx", "gy", "gz", "mx", "my", "mz",
                                  "gnss_lat", "gnss_lon", "gnss_alt", "gnss_speed", "gnss_course", "gnss_acc",
                                  "truth_lat", "truth_lon"};

}  // namespace

CsvSensorSource::CsvSensorSource(std::istream& in, AxisConvention axes) : in_(in), axes_(axes) {}

bool CsvSensorSource::fail(const std::string& message) {
    error_ = "line " + std::to_string(line_) + ": " + message;
    return false;
}

bool CsvSensorSource::readHeader() {
    std::string line;
    while (std::getline(in_, line)) {
        ++line_;
        if (line_ == 1 && line.size() >= 3 && line.compare(0, 3, "\xEF\xBB\xBF") == 0) line.erase(0, 3);
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;
        const std::vector<std::string> names = split(line);
        for (std::size_t i = 0; i < names.size(); ++i) {
            const std::string name = lower(names[i]);
            if (std::find(std::begin(kKnown), std::end(kKnown), name) != std::end(kKnown))
                columns_[name] = static_cast<int>(i);
        }
        headerRead_ = true;
        if (columns_.find("t") == columns_.end()) return fail("header has no 't' column");
        return true;
    }
    return fail("no header row");
}

bool CsvSensorSource::parseRow(const std::string& line) {
    const std::vector<std::string> cells = split(line);
    bool ok = true;
    // value(name): nullopt if the column is absent or the cell empty; sets ok=false on garbage.
    auto value = [&](const char* name) -> std::optional<double> {
        const auto it = columns_.find(name);
        if (it == columns_.end() || static_cast<std::size_t>(it->second) >= cells.size()) return std::nullopt;
        bool cellOk = true;
        const std::optional<double> v = number(cells[static_cast<std::size_t>(it->second)], cellOk);
        if (!cellOk) {
            ok = false;
            error_ = std::string("line ") + std::to_string(line_) + ": '" + cells[static_cast<std::size_t>(it->second)] +
                     "' in column " + name + " is not a number";
        }
        return v;
    };
    const std::optional<double> t = value("t");
    if (!ok) return false;
    if (!t || !std::isfinite(*t)) return fail("missing or non-finite time");
    if (*t < lastTime_) return fail("time goes backwards (" + std::to_string(*t) + " < " + std::to_string(lastTime_) + ")");
    lastTime_ = *t;

    const char* imuNames[6] = {"ax", "ay", "az", "gx", "gy", "gz"};
    std::optional<double> imu[6];
    int imuCount = 0;
    for (int i = 0; i < 6; ++i) {
        imu[i] = value(imuNames[i]);
        imuCount += imu[i].has_value();
    }
    const std::optional<double> gLat = value("gnss_lat"), gLon = value("gnss_lon");
    const std::optional<double> tLat = value("truth_lat"), tLon = value("truth_lon");
    if (!ok) return false;
    if (imuCount != 0 && imuCount != 6) return fail("incomplete IMU group (need all of ax ay az gx gy gz)");
    if (gLat.has_value() != gLon.has_value()) return fail("incomplete GNSS group (need gnss_lat and gnss_lon)");
    if (tLat.has_value() != tLon.has_value()) return fail("incomplete truth group (need truth_lat and truth_lon)");
    if (imuCount == 0 && !gLat && !tLat) return fail("row carries no IMU, GNSS or truth data");

    if (imuCount == 6) {
        // Engine frame is FRD; FLU -> FRD flips y and z.
        const double flip = axes_ == AxisConvention::Flu ? -1.0 : 1.0;
        ImuSample s;
        s.t = *t;
        s.accel = {*imu[0], flip * *imu[1], flip * *imu[2]};
        s.gyro = {*imu[3], flip * *imu[4], flip * *imu[5]};
        const std::optional<double> mx = value("mx"), my = value("my"), mz = value("mz");
        if (mx && my && mz) {
            s.mag = {*mx, flip * *my, flip * *mz};
            s.hasMag = true;
        }
        pending_.emplace_back(s);
    }
    if (gLat) {
        GnssFix g;
        g.t = *t;
        g.lat = *gLat;
        g.lon = *gLon;
        g.alt = value("gnss_alt").value_or(kNoValue);
        g.speed = value("gnss_speed").value_or(kNoValue);
        g.course = value("gnss_course").value_or(kNoValue);
        g.accuracy = value("gnss_acc").value_or(g.accuracy);
        pending_.emplace_back(g);
    }
    if (tLat) pending_.emplace_back(TruthPoint{*t, *tLat, *tLon});
    return ok;
}

bool CsvSensorSource::next(SensorEvent& event) {
    while (pending_.empty()) {
        if (!error_.empty()) return false;
        if (!headerRead_ && !readHeader()) return false;
        std::string line;
        bool got = false;
        while (std::getline(in_, line)) {
            ++line_;
            line = trim(line);
            if (line.empty() || line[0] == '#') continue;
            got = true;
            break;
        }
        if (!got) return false;
        if (!parseRow(line)) return false;
    }
    event = pending_.front();
    pending_.pop_front();
    return true;
}

LoadedStream loadAll(ISensorSource& source) {
    LoadedStream out;
    SensorEvent e;
    while (source.next(e)) out.events.push_back(e);
    out.error = source.error();
    return out;
}

void writeCsv(std::ostream& out, const std::vector<SensorEvent>& events, AxisConvention axes) {
    out << "t,ax,ay,az,gx,gy,gz,gnss_lat,gnss_lon,gnss_alt,gnss_speed,gnss_course,gnss_acc,truth_lat,truth_lon\n";
    const double flip = axes == AxisConvention::Flu ? -1.0 : 1.0;
    char buf[320];
    for (const SensorEvent& e : events) {
        if (const auto* s = std::get_if<ImuSample>(&e)) {
            std::snprintf(buf, sizeof buf, "%.6f,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,,,,,,,,\n", s->t, s->accel.x,
                          flip * s->accel.y, flip * s->accel.z, s->gyro.x, flip * s->gyro.y, flip * s->gyro.z);
        } else if (const auto* g = std::get_if<GnssFix>(&e)) {
            char alt[32] = "", spd[32] = "", crs[32] = "";
            if (std::isfinite(g->alt)) std::snprintf(alt, sizeof alt, "%.3f", g->alt);
            if (std::isfinite(g->speed)) std::snprintf(spd, sizeof spd, "%.4f", g->speed);
            if (std::isfinite(g->course)) std::snprintf(crs, sizeof crs, "%.4f", g->course);
            std::snprintf(buf, sizeof buf, "%.6f,,,,,,,%.9f,%.9f,%s,%s,%s,%.3f,,\n", g->t, g->lat, g->lon, alt, spd, crs,
                          g->accuracy);
        } else {
            const auto& p = std::get<TruthPoint>(e);
            std::snprintf(buf, sizeof buf, "%.6f,,,,,,,,,,,,,%.9f,%.9f\n", p.t, p.lat, p.lon);
        }
        out << buf;
    }
}

}  // namespace gati

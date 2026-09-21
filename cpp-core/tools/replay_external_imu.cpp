// replay_external_imu: drive the standalone navigation engine from an external IMU/GNSS
// CSV (format: include/engine/sensor_source.h, cpp-core/README.md) and score it.
//
//   replay_external_imu --input drive.csv [--out traj.csv] [--json metrics.json]
//       [--outage-start 20 --outage-len 60] [--sweep 10,30,60,120 [--stride 20]]
//       [--axes flu|frd] [--set key=value ...]
//
// `--input -` reads standard input, so any process can pipe a live IMU stream in.

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "engine/replay.h"
#include "engine/sensor_source.h"

using namespace gati;

namespace {

struct Args {
    std::string input, out, json, windows;
    AxisConvention axes{AxisConvention::Flu};
    ReplayOptions options;
};

int usage() {
    std::fputs(
        "usage: replay_external_imu --input FILE|- [--out traj.csv] [--json metrics.json] [--windows windows.csv]\n"
        "         [--outage-start S --outage-len L] [--sweep L1,L2,...] [--stride S] [--settle S] [--min-distance M]\n"
        "         [--axes flu|frd] [--set key=value]...\n",
        stderr);
    return 2;
}

bool parseNumber(const std::string& s, double& v) {
    char* end = nullptr;
    v = std::strtod(s.c_str(), &end);
    return end != s.c_str() && *end == '\0';
}

bool parseList(const std::string& s, std::vector<double>& out) {
    std::istringstream ss(s);
    std::string item;
    while (std::getline(ss, item, ',')) {
        double v = 0.0;
        if (!parseNumber(item, v) || v <= 0.0) return false;
        out.push_back(v);
    }
    return !out.empty();
}

bool applySet(EngineConfig& cfg, const std::string& kv) {
    const std::size_t eq = kv.find('=');
    double v = 0.0;
    if (eq == std::string::npos || !parseNumber(kv.substr(eq + 1), v)) return false;
    return cfg.apply(kv.substr(0, eq), v);
}

// Returns an empty string on success, otherwise the reason.
std::string parseArgs(int argc, char** argv, Args& a) {
    std::vector<std::string> sets;
    for (int i = 1; i < argc; ++i) {
        const std::string k = argv[i];
        auto value = [&]() -> const char* { return i + 1 < argc ? argv[++i] : nullptr; };
        const char* v = nullptr;
        if (k == "--input" || k == "--out" || k == "--json" || k == "--windows" || k == "--axes" || k == "--outage-start" ||
            k == "--outage-len" || k == "--sweep" || k == "--stride" || k == "--settle" || k == "--min-distance" || k == "--set") {
            v = value();
            if (!v) return "missing value after " + k;
        } else {
            return "unknown argument " + k;
        }
        const std::string s = v;
        double d = 0.0;
        if (k == "--input") a.input = s;
        else if (k == "--out") a.out = s;
        else if (k == "--json") a.json = s;
        else if (k == "--windows") a.windows = s;
        else if (k == "--axes") {
            if (s != "flu" && s != "frd") return "--axes must be flu or frd";
            a.axes = s == "flu" ? AxisConvention::Flu : AxisConvention::Frd;
        } else if (k == "--sweep") {
            if (!parseList(s, a.options.sweepLengths)) return "--sweep needs positive numbers, e.g. 10,30,60,120";
        } else if (k == "--set") sets.push_back(s);
        else if (!parseNumber(s, d)) return "not a number: " + s;
        else if (k == "--outage-start") a.options.outageStart = d;
        else if (k == "--outage-len") a.options.outageLength = d;
        else if (k == "--stride") a.options.sweepStride = d;
        else if (k == "--settle") a.options.sweepSettle = d;
        else if (k == "--min-distance") a.options.minDistance = d;
    }
    for (const std::string& kv : sets)
        if (!applySet(a.options.config, kv)) return "bad --set " + kv + " (unknown key or value)";
    if (a.input.empty()) return "--input is required";
    return "";
}

bool writeFile(const std::string& path, const std::string& text) {
    std::ofstream f(path, std::ios::binary);
    f << text;
    return static_cast<bool>(f);
}

}  // namespace

int main(int argc, char** argv) {
    Args args;
    const std::string problem = parseArgs(argc, argv, args);
    if (!problem.empty()) {
        std::fprintf(stderr, "error: %s\n", problem.c_str());
        return usage();
    }

    std::ifstream file;
    std::istream* in = &std::cin;
    if (args.input != "-") {
        file.open(args.input, std::ios::binary);
        if (!file) {
            std::fprintf(stderr, "error: cannot open %s\n", args.input.c_str());
            return 3;
        }
        in = &file;
    }
    CsvSensorSource source(*in, args.axes);
    const LoadedStream stream = loadAll(source);
    if (!stream.error.empty()) {
        std::fprintf(stderr, "error: %s: %s\n", args.input.c_str(), stream.error.c_str());
        return 3;
    }

    const ReplayReport report = runReplay(stream.events, args.options);
    printSummary(std::cout, report, args.options);
    if (!args.out.empty()) {
        std::ostringstream ss;
        writeTrajectoryCsv(ss, report);
        if (!writeFile(args.out, ss.str())) {
            std::fprintf(stderr, "error: cannot write %s\n", args.out.c_str());
            return 3;
        }
    }
    if (!args.windows.empty()) {
        std::ostringstream ss;
        writeWindowsCsv(ss, report);
        if (!writeFile(args.windows, ss.str())) {
            std::fprintf(stderr, "error: cannot write %s\n", args.windows.c_str());
            return 3;
        }
    }
    if (!args.json.empty() && !writeFile(args.json, toJson(report, args.options) + "\n")) {
        std::fprintf(stderr, "error: cannot write %s\n", args.json.c_str());
        return 3;
    }
    return report.imuCount == 0 ? 3 : 0;
}

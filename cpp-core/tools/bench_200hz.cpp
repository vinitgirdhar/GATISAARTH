// bench_200hz: throughput, latency and buffer behaviour of the edge engine on a ~200 Hz
// IMU stream. Everything reported is measured by this program on the machine it runs on.
//
//   bench_200hz [--minutes 10] [--rate 200] [--paced-seconds 60] [--iovnbd-csv trip.csv]
//               [--noise 1|0] [--json out.json] [--smoke]
//
// Modes: (a) as fast as possible (throughput + per-sample processing latency),
//        (b) paced in real time (sleep to each sample's deadline, producer and consumer on
//            their own threads through the ring buffer),
//        (c) bursts: a 200 ms producer stall, a 200 ms consumer stall, and a stall longer
//            than the buffer (overflow) to show how drops are counted and survived.
// Input: a scripted synthetic vehicle, and (optionally) a real IO-VNBD trip converted by
// tools/iovnbd_to_external_imu.py and linearly interpolated from 10 Hz up to the rate.

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <memory>
#include <random>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "engine/edge_pipeline.h"
#include "engine/geo.h"
#include "engine/sensor_source.h"
#include "engine/synthetic.h"

#if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_IX86))
#include <intrin.h>
#endif
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#include <mmsystem.h>
#pragma comment(lib, "winmm.lib")
#endif

#ifdef _MSVC_LANG
constexpr long kCxxStandard = static_cast<long>(_MSVC_LANG);   // MSVC keeps __cplusplus at 199711
#else
constexpr long kCxxStandard = static_cast<long>(__cplusplus);
#endif

#ifndef GATI_BUILD_CONFIG
#define GATI_BUILD_CONFIG "unknown"
#endif
#ifndef GATI_CXX_FLAGS
#define GATI_CXX_FLAGS "unknown"
#endif

using namespace gati;
using Clock = std::chrono::steady_clock;

namespace {

// ---------------------------------------------------------------- small helpers

double toUs(Clock::duration d) { return std::chrono::duration<double, std::micro>(d).count(); }

struct Quantiles {
    double p50{0}, p95{0}, p99{0}, max{0}, mean{0};
    std::size_t n{0};
};

Quantiles quantiles(std::vector<double> v) {
    Quantiles q;
    q.n = v.size();
    if (v.empty()) return q;
    std::sort(v.begin(), v.end());
    auto at = [&](double p) { return v[static_cast<std::size_t>(p * static_cast<double>(v.size() - 1))]; };
    q.p50 = at(0.5);
    q.p95 = at(0.95);
    q.p99 = at(0.99);
    q.max = v.back();
    double s = 0.0;
    for (double x : v) s += x;
    q.mean = s / static_cast<double>(v.size());
    return q;
}

std::string quantilesJson(const Quantiles& q) {
    char b[240];
    std::snprintf(b, sizeof b, "{\"p50\":%.3f,\"p95\":%.3f,\"p99\":%.3f,\"max\":%.3f,\"mean\":%.3f,\"n\":%zu}", q.p50, q.p95,
                  q.p99, q.max, q.mean, q.n);
    return b;
}

std::string cpuModel() {
#if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_IX86))
    int r[4];
    __cpuid(r, static_cast<int>(0x80000000));
    if (static_cast<unsigned>(r[0]) < 0x80000004u) return "unknown";
    char brand[49] = {};
    for (int i = 0; i < 3; ++i) {
        __cpuid(r, static_cast<int>(0x80000002 + i));
        std::memcpy(brand + 16 * i, r, 16);
    }
    std::string s = brand;
    s.erase(0, s.find_first_not_of(' '));
    return s;
#else
    std::ifstream f("/proc/cpuinfo");
    std::string line;
    while (std::getline(f, line))
        if (line.rfind("model name", 0) == 0 && line.find(':') != std::string::npos) return line.substr(line.find(':') + 2);
    return "unknown";
#endif
}

std::string compilerId() {
#if defined(_MSC_VER)
    return "MSVC " + std::to_string(_MSC_FULL_VER);
#elif defined(__clang__)
    return std::string("clang ") + __clang_version__;
#elif defined(__GNUC__)
    return std::string("gcc ") + __VERSION__;
#else
    return "unknown";
#endif
}

// Windows sleeps in ~15.6 ms steps unless the timer resolution is raised for the process.
struct TimerResolution {
#ifdef _WIN32
    TimerResolution() { timeBeginPeriod(1); }
    ~TimerResolution() { timeEndPeriod(1); }
#endif
};

// Sleep most of the way, then spin the last stretch: accurate to microseconds, at the cost
// of one busy core while pacing (the pacer is the test fixture, not the engine).
void sleepUntil(Clock::time_point deadline) {
    for (;;) {
        const auto remaining = deadline - Clock::now();
        if (remaining <= Clock::duration::zero()) return;
        if (remaining > std::chrono::microseconds(2500)) std::this_thread::sleep_for(std::chrono::microseconds(1000));
        else std::this_thread::yield();
    }
}

// ---------------------------------------------------------------- input streams

struct Stream {
    std::string name;
    std::vector<SensorEvent> events;
    std::vector<TruthPoint> truth;
    double rate{200.0};
    double seconds{0.0};
    std::size_t imuCount() const {
        std::size_t n = 0;
        for (const SensorEvent& e : events) n += std::holds_alternative<ImuSample>(e);
        return n;
    }
};

Stream syntheticStream(double seconds, double rate, bool noise) {
    SyntheticConfig c;
    c.imuRateHz = rate;
    c.heading0Deg = 45.0;
    c.gnssRateHz = 1.0;
    c.truthRateHz = 1.0;
    const std::vector<Maneuver> cycle = {{20, 0.75, 0}, {60, 0, 0}, {15, 0, 3}, {40, 0, 0}, {15, 0, -3}, {30, 0, 0}, {20, -0.75, 0}, {10, 0, 0}};
    for (double t = 0.0; t < seconds; t += 210.0) c.plan.insert(c.plan.end(), cycle.begin(), cycle.end());
    if (noise) {
        c.accelNoiseStd = 0.02;
        c.gyroNoiseStd = 0.001;
        c.gnssPosNoiseStd = 2.0;
    }
    Stream s;
    s.name = "synthetic";
    s.rate = rate;
    s.seconds = seconds;
    for (const SensorEvent& e : generateDrive(c).events) {
        if (eventTime(e) > seconds) break;
        s.events.push_back(e);
        if (const auto* p = std::get_if<TruthPoint>(&e)) s.truth.push_back(*p);
    }
    return s;
}

// Linear interpolation of the 10 Hz IMU up to `rate` (only across gaps <= 0.25 s), plus
// optional white noise; GNSS and truth rows keep their original times.
Stream iovnbdStream(const std::string& path, double seconds, double rate, bool noise, std::string& error) {
    std::ifstream f(path, std::ios::binary);
    CsvSensorSource source(f, AxisConvention::Flu);
    const LoadedStream loaded = loadAll(source);
    Stream s;
    s.name = "iovnbd";
    s.rate = rate;
    s.seconds = seconds;
    // EOF is the expected state after loadAll. Only a failure to open, an I/O
    // error, or a parser error makes this stream invalid.
    if (!f.is_open() || f.bad() || !loaded.error.empty() || loaded.events.empty()) {
        error = path + ": " + (loaded.error.empty() ? "cannot read" : loaded.error);
        return s;
    }
    std::vector<ImuSample> imu;
    std::vector<SensorEvent> other;
    const double t0 = eventTime(loaded.events.front());
    for (const SensorEvent& e : loaded.events) {
        if (eventTime(e) - t0 > seconds) break;
        if (const auto* i = std::get_if<ImuSample>(&e)) imu.push_back(*i);
        else other.push_back(e);
    }
    std::mt19937 rng(7);
    std::normal_distribution<double> unit(0.0, 1.0);
    auto jitter = [&](double sigma) { return noise ? sigma * unit(rng) : 0.0; };
    std::vector<SensorEvent> merged;
    for (std::size_t k = 0; k + 1 < imu.size(); ++k) {
        const double dt = imu[k + 1].t - imu[k].t;
        const int n = dt > 0.0 && dt <= 0.25 ? std::max(1, static_cast<int>(std::lround(dt * rate))) : 1;
        for (int j = 0; j < n; ++j) {
            const double w = static_cast<double>(j) / n;
            ImuSample o = imu[k];
            o.t = imu[k].t + w * dt;
            o.accel = imu[k].accel * (1 - w) + imu[k + 1].accel * w + Vector3d{jitter(0.05), jitter(0.05), jitter(0.05)};
            o.gyro = imu[k].gyro * (1 - w) + imu[k + 1].gyro * w + Vector3d{jitter(0.002), jitter(0.002), jitter(0.002)};
            merged.emplace_back(o);
        }
    }
    merged.insert(merged.end(), other.begin(), other.end());
    std::stable_sort(merged.begin(), merged.end(), [](const SensorEvent& a, const SensorEvent& b) { return eventTime(a) < eventTime(b); });
    for (const SensorEvent& e : merged)
        if (const auto* p = std::get_if<TruthPoint>(&e)) s.truth.push_back(*p);
    s.events = std::move(merged);
    return s;
}

double finalErrorMeters(const Stream& s, const NavOutput& out) {
    if (!out.valid || s.truth.empty()) return -1.0;
    const auto it = std::lower_bound(s.truth.begin(), s.truth.end(), out.t, [](const TruthPoint& p, double t) { return p.t < t; });
    const TruthPoint& p = it == s.truth.end() ? s.truth.back() : *it;
    return geo::distanceMeters(out.lat * geo::kDegToRad, out.lon * geo::kDegToRad, p.lat * geo::kDegToRad, p.lon * geo::kDegToRad);
}

// ---------------------------------------------------------------- (a) as fast as possible

struct FlatOut {
    std::size_t samples{0};
    double wallSeconds{0.0}, throughput{0.0}, timerOverheadNs{0.0}, finalErrorM{-1.0};
    Quantiles latencyUs;
    PipelineStats pipe;
};

double measureTimerOverheadNs() {
    constexpr int kN = 2000000;
    double sum = 0.0;
    for (int i = 0; i < kN; ++i) {
        const auto a = Clock::now();
        const auto b = Clock::now();
        sum += std::chrono::duration<double, std::nano>(b - a).count();
    }
    return sum / kN;
}

FlatOut runFlatOut(const Stream& s) {
    FlatOut r;
    {   // untimed pass: honest throughput, no per-sample clock reads
        auto pipe = std::make_unique<EdgePipeline>();
        const auto t0 = Clock::now();
        for (const SensorEvent& e : s.events) {
            pipe->offer(e);
            pipe->processOne();
        }
        r.wallSeconds = std::chrono::duration<double>(Clock::now() - t0).count();
        r.pipe = pipe->stats();
        r.finalErrorM = finalErrorMeters(s, pipe->engine().output());
    }
    r.samples = s.imuCount();
    r.throughput = r.wallSeconds > 0.0 ? static_cast<double>(r.samples) / r.wallSeconds : 0.0;
    {   // timed pass: one clock pair around each engine call on an IMU sample
        auto pipe = std::make_unique<EdgePipeline>();
        std::vector<double> lat;
        lat.reserve(r.samples);
        for (const SensorEvent& e : s.events) {
            pipe->offer(e);
            const bool imu = std::holds_alternative<ImuSample>(e);
            const auto a = Clock::now();
            pipe->processOne();
            const auto b = Clock::now();
            if (imu) lat.push_back(toUs(b - a));
        }
        r.latencyUs = quantiles(std::move(lat));
    }
    r.timerOverheadNs = measureTimerOverheadNs();
    return r;
}

// ---------------------------------------------------------------- (b)/(c) paced with threads

struct Scenario {
    std::string name;
    double producerStallAt{-1.0}, producerStallLen{0.0};   // s into the run
    double consumerStallAt{-1.0}, consumerStallLen{0.0};
};

struct Paced {
    std::size_t samples{0}, misses{0}, offeredLate{0};
    double seconds{0.0}, periodMs{0.0}, recoveryMs{-1.0}, finalErrorM{-1.0};
    Quantiles endToEndUs, processUs, pacerLatenessUs;
    PipelineStats pipe;
};

struct Timing {
    std::vector<Clock::time_point> scheduled, offered, done;
    std::vector<double> processUs;
    explicit Timing(std::size_t n) : scheduled(n), offered(n), done(n), processUs(n, -1.0) {}
};

void producer(EdgePipeline& pipe, const Stream& s, Clock::time_point start, const Scenario& sc, Timing& tm) {
    const double t0 = eventTime(s.events.front());
    std::size_t idx = 0;
    bool stalled = false;
    for (const SensorEvent& src : s.events) {
        SensorEvent e = src;
        auto* imu = std::get_if<ImuSample>(&e);
        if (!imu) {
            pipe.offer(e);
            continue;
        }
        const auto deadline = start + std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(imu->t - t0));
        if (!stalled && sc.producerStallAt >= 0.0 && imu->t - t0 >= sc.producerStallAt) {
            stalled = true;   // the sensor driver goes quiet; samples queue up behind it in "the hardware"
            std::this_thread::sleep_for(std::chrono::duration<double>(sc.producerStallLen));
        }
        sleepUntil(deadline);
        imu->mag.x = static_cast<double>(idx);   // sequence tag (mag is unused by the engine)
        tm.scheduled[idx] = deadline;
        tm.offered[idx] = Clock::now();
        pipe.offer(e);
        ++idx;
    }
}

void consumer(EdgePipeline& pipe, std::atomic<bool>& done, Clock::time_point start, const Scenario& sc, Timing& tm,
              Clock::time_point& recoveredAt) {
    bool stalled = false, recovering = false;
    SensorEvent e;
    for (;;) {
        const double elapsed = std::chrono::duration<double>(Clock::now() - start).count();
        if (!stalled && sc.consumerStallAt >= 0.0 && elapsed >= sc.consumerStallAt) {
            stalled = true;
            std::this_thread::sleep_for(std::chrono::duration<double>(sc.consumerStallLen));
            recovering = true;
        }
        const auto a = Clock::now();
        if (pipe.processOne(&e)) {
            const auto b = Clock::now();
            if (const auto* imu = std::get_if<ImuSample>(&e)) {
                const std::size_t idx = static_cast<std::size_t>(imu->mag.x);
                tm.done[idx] = b;
                tm.processUs[idx] = toUs(b - a);
            }
            if (recovering && pipe.occupancy() <= 1) {
                recoveredAt = b;
                recovering = false;
            }
        } else if (done.load(std::memory_order_acquire) && pipe.occupancy() == 0) {
            return;
        } else {
            std::this_thread::yield();
        }
    }
}

Paced runPaced(const Stream& s, double seconds, const Scenario& sc) {
    Stream cut;
    for (const SensorEvent& e : s.events)
        if (eventTime(e) - eventTime(s.events.front()) <= seconds) cut.events.push_back(e);
    cut.truth = s.truth;
    Paced r;
    r.seconds = seconds;
    r.periodMs = 1000.0 / s.rate;
    r.samples = cut.imuCount();
    Timing tm(r.samples);
    auto pipe = std::make_unique<EdgePipeline>();
    std::atomic<bool> done{false};
    Clock::time_point recoveredAt{};
    const auto start = Clock::now() + std::chrono::milliseconds(50);
    std::thread cons(consumer, std::ref(*pipe), std::ref(done), start, std::cref(sc), std::ref(tm), std::ref(recoveredAt));
    std::thread prod(producer, std::ref(*pipe), std::cref(cut), start, std::cref(sc), std::ref(tm));
    prod.join();
    done.store(true, std::memory_order_release);
    cons.join();

    std::vector<double> e2e, proc, lateness;
    const auto period = std::chrono::duration<double, std::milli>(r.periodMs);
    for (std::size_t i = 0; i < r.samples; ++i) {
        if (tm.processUs[i] < 0.0) continue;   // dropped by a full queue
        const double lag = toUs(tm.done[i] - tm.scheduled[i]);
        e2e.push_back(lag);
        proc.push_back(tm.processUs[i]);
        lateness.push_back(toUs(tm.offered[i] - tm.scheduled[i]));
        r.misses += lag > period.count() * 1000.0;
    }
    r.endToEndUs = quantiles(e2e);
    r.processUs = quantiles(proc);
    r.pacerLatenessUs = quantiles(lateness);
    r.pipe = pipe->stats();
    if (recoveredAt != Clock::time_point{}) {
        const double stallEnd = sc.consumerStallAt >= 0 ? sc.consumerStallAt + sc.consumerStallLen : sc.producerStallAt + sc.producerStallLen;
        r.recoveryMs = std::chrono::duration<double, std::milli>(recoveredAt - start).count() - stallEnd * 1000.0;
    }
    r.finalErrorM = finalErrorMeters(cut, pipe->engine().output());
    return r;
}

// ---------------------------------------------------------------- reporting

std::string flatJson(const std::string& name, const Stream& s, const FlatOut& r) {
    char b[700];
    std::snprintf(b, sizeof b,
                  "{\"name\":\"%s\",\"mode\":\"as_fast_as_possible\",\"input\":\"%s\",\"rate_hz\":%.0f,\"simulated_seconds\":%.1f,"
                  "\"imu_samples\":%zu,\"wall_seconds\":%.4f,\"throughput_samples_per_s\":%.0f,\"x_realtime\":%.1f,"
                  "\"latency_us_per_sample\":%s,\"timer_overhead_ns_per_clock_pair\":%.1f,"
                  "\"dropped\":%llu,\"max_queue_occupancy\":%zu,\"final_position_error_m\":%.3f}",
                  name.c_str(), s.name.c_str(), s.rate, s.seconds, r.samples, r.wallSeconds, r.throughput,
                  r.throughput / s.rate, quantilesJson(r.latencyUs).c_str(), r.timerOverheadNs,
                  static_cast<unsigned long long>(r.pipe.dropped), r.pipe.maxOccupancy, r.finalErrorM);
    return b;
}

std::string pacedJson(const std::string& name, const Stream& s, const Scenario& sc, const Paced& r) {
    std::ostringstream o;
    o << "{\"name\":\"" << name << "\",\"mode\":\"paced_realtime\",\"input\":\"" << s.name << "\",\"rate_hz\":" << s.rate
      << ",\"seconds\":" << r.seconds << ",\"imu_samples\":" << r.samples << ",\"deadline_ms\":" << r.periodMs
      << ",\"deadline_misses\":" << r.misses << ",\"end_to_end_latency_us\":" << quantilesJson(r.endToEndUs)
      << ",\"engine_processing_us\":" << quantilesJson(r.processUs) << ",\"producer_lateness_us\":" << quantilesJson(r.pacerLatenessUs)
      << ",\"queue_capacity\":" << EdgePipeline::kCapacity << ",\"max_queue_occupancy\":" << r.pipe.maxOccupancy
      << ",\"offered\":" << r.pipe.offered << ",\"dropped\":" << r.pipe.dropped << ",\"processed\":" << r.pipe.processed
      << ",\"recovery_ms_after_stall\":" << r.recoveryMs << ",\"final_position_error_m\":" << r.finalErrorM
      << ",\"injected\":{\"producer_stall_s\":" << sc.producerStallLen << ",\"consumer_stall_s\":" << sc.consumerStallLen << "}}";
    return o.str();
}

std::string utcNow() {
    const std::time_t t = std::time(nullptr);
    std::tm utc{};
#ifdef _WIN32
    gmtime_s(&utc, &t);
#else
    gmtime_r(&t, &utc);
#endif
    char b[32];
    std::strftime(b, sizeof b, "%Y-%m-%dT%H:%M:%SZ", &utc);
    return b;
}

void printFlat(const std::string& name, const Stream& s, const FlatOut& r) {
    std::printf("%-28s %8zu samples | %9.0f samples/s (%.0fx real time) | latency us p50 %.2f p95 %.2f p99 %.2f max %.1f | drops %llu | err %.2f m\n",
                name.c_str(), r.samples, r.throughput, r.throughput / s.rate, r.latencyUs.p50, r.latencyUs.p95, r.latencyUs.p99,
                r.latencyUs.max, static_cast<unsigned long long>(r.pipe.dropped), r.finalErrorM);
}

void printPaced(const std::string& name, const Paced& r) {
    std::printf("%-28s %8zu samples | e2e us p50 %.0f p99 %.0f max %.0f | misses(>%.1f ms) %zu | queue max %zu/%zu | dropped %llu | recovery %.0f ms | err %.2f m\n",
                name.c_str(), r.samples, r.endToEndUs.p50, r.endToEndUs.p99, r.endToEndUs.max, r.periodMs, r.misses,
                r.pipe.maxOccupancy, EdgePipeline::kCapacity, static_cast<unsigned long long>(r.pipe.dropped), r.recoveryMs,
                r.finalErrorM);
}

struct Args {
    double minutes{10.0}, rate{200.0}, pacedSeconds{60.0};
    std::string iovnbd, json;
    bool noise{true}, smoke{false};
};

bool parse(int argc, char** argv, Args& a) {
    for (int i = 1; i < argc; ++i) {
        const std::string k = argv[i];
        if (k == "--smoke") { a.smoke = true; continue; }
        if (i + 1 >= argc) return false;
        const std::string v = argv[++i];
        if (k == "--minutes") a.minutes = std::atof(v.c_str());
        else if (k == "--rate") a.rate = std::atof(v.c_str());
        else if (k == "--paced-seconds") a.pacedSeconds = std::atof(v.c_str());
        else if (k == "--iovnbd-csv") a.iovnbd = v;
        else if (k == "--json") a.json = v;
        else if (k == "--noise") a.noise = v != "0";
        else return false;
    }
    return a.rate > 0.0 && a.minutes > 0.0;
}

}  // namespace

int main(int argc, char** argv) {
    Args args;
    if (!parse(argc, argv, args)) {
        std::fputs("usage: bench_200hz [--minutes M] [--rate HZ] [--paced-seconds S] [--iovnbd-csv trip.csv] [--noise 1|0] [--json out.json] [--smoke]\n", stderr);
        return 2;
    }
    if (args.smoke) {
        args.minutes = 10.0 / 60.0;
        args.pacedSeconds = 1.0;
        args.iovnbd.clear();
    }
    const TimerResolution resolution;
    const double seconds = args.minutes * 60.0;
    std::vector<std::string> runs;
    int failures = 0;
    auto check = [&](bool ok, const char* what) {
        if (!ok) {
            std::fprintf(stderr, "bench check failed: %s\n", what);
            ++failures;
        }
    };

    std::vector<Stream> inputs;
    inputs.push_back(syntheticStream(std::max(seconds, args.pacedSeconds + 1.0), args.rate, args.noise));
    if (!args.iovnbd.empty()) {
        std::string error;
        Stream trip = iovnbdStream(args.iovnbd, std::max(seconds, args.pacedSeconds + 1.0), args.rate, args.noise, error);
        if (!error.empty()) {
            std::fprintf(stderr, "error: %s\n", error.c_str());
            return 3;
        }
        inputs.push_back(std::move(trip));
    }

    for (const Stream& s : inputs) {
        Stream flat = s;
        flat.seconds = seconds;
        flat.events.erase(std::remove_if(flat.events.begin(), flat.events.end(),
                                         [&](const SensorEvent& e) { return eventTime(e) - eventTime(s.events.front()) > seconds; }),
                          flat.events.end());
        const FlatOut r = runFlatOut(flat);
        const std::string name = s.name + "_flat_out_" + std::to_string(static_cast<int>(seconds)) + "s";
        printFlat(name, flat, r);
        runs.push_back(flatJson(name, flat, r));
        check(r.pipe.dropped == 0, "flat-out run dropped samples");
        check(r.throughput > 10.0 * s.rate, "throughput below 10x real time");
        if (s.name == "synthetic") check(r.finalErrorM >= 0.0 && r.finalErrorM < 25.0, "synthetic final position error");

        const Scenario steady{s.name + "_paced", -1, 0, -1, 0};
        const Paced p = runPaced(s, args.pacedSeconds, steady);
        printPaced(steady.name, p);
        runs.push_back(pacedJson(steady.name, s, steady, p));
        check(p.pipe.dropped == 0, "paced run dropped samples");
    }

    const Stream& synth = inputs.front();
    const double burstSeconds = args.smoke ? 1.5 : 10.0;
    const std::vector<Scenario> bursts = {
        {"burst_producer_stall_200ms", 0.4 * burstSeconds, 0.2, -1, 0},
        {"burst_consumer_stall_200ms", -1, 0, 0.4 * burstSeconds, 0.2},
    };
    for (const Scenario& sc : bursts) {
        const Paced p = runPaced(synth, burstSeconds, sc);
        printPaced(sc.name, p);
        runs.push_back(pacedJson(sc.name, synth, sc, p));
        check(p.pipe.dropped == 0, "a 200 ms stall must not drop samples");
        check(p.pipe.processed == p.pipe.offered, "processed != offered");
    }
    if (!args.smoke) {
        const Scenario overflow{"burst_consumer_stall_6s_overflow", 2.0, 0, 2.0, 6.0};
        const Paced p = runPaced(synth, 12.0, overflow);
        printPaced(overflow.name, p);
        runs.push_back(pacedJson(overflow.name, synth, overflow, p));
        check(p.pipe.dropped > 0, "a 6 s stall must overflow a 5 s buffer (drop accounting untested)");
        check(p.pipe.processed + p.pipe.dropped == p.pipe.offered, "offered != processed + dropped");
    }

    std::ostringstream json;
    json << "{\"schema\":1,\"generated_utc\":\"" << utcNow() << "\",\"machine\":{\"cpu\":\"" << cpuModel()
         << "\",\"logical_cores\":" << std::thread::hardware_concurrency() << "},\"build\":{\"compiler\":\"" << compilerId()
         << "\",\"config\":\"" << GATI_BUILD_CONFIG << "\",\"flags\":\"" << GATI_CXX_FLAGS << "\",\"cxx_standard\":" << kCxxStandard
         << "},\"settings\":{\"rate_hz\":" << args.rate << ",\"minutes\":" << args.minutes << ",\"paced_seconds\":" << args.pacedSeconds
         << ",\"white_noise\":" << (args.noise ? "true" : "false") << ",\"queue_capacity_events\":" << EdgePipeline::kCapacity
         << "},\"runs\":[";
    for (std::size_t i = 0; i < runs.size(); ++i) json << (i ? "," : "") << runs[i];
    json << "]}\n";
    if (!args.json.empty()) {
        std::ofstream out(args.json, std::ios::binary);
        out << json.str();
        if (!out) {
            std::fprintf(stderr, "error: cannot write %s\n", args.json.c_str());
            return 3;
        }
    }
    if (args.smoke) std::fputs(json.str().c_str(), stdout);
    return failures == 0 ? 0 : 1;
}

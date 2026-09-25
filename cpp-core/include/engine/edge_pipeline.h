#pragma once

// Ring-buffered ingest in front of the navigation engine: a producer thread (sensor
// driver) offers events, one consumer thread drains them into the engine. Lock-free and
// allocation-free (SPSC ring buffer). A full queue drops the NEW event and counts it; the
// engine treats the resulting gap like any dropout (it clamps the integration step).

#include <atomic>
#include <cstddef>
#include <cstdint>

#include "engine/nav_engine.h"
#include "engine/spsc_queue.h"

namespace gati {

struct PipelineStats {
    std::uint64_t offered{0}, dropped{0}, processed{0};
    std::size_t maxOccupancy{0};
};

class EdgePipeline {
public:
    static constexpr std::size_t kCapacity = 1024;   // 1024 events = 5.1 s of a 200 Hz stream

    explicit EdgePipeline(const EngineConfig& config = EngineConfig{}) : engine_(config) {}

    // Producer thread only. False (and counted) when the queue is full.
    bool offer(const SensorEvent& event);
    // Consumer thread only: pops one event into the engine. False when the queue is empty.
    // `processed` (optional) receives a copy of the event that was consumed.
    bool processOne(SensorEvent* processed = nullptr);
    std::size_t drain(std::size_t maxEvents);

    std::size_t occupancy() const { return queue_.size(); }
    PipelineStats stats() const;
    const NavEngine& engine() const { return engine_; }

private:
    SpscQueue<SensorEvent, kCapacity> queue_;
    NavEngine engine_;
    std::atomic<std::uint64_t> offered_{0}, dropped_{0}, processed_{0};
    std::atomic<std::size_t> maxOccupancy_{0};
};

}  // namespace gati

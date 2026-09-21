#include "engine/edge_pipeline.h"

namespace gati {

bool EdgePipeline::offer(const SensorEvent& event) {
    offered_.fetch_add(1, std::memory_order_relaxed);
    if (!queue_.push(event)) {
        dropped_.fetch_add(1, std::memory_order_relaxed);
        return false;
    }
    const std::size_t occupancy = queue_.size();
    if (occupancy > maxOccupancy_.load(std::memory_order_relaxed)) maxOccupancy_.store(occupancy, std::memory_order_relaxed);
    return true;
}

bool EdgePipeline::processOne(SensorEvent* processed) {
    SensorEvent event;
    if (!queue_.pop(event)) return false;
    if (const auto* imu = std::get_if<ImuSample>(&event)) engine_.pushImu(*imu);
    else if (const auto* gnss = std::get_if<GnssFix>(&event)) engine_.pushGnss(*gnss);
    processed_.fetch_add(1, std::memory_order_relaxed);
    if (processed) *processed = event;
    return true;
}

std::size_t EdgePipeline::drain(std::size_t maxEvents) {
    std::size_t n = 0;
    while (n < maxEvents && processOne()) ++n;
    return n;
}

PipelineStats EdgePipeline::stats() const {
    return {offered_.load(std::memory_order_relaxed), dropped_.load(std::memory_order_relaxed),
            processed_.load(std::memory_order_relaxed), maxOccupancy_.load(std::memory_order_relaxed)};
}

}  // namespace gati

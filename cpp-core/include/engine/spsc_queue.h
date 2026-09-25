#pragma once

// Lock-free single-producer / single-consumer queue for the edge pipeline.
//
// The producer only writes `written_`, the consumer only writes `read_`; both are
// monotonically increasing counters, so full/empty need no spare slot and the
// index is a mask of the counter. `Capacity` must be a power of two. The two
// counters sit on separate cache lines so the threads do not false-share.

#include <array>
#include <atomic>
#include <cstddef>

#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4324)  // the cache-line padding below is deliberate
#endif

namespace gati {

template <typename T, std::size_t Capacity>
class SpscQueue {
    static_assert(Capacity >= 2 && (Capacity & (Capacity - 1)) == 0, "Capacity must be a power of two");

public:
    // Producer side. False (and nothing stored) when the queue is full.
    bool push(const T& item) {
        const std::size_t w = written_.load(std::memory_order_relaxed);
        if (w - read_.load(std::memory_order_acquire) == Capacity) return false;
        slots_[w & kMask] = item;
        written_.store(w + 1, std::memory_order_release);
        return true;
    }

    // Consumer side. False when the queue is empty.
    bool pop(T& item) {
        const std::size_t r = read_.load(std::memory_order_relaxed);
        if (r == written_.load(std::memory_order_acquire)) return false;
        item = slots_[r & kMask];
        read_.store(r + 1, std::memory_order_release);
        return true;
    }

    std::size_t size() const {
        return written_.load(std::memory_order_acquire) - read_.load(std::memory_order_acquire);
    }
    static constexpr std::size_t capacity() { return Capacity; }

    // Consumer side: drops everything queued so far.
    void clear() { read_.store(written_.load(std::memory_order_acquire), std::memory_order_release); }

private:
    static constexpr std::size_t kMask = Capacity - 1;
    alignas(64) std::atomic<std::size_t> written_{0};
    alignas(64) std::atomic<std::size_t> read_{0};
    std::array<T, Capacity> slots_{};
};

}  // namespace gati

#ifdef _MSC_VER
#pragma warning(pop)
#endif

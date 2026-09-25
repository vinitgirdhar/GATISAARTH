#pragma once

// A live external IMU over UDP, as a std::istream.
//
// Each datagram carries one or more lines of the CSV format in sensor_source.h (the
// header first, then rows), so `CsvSensorSource` reads a UDP stream exactly as it
// reads a file:
//
//     gati::UdpLineBuf buf(5005);
//     std::istream in(&buf);
//     gati::CsvSensorSource source(in);
//
// The stream ends at a datagram "#eof" or after `idleTimeoutMs` without data. Any
// board that can send UDP (a Raspberry Pi reading a USB/serial IMU, a phone app, a
// microcontroller on Wi-Fi) can feed the engine without code changes here.
// tools/udp_imu_sender.py replays a recorded CSV this way for a bench test.

#include <cstdint>
#include <streambuf>
#include <string>

namespace gati {

class UdpLineBuf : public std::streambuf {
public:
    // Binds 0.0.0.0:`port` (0 picks a free port, see port()).
    explicit UdpLineBuf(std::uint16_t port, int idleTimeoutMs = 5000);
    ~UdpLineBuf() override;
    UdpLineBuf(const UdpLineBuf&) = delete;
    UdpLineBuf& operator=(const UdpLineBuf&) = delete;

    bool ok() const { return error_.empty(); }
    const std::string& error() const { return error_; }
    std::uint16_t port() const { return port_; }
    std::uint64_t datagrams() const { return datagrams_; }

protected:
    int_type underflow() override;

private:
    std::intptr_t socket_{-1};
    std::uint16_t port_{0};
    int idleTimeoutMs_;
    std::string buffer_;
    std::string error_;
    std::uint64_t datagrams_{0};
    bool ended_{false};
};

}  // namespace gati

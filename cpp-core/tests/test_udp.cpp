// UDP external-IMU input: datagrams of CSV rows arrive, CsvSensorSource reads them.

#include <chrono>
#include <istream>
#include <string>
#include <thread>
#include <variant>
#include <vector>

#include "check.h"
#include "engine/sensor_source.h"
#include "engine/udp_stream.h"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace {

void sendAll(unsigned short port, const std::vector<std::string>& datagrams) {
#ifdef _WIN32
    const SOCKET s = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
#else
    const int s = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
#endif
    sockaddr_in to{};
    to.sin_family = AF_INET;
    to.sin_port = htons(port);
    to.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    for (const std::string& d : datagrams) {
        ::sendto(s, d.data(), static_cast<int>(d.size()), 0, reinterpret_cast<const sockaddr*>(&to), sizeof(to));
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
#ifdef _WIN32
    closesocket(s);
#else
    close(s);
#endif
}

}  // namespace

int main() {
    gati::UdpLineBuf buf(0, 3000);
    CHECK(buf.ok());
    CHECK(buf.port() != 0);

    std::vector<std::string> datagrams{"t,ax,ay,az,gx,gy,gz,gnss_lat,gnss_lon"};
    for (int i = 0; i < 200; ++i) {
        const double t = i * 0.005;  // 200 Hz
        std::string row = std::to_string(t) + ",0.1,0,9.81,0,0,0.01";
        row += (i % 40 == 0) ? ",28.6,77.2" : ",,";
        datagrams.push_back(row);
    }
    datagrams.push_back("#eof");
    std::thread sender(sendAll, buf.port(), datagrams);

    std::istream in(&buf);
    gati::CsvSensorSource source(in);
    const gati::LoadedStream stream = gati::loadAll(source);
    sender.join();

    CHECK(stream.error.empty());
    std::size_t imu = 0, gnss = 0;
    for (const gati::SensorEvent& e : stream.events) {
        if (std::holds_alternative<gati::ImuSample>(e)) ++imu;
        if (std::holds_alternative<gati::GnssFix>(e)) ++gnss;
    }
    CHECK(imu == 200);
    CHECK(gnss == 5);
    CHECK(buf.datagrams() == datagrams.size());
    return gati_test::finish("test_udp");
}

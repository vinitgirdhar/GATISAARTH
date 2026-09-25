#include "engine/udp_stream.h"

#include <cstring>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
using socklen_t = int;
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace gati {

namespace {

#ifdef _WIN32
struct WinsockInit {
    WinsockInit() {
        WSADATA data;
        WSAStartup(MAKEWORD(2, 2), &data);
    }
    ~WinsockInit() { WSACleanup(); }
};
using Handle = SOCKET;
constexpr Handle kInvalid = INVALID_SOCKET;
void closeHandle(Handle s) { closesocket(s); }
#else
using Handle = int;
constexpr Handle kInvalid = -1;
void closeHandle(Handle s) { close(s); }
#endif

Handle handle(std::intptr_t s) { return static_cast<Handle>(s); }

constexpr std::size_t kMaxDatagram = 65507;

}  // namespace

UdpLineBuf::UdpLineBuf(std::uint16_t port, int idleTimeoutMs) : idleTimeoutMs_(idleTimeoutMs) {
#ifdef _WIN32
    static WinsockInit winsock;
#endif
    const Handle s = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s == kInvalid) {
        error_ = "cannot create a UDP socket";
        return;
    }
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);
    if (::bind(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        closeHandle(s);
        error_ = "cannot bind UDP port " + std::to_string(port);
        return;
    }
    socklen_t len = sizeof(addr);
    ::getsockname(s, reinterpret_cast<sockaddr*>(&addr), &len);
    port_ = ntohs(addr.sin_port);
    socket_ = static_cast<std::intptr_t>(s);
}

UdpLineBuf::~UdpLineBuf() {
    if (socket_ != -1) closeHandle(handle(socket_));
}

UdpLineBuf::int_type UdpLineBuf::underflow() {
    if (gptr() < egptr()) return traits_type::to_int_type(*gptr());
    if (ended_ || socket_ == -1) return traits_type::eof();

    fd_set ready;
    FD_ZERO(&ready);
    FD_SET(handle(socket_), &ready);
    timeval wait{idleTimeoutMs_ / 1000, (idleTimeoutMs_ % 1000) * 1000};
    const int n = ::select(static_cast<int>(handle(socket_)) + 1, &ready, nullptr, nullptr, &wait);
    if (n <= 0) {  // idle timeout (or error): the stream is over
        ended_ = true;
        return traits_type::eof();
    }
    buffer_.resize(kMaxDatagram);
    const auto got = ::recvfrom(handle(socket_), buffer_.data(), static_cast<int>(buffer_.size()), 0, nullptr, nullptr);
    if (got <= 0) {
        ended_ = true;
        return traits_type::eof();
    }
    buffer_.resize(static_cast<std::size_t>(got));
    ++datagrams_;
    if (buffer_.rfind("#eof", 0) == 0) {
        ended_ = true;
        return traits_type::eof();
    }
    if (buffer_.back() != '\n') buffer_.push_back('\n');
    setg(buffer_.data(), buffer_.data(), buffer_.data() + buffer_.size());
    return traits_type::to_int_type(*gptr());
}

}  // namespace gati

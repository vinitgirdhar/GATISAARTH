#pragma once

// WGS-84 helpers shared by the navigation engine, the replay metrics and the
// synthetic trajectory generator. Angles in radians unless a name says Deg.

#include <cmath>

namespace gati::geo {

constexpr double kPi = 3.14159265358979323846;
constexpr double kDegToRad = kPi / 180.0;
constexpr double kRadToDeg = 180.0 / kPi;
constexpr double kSemiMajor = 6378137.0;           // m
constexpr double kEccSq = 6.69437999014e-3;        // first eccentricity squared
constexpr double kEarthRate = 7.2921150e-5;        // rad/s

inline double wrapPi(double a) {
    while (a > kPi) a -= 2.0 * kPi;
    while (a < -kPi) a += 2.0 * kPi;
    return a;
}

inline double wrap360Deg(double d) {
    double r = std::fmod(d, 360.0);
    return r < 0.0 ? r + 360.0 : r;
}

// Meridian radius of curvature (north-south) at geodetic latitude `lat`.
inline double meridianRadius(double lat) {
    const double s = std::sin(lat);
    return kSemiMajor * (1.0 - kEccSq) / std::pow(1.0 - kEccSq * s * s, 1.5);
}

// Prime-vertical radius of curvature (east-west) at geodetic latitude `lat`.
inline double primeVerticalRadius(double lat) {
    const double s = std::sin(lat);
    return kSemiMajor / std::sqrt(1.0 - kEccSq * s * s);
}

struct NorthEast {
    double north{0.0};
    double east{0.0};
};

// Local tangent-plane offset (metres) from point 0 to point 1. Accurate to well
// under a millimetre per kilometre, which is far below any error measured here.
inline NorthEast offsetMeters(double lat0, double lon0, double lat1, double lon1, double height = 0.0) {
    const double latMid = 0.5 * (lat0 + lat1);
    return {(lat1 - lat0) * (meridianRadius(latMid) + height),
            wrapPi(lon1 - lon0) * (primeVerticalRadius(latMid) + height) * std::cos(latMid)};
}

inline double distanceMeters(double lat0, double lon0, double lat1, double lon1) {
    const NorthEast d = offsetMeters(lat0, lon0, lat1, lon1);
    return std::hypot(d.north, d.east);
}

}  // namespace gati::geo

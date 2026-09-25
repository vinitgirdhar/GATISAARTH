#include "engine/earth.h"

#include <cmath>

#include "engine/geo.h"
#include "engine/linalg.h"

namespace gati {

double normalGravity(double latitudeDeg, double altitudeM) {
    constexpr double kGammaEquator = 9.7803253359;   // m/s^2
    constexpr double kSomiglianaK = 0.00193185265241;
    constexpr double kFreeAir = 3.086e-6;            // 1/s^2
    const double s2 = std::pow(std::sin(latitudeDeg * geo::kDegToRad), 2);
    return kGammaEquator * (1.0 + kSomiglianaK * s2) / std::sqrt(1.0 - geo::kEccSq * s2) - kFreeAir * altitudeM;
}

Vector3d coriolisAccel(const Vector3d& velocityNed, double latitudeDeg) {
    const double lat = latitudeDeg * geo::kDegToRad;
    const Vector3d earthRate{geo::kEarthRate * std::cos(lat), 0.0, -geo::kEarthRate * std::sin(lat)};
    return cross(earthRate, velocityNed) * -2.0;
}

void propagateAttitude(Quaterniond& q, const Vector3d& rateBody, double dt) {
    q = quatNormalized(quatMul(q, quatFromRotationVector(rateBody * dt)));
}

Vector3d bodyToNav(const Vector3d& vBody, const Quaterniond& q) { return dcmFromQuat(q) * vBody; }

}  // namespace gati

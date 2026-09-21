#include "ins/mechanization.h"
#include "ins/bias_tracker.h"
#include "ins/earth_model.h"

#include <cmath>

#include "engine/geo.h"
#include "engine/linalg.h"

namespace gati {

// Legacy entry points with no state to act on. The working strapdown loop lives in
// NavEngine (engine/nav_engine.h), which calls the four real functions below.
void strapdownIntegration(const IMUPacket&, double) {}
void updateBiases(Vector3d&, Vector3d&, const Vector3d&, const Vector3d&) {}

// Rotates a body-frame vector into the navigation frame with the body->nav quaternion.
Vector3d transformAccelToNavFrame(const Vector3d& bodyAcceleration, const Quaterniond& attitude) {
    return dcmFromQuat(attitude) * bodyAcceleration;
}

// q <- q * exp(angularRate * dt); angularRate is the body rate relative to the
// navigation frame, expressed in the body frame (rad/s).
void updateAttitudeQuaternion(Quaterniond& attitude, const Vector3d& angularRate, double dt) {
    attitude = quatNormalized(quatMul(attitude, quatFromRotationVector(angularRate * dt)));
}

void correctRawMeasurements(Vector3d& gyro, Vector3d& acceleration, const Vector3d& gyroBias, const Vector3d& accelerometerBias) {
    gyro.x -= gyroBias.x; gyro.y -= gyroBias.y; gyro.z -= gyroBias.z;
    acceleration.x -= accelerometerBias.x; acceleration.y -= accelerometerBias.y; acceleration.z -= accelerometerBias.z;
}

// Somigliana normal gravity on the WGS-84 ellipsoid plus the free-air gradient.
// `latitude` is geodetic latitude in DEGREES (like geodeticToECEF), altitude in metres.
double calculateSomiglianaGravity(double latitude, double altitude) {
    const double s = std::sin(latitude * geo::kDegToRad);
    const double s2 = s * s;
    const double normal = 9.7803253359 * (1.0 + 0.00193185265241 * s2) / std::sqrt(1.0 - geo::kEccSq * s2);
    return normal - 3.086e-6 * altitude;
}

// Coriolis term -2 (w_ie x v) of the navigation-frame acceleration, NED axes.
// `latitude` in degrees; add the result to the specific-force acceleration.
Vector3d computeCoriolisCorrection(const Vector3d& velocity, double latitude) {
    const double lat = latitude * geo::kDegToRad;
    const Vector3d wie{geo::kEarthRate * std::cos(lat), 0.0, -geo::kEarthRate * std::sin(lat)};
    return cross(wie, velocity) * -2.0;
}

}  // namespace gati

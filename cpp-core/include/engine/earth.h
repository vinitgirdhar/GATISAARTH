#pragma once

// Earth model and strapdown helpers used by NavEngine's mechanisation.
// Latitudes are geodetic DEGREES, altitudes metres, the navigation frame NED.

#include "engine/types.h"

namespace gati {

// WGS-84 normal gravity (Somigliana) with the free-air gradient, m/s^2.
double normalGravity(double latitudeDeg, double altitudeM);

// Coriolis term -2 (w_ie x v) of the navigation-frame acceleration, m/s^2.
Vector3d coriolisAccel(const Vector3d& velocityNed, double latitudeDeg);

// q <- q * exp(rate * dt) for a body rate relative to the navigation frame (rad/s).
void propagateAttitude(Quaterniond& q, const Vector3d& rateBody, double dt);

// Rotates a body-frame vector into the navigation frame.
Vector3d bodyToNav(const Vector3d& vBody, const Quaterniond& q);

}  // namespace gati

#pragma once

// Plain value types shared by the whole engine.

#include <array>

namespace gati {

struct Vector3d {
    double x{0.0};
    double y{0.0};
    double z{0.0};
};

// Attitude quaternion [w, x, y, z]; rotates body -> navigation (see linalg.h).
using Quaterniond = std::array<double, 4>;

}  // namespace gati

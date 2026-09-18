#ifndef GATI_TYPES_H
#define GATI_TYPES_H

#include <cstdint>
#include <array>

namespace gati {
    struct Vector3d {
        double x{0.0};
        double y{0.0};
        double z{0.0};
    };

    using Matrix3d = std::array<double, 9>;
    using Quaterniond = std::array<double, 4>;
    using StateVector15d = std::array<double, 15>;

    struct NavigationState {
        double latitude;
        double longitude;
        double altitude;
        double speed;
        double heading;
        double confidence;
    };
}

#endif // GATI_TYPES_H

#pragma once

#include <string>
#include <vector>

namespace gati {
struct RoadSegment {
    std::string id;
    std::vector<double> coordinates;
};
std::vector<RoadSegment> loadGraphFromBinary(const std::string& path);
std::vector<RoadSegment> querySpatialProximity(double latitude, double longitude, double radiusMeters);
}

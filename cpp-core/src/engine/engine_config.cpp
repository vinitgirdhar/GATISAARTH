#include "engine/engine_config.h"

#include <cmath>
#include <cstddef>

namespace gati {

EngineConfig EngineConfig::vehicleGrade() { return EngineConfig{}; }

namespace {

struct NumericField {
    const char* name;
    double EngineConfig::*member;
};
struct FlagField {
    const char* name;
    bool EngineConfig::*member;
};

constexpr NumericField kNumeric[] = {
    {"accelNoise", &EngineConfig::accelNoise},
    {"gyroNoise", &EngineConfig::gyroNoise},
    {"accelBiasWalk", &EngineConfig::accelBiasWalk},
    {"gyroBiasWalk", &EngineConfig::gyroBiasWalk},
    {"minAccelBiasSigma", &EngineConfig::minAccelBiasSigma},
    {"minGyroBiasSigma", &EngineConfig::minGyroBiasSigma},
    {"initVelSigma", &EngineConfig::initVelSigma},
    {"initTiltSigmaDeg", &EngineConfig::initTiltSigmaDeg},
    {"initTiltSigmaStaticDeg", &EngineConfig::initTiltSigmaStaticDeg},
    {"initHeadingSigmaDeg", &EngineConfig::initHeadingSigmaDeg},
    {"initAccelBiasSigma", &EngineConfig::initAccelBiasSigma},
    {"initGyroBiasSigma", &EngineConfig::initGyroBiasSigma},
    {"alignWindow", &EngineConfig::alignWindow},
    {"alignMinSpeed", &EngineConfig::alignMinSpeed},
    {"levelDeparture", &EngineConfig::levelDeparture},
    {"gnssMinSigma", &EngineConfig::gnssMinSigma},
    {"gnssSpeedSigma", &EngineConfig::gnssSpeedSigma},
    {"gnssCourseSigmaDeg", &EngineConfig::gnssCourseSigmaDeg},
    {"gnssMinCourseSpeed", &EngineConfig::gnssMinCourseSpeed},
    {"gnssZeroSpeed", &EngineConfig::gnssZeroSpeed},
    {"gnssAltSigma", &EngineConfig::gnssAltSigma},
    {"gnssTimeout", &EngineConfig::gnssTimeout},
    {"gateScale", &EngineConfig::gateScale},
    {"nhcInterval", &EngineConfig::nhcInterval},
    {"nhcLateralSigma", &EngineConfig::nhcLateralSigma},
    {"nhcVerticalSigma", &EngineConfig::nhcVerticalSigma},
    {"nhcMinSpeed", &EngineConfig::nhcMinSpeed},
    {"nhcMaxYawRate", &EngineConfig::nhcMaxYawRate},
    {"zuptInterval", &EngineConfig::zuptInterval},
    {"zuptSigma", &EngineConfig::zuptSigma},
    {"zuptGyroRms", &EngineConfig::zuptGyroRms},
    {"zuptAccelStd", &EngineConfig::zuptAccelStd},
    {"zuptHold", &EngineConfig::zuptHold},
    {"stillWindow", &EngineConfig::stillWindow},
    {"zaruInterval", &EngineConfig::zaruInterval},
    {"zuptMaxSpeed", &EngineConfig::zuptMaxSpeed},
    {"zuptSpeedSigmas", &EngineConfig::zuptSpeedSigmas},
    {"zuptSpeedCap", &EngineConfig::zuptSpeedCap},
    {"zuptMaxGnssSpeed", &EngineConfig::zuptMaxGnssSpeed},
    {"maxImuDt", &EngineConfig::maxImuDt},
    {"maxAccel", &EngineConfig::maxAccel},
    {"maxGyro", &EngineConfig::maxGyro},
};

constexpr FlagField kFlags[] = {
    {"useGnssAltitude", &EngineConfig::useGnssAltitude},
    {"nhcEnabled", &EngineConfig::nhcEnabled},
    {"zuptEnabled", &EngineConfig::zuptEnabled},
    {"zaruEnabled", &EngineConfig::zaruEnabled},
};

bool same(const char* a, const std::string& b) { return b == a; }

}  // namespace

bool EngineConfig::apply(const std::string& key, double value) {
    if (!std::isfinite(value)) return false;
    for (const NumericField& f : kNumeric) {
        if (same(f.name, key)) {
            this->*f.member = value;
            return true;
        }
    }
    for (const FlagField& f : kFlags) {
        if (same(f.name, key)) {
            this->*f.member = value != 0.0;
            return true;
        }
    }
    if (key == "gnssRejectLimit") {
        gnssRejectLimit = static_cast<int>(value);
        return true;
    }
    return false;
}

}  // namespace gati

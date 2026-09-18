#pragma once

#include "sensor/gnss_packet.h"

namespace gati {
bool evaluateSignalIntegrity(const GNSSPacket& gnss);
bool detectMultipathAnomaly(const GNSSPacket& gnss);
}

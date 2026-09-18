#pragma once

#include "sensor/gnss_packet.h"

namespace gati {
void h_GNSS(const GNSSPacket& gnss);
void h_ZUPT();
void h_Kinematic();
}

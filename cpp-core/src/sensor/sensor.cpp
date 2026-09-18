#include "sensor/imu_packet.h"
#include "sensor/gnss_packet.h"
#include "sensor/ring_buffer.h"

namespace gati {
static_assert(sizeof(IMUPacket) > 0);
static_assert(sizeof(GNSSPacket) > 0);
}

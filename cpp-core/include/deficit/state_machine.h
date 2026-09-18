#pragma once

namespace gati {
enum class NavigationMode { Gnss, Degraded, DeadReckoning, Reacquiring };
NavigationMode transitionMode(NavigationMode current, bool gnssAvailable);
}

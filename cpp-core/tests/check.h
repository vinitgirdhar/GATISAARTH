#pragma once

// Minimal test harness: CHECK / CHECK_NEAR count failures, tests_exit() reports them.
// (Deliberately not GoogleTest: the build stays hermetic and works offline.)

#include <cmath>
#include <cstdio>

namespace gati_test {

inline int& failures() {
    static int n = 0;
    return n;
}

inline int finish(const char* suite) {
    std::printf("%s: %s (%d failed check%s)\n", suite, failures() == 0 ? "PASS" : "FAIL", failures(),
                failures() == 1 ? "" : "s");
    return failures() == 0 ? 0 : 1;
}

}  // namespace gati_test

#define CHECK(cond)                                                                        \
    do {                                                                                   \
        if (!(cond)) {                                                                     \
            std::printf("  CHECK FAILED %s:%d  %s\n", __FILE__, __LINE__, #cond);          \
            ++gati_test::failures();                                                       \
        }                                                                                  \
    } while (0)

#define CHECK_NEAR(actual, expected, tol)                                                  \
    do {                                                                                   \
        const double a_ = (actual), e_ = (expected), t_ = (tol);                           \
        if (!(std::fabs(a_ - e_) <= t_)) {                                                 \
            std::printf("  CHECK_NEAR FAILED %s:%d  %s = %.6g, expected %.6g +/- %.3g\n", \
                        __FILE__, __LINE__, #actual, a_, e_, t_);                          \
            ++gati_test::failures();                                                       \
        }                                                                                  \
    } while (0)

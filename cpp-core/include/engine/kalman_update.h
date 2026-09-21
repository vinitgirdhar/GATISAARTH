#pragma once

// One measurement update of the 15-state error-state Kalman filter, in Joseph form
// with an optional chi-square gate. The covariance is only touched when the update
// is accepted, so a rejected or singular measurement changes nothing.

#include <array>
#include <cmath>

#include "engine/linalg.h"

namespace gati {

enum class UpdateStatus { Accepted, Rejected, Failed };

struct UpdateResult {
    UpdateStatus status{UpdateStatus::Failed};
    double nis{0.0};  // normalised innovation squared (expected value = dimension)
};

// residual = z - h(x_nominal) = H dx + noise;  sigma = per-component measurement std.
// gate <= 0 disables gating. On acceptance `dx` receives the state correction.
template <int M>
UpdateResult kalmanUpdate(Mat<15, 15>& P, const Mat<M, 15>& H, const std::array<double, M>& residual,
                          const std::array<double, M>& sigma, double gate, std::array<double, 15>& dx) {
    const Mat<15, M> PHt = P * transposed(H);
    Mat<M, M> S = H * PHt;
    for (int i = 0; i < M; ++i) S(i, i) += sigma[static_cast<std::size_t>(i)] * sigma[static_cast<std::size_t>(i)];

    Mat<M, M> Sinv;
    if (!invert(S, Sinv)) return {UpdateStatus::Failed, 0.0};

    double nis = 0.0;
    for (int i = 0; i < M; ++i)
        for (int j = 0; j < M; ++j)
            nis += residual[static_cast<std::size_t>(i)] * Sinv(i, j) * residual[static_cast<std::size_t>(j)];
    if (!std::isfinite(nis)) return {UpdateStatus::Failed, 0.0};
    if (gate > 0.0 && nis > gate) return {UpdateStatus::Rejected, nis};

    const Mat<15, M> K = PHt * Sinv;
    for (int i = 0; i < 15; ++i) {
        double s = 0.0;
        for (int j = 0; j < M; ++j) s += K(i, j) * residual[static_cast<std::size_t>(j)];
        dx[static_cast<std::size_t>(i)] = s;
    }

    const Mat<15, 15> A = identity<15>() - K * H;
    Mat<15, 15> next = A * P * transposed(A);
    for (int i = 0; i < 15; ++i)
        for (int j = 0; j < 15; ++j)
            for (int k = 0; k < M; ++k) {
                const double s = sigma[static_cast<std::size_t>(k)];
                next(i, j) += K(i, k) * s * s * K(j, k);
            }
    P = next;
    return {UpdateStatus::Accepted, nis};
}

}  // namespace gati

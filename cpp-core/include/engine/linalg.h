#pragma once

// Small fixed-size linear algebra for the navigation filter. Header-only, no heap,
// no dependencies: the 15-state error-state Kalman filter needs only products,
// transposes and inverses of matrices no larger than 3x3.
//
// Conventions: Quaterniond is [w, x, y, z] and rotates body -> navigation.

#include <array>
#include <cmath>
#include <cstddef>
#include <utility>

#include "engine/types.h"

namespace gati {

inline Vector3d operator+(const Vector3d& a, const Vector3d& b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline Vector3d operator-(const Vector3d& a, const Vector3d& b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline Vector3d operator*(const Vector3d& a, double s) { return {a.x * s, a.y * s, a.z * s}; }
inline double dot(const Vector3d& a, const Vector3d& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline double norm(const Vector3d& a) { return std::sqrt(dot(a, a)); }
inline Vector3d cross(const Vector3d& a, const Vector3d& b) {
    return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline bool isFinite(const Vector3d& a) { return std::isfinite(a.x) && std::isfinite(a.y) && std::isfinite(a.z); }

template <int R, int C>
struct Mat {
    std::array<double, static_cast<std::size_t>(R * C)> a{};
    double& operator()(int r, int c) { return a[static_cast<std::size_t>(r * C + c)]; }
    double operator()(int r, int c) const { return a[static_cast<std::size_t>(r * C + c)]; }
};

template <int N>
Mat<N, N> identity() {
    Mat<N, N> m;
    for (int i = 0; i < N; ++i) m(i, i) = 1.0;
    return m;
}

template <int R, int C>
Mat<C, R> transposed(const Mat<R, C>& m) {
    Mat<C, R> t;
    for (int r = 0; r < R; ++r)
        for (int c = 0; c < C; ++c) t(c, r) = m(r, c);
    return t;
}

template <int R, int K, int C>
Mat<R, C> operator*(const Mat<R, K>& x, const Mat<K, C>& y) {
    Mat<R, C> out;
    for (int r = 0; r < R; ++r)
        for (int k = 0; k < K; ++k) {
            const double xv = x(r, k);
            if (xv == 0.0) continue;   // the filter matrices are mostly zeros
            for (int c = 0; c < C; ++c) out(r, c) += xv * y(k, c);
        }
    return out;
}

template <int R, int C>
Mat<R, C> operator+(const Mat<R, C>& x, const Mat<R, C>& y) {
    Mat<R, C> out;
    for (std::size_t i = 0; i < out.a.size(); ++i) out.a[i] = x.a[i] + y.a[i];
    return out;
}

template <int R, int C>
Mat<R, C> operator-(const Mat<R, C>& x, const Mat<R, C>& y) {
    Mat<R, C> out;
    for (std::size_t i = 0; i < out.a.size(); ++i) out.a[i] = x.a[i] - y.a[i];
    return out;
}

template <int R, int C>
Mat<R, C> operator*(const Mat<R, C>& x, double s) {
    Mat<R, C> out;
    for (std::size_t i = 0; i < out.a.size(); ++i) out.a[i] = x.a[i] * s;
    return out;
}

// Gauss-Jordan with partial pivoting. Returns false (and leaves `out` untouched)
// for a singular or non-finite matrix instead of producing NaN.
template <int N>
bool invert(const Mat<N, N>& m, Mat<N, N>& out) {
    Mat<N, N> a = m;
    Mat<N, N> inv = identity<N>();
    for (int col = 0; col < N; ++col) {
        int pivot = col;
        for (int r = col + 1; r < N; ++r)
            if (std::fabs(a(r, col)) > std::fabs(a(pivot, col))) pivot = r;
        const double p = a(pivot, col);
        if (!(std::fabs(p) > 1e-300) || !std::isfinite(p)) return false;
        if (pivot != col) {
            for (int c = 0; c < N; ++c) {
                std::swap(a(pivot, c), a(col, c));
                std::swap(inv(pivot, c), inv(col, c));
            }
        }
        const double invP = 1.0 / a(col, col);
        for (int c = 0; c < N; ++c) {
            a(col, c) *= invP;
            inv(col, c) *= invP;
        }
        for (int r = 0; r < N; ++r) {
            if (r == col) continue;
            const double factor = a(r, col);
            if (factor == 0.0) continue;
            for (int c = 0; c < N; ++c) {
                a(r, c) -= factor * a(col, c);
                inv(r, c) -= factor * inv(col, c);
            }
        }
    }
    out = inv;
    return true;
}

inline Mat<3, 3> skew(const Vector3d& v) {
    Mat<3, 3> m;
    m(0, 1) = -v.z; m(0, 2) = v.y;
    m(1, 0) = v.z;  m(1, 2) = -v.x;
    m(2, 0) = -v.y; m(2, 1) = v.x;
    return m;
}

inline Vector3d operator*(const Mat<3, 3>& m, const Vector3d& v) {
    return {m(0, 0) * v.x + m(0, 1) * v.y + m(0, 2) * v.z,
            m(1, 0) * v.x + m(1, 1) * v.y + m(1, 2) * v.z,
            m(2, 0) * v.x + m(2, 1) * v.y + m(2, 2) * v.z};
}

// ---- quaternions ([w, x, y, z], body -> navigation)

inline Quaterniond quatMul(const Quaterniond& p, const Quaterniond& q) {
    return {p[0] * q[0] - p[1] * q[1] - p[2] * q[2] - p[3] * q[3],
            p[0] * q[1] + p[1] * q[0] + p[2] * q[3] - p[3] * q[2],
            p[0] * q[2] - p[1] * q[3] + p[2] * q[0] + p[3] * q[1],
            p[0] * q[3] + p[1] * q[2] - p[2] * q[1] + p[3] * q[0]};
}

inline Quaterniond quatNormalized(const Quaterniond& q) {
    const double n = std::sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
    if (!(n > 1e-12)) return {1.0, 0.0, 0.0, 0.0};
    return {q[0] / n, q[1] / n, q[2] / n, q[3] / n};
}

// Exact quaternion for a rotation vector (axis * angle, radians).
inline Quaterniond quatFromRotationVector(const Vector3d& r) {
    const double angle = norm(r);
    if (angle < 1e-9) return quatNormalized({1.0, 0.5 * r.x, 0.5 * r.y, 0.5 * r.z});
    const double s = std::sin(0.5 * angle) / angle;
    return {std::cos(0.5 * angle), r.x * s, r.y * s, r.z * s};
}

// Direction cosine matrix C_nb (body -> navigation) of a unit quaternion.
inline Mat<3, 3> dcmFromQuat(const Quaterniond& q) {
    const double w = q[0], x = q[1], y = q[2], z = q[3];
    Mat<3, 3> c;
    c(0, 0) = 1 - 2 * (y * y + z * z); c(0, 1) = 2 * (x * y - w * z);     c(0, 2) = 2 * (x * z + w * y);
    c(1, 0) = 2 * (x * y + w * z);     c(1, 1) = 1 - 2 * (x * x + z * z); c(1, 2) = 2 * (y * z - w * x);
    c(2, 0) = 2 * (x * z - w * y);     c(2, 1) = 2 * (y * z + w * x);     c(2, 2) = 1 - 2 * (x * x + y * y);
    return c;
}

// ZYX (yaw-pitch-roll) Euler angles in radians of C_nb.
inline void eulerFromQuat(const Quaterniond& q, double& roll, double& pitch, double& yaw) {
    const Mat<3, 3> c = dcmFromQuat(q);
    roll = std::atan2(c(2, 1), c(2, 2));
    pitch = -std::asin(std::fmax(-1.0, std::fmin(1.0, c(2, 0))));
    yaw = std::atan2(c(1, 0), c(0, 0));
}

inline Quaterniond quatFromEuler(double roll, double pitch, double yaw) {
    const Quaterniond qz{std::cos(0.5 * yaw), 0.0, 0.0, std::sin(0.5 * yaw)};
    const Quaterniond qy{std::cos(0.5 * pitch), 0.0, std::sin(0.5 * pitch), 0.0};
    const Quaterniond qx{std::cos(0.5 * roll), std::sin(0.5 * roll), 0.0, 0.0};
    return quatNormalized(quatMul(quatMul(qz, qy), qx));
}

}  // namespace gati

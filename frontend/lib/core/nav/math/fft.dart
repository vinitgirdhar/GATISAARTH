import 'dart:math' as math;

/// In-place iterative radix-2 Cooley–Tukey FFT of the complex sequence
/// ([re], [im]). The length must be a power of two.
void fftInPlace(List<double> re, List<double> im) {
  final n = re.length;
  if (n != im.length || n == 0 || n & (n - 1) != 0) {
    throw ArgumentError('FFT length must be a power of two, got $n');
  }
  // Bit-reversal permutation.
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i], ti = im[i];
      re[i] = re[j];
      im[i] = im[j];
      re[j] = tr;
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final angle = -2 * math.pi / len;
    final wr = math.cos(angle), wi = math.sin(angle);
    for (var start = 0; start < n; start += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final a = start + k, b = a + len ~/ 2;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}

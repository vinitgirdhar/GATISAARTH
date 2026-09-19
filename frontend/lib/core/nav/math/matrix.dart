import 'dart:math' as math;
import 'dart:typed_data';

/// Dense row-major matrix of doubles, sized for the navigation filter
/// (15x15 and smaller).
///
/// Deliberately minimal — only what the error-state EKF needs. `vector_math`
/// covers the fixed 3x3 / quaternion work; this exists because the filter's
/// state is 15-dimensional and nothing bundled with Flutter does NxN.
class Matrix {
  Matrix(this.rows, this.cols)
      : assert(rows > 0 && cols > 0),
        _d = Float64List(rows * cols);

  Matrix.fromRows(List<List<double>> values)
      : rows = values.length,
        cols = values.first.length,
        _d = Float64List(values.length * values.first.length) {
    for (var r = 0; r < rows; r++) {
      if (values[r].length != cols) {
        throw ArgumentError('row $r has ${values[r].length} values, want $cols');
      }
      for (var c = 0; c < cols; c++) {
        _d[r * cols + c] = values[r][c];
      }
    }
  }

  /// Column vector from [values].
  Matrix.column(List<double> values)
      : rows = values.length,
        cols = 1,
        _d = Float64List.fromList(values.map((v) => v.toDouble()).toList());

  factory Matrix.identity(int n) {
    final m = Matrix(n, n);
    for (var i = 0; i < n; i++) {
      m._d[i * n + i] = 1;
    }
    return m;
  }

  /// Square matrix with [diagonal] on the main diagonal, zero elsewhere.
  factory Matrix.diagonal(List<double> diagonal) {
    final n = diagonal.length;
    final m = Matrix(n, n);
    for (var i = 0; i < n; i++) {
      m._d[i * n + i] = diagonal[i];
    }
    return m;
  }

  final int rows;
  final int cols;
  final Float64List _d;

  bool get isSquare => rows == cols;

  double at(int r, int c) => _d[r * cols + c];

  void set(int r, int c, double v) => _d[r * cols + c] = v;

  void add(int r, int c, double v) => _d[r * cols + c] += v;

  /// Flat row-major view. Mutating it mutates the matrix.
  Float64List get storage => _d;

  Matrix copy() {
    final m = Matrix(rows, cols);
    m._d.setAll(0, _d);
    return m;
  }

  Matrix operator +(Matrix o) => _elementwise(o, (a, b) => a + b);

  Matrix operator -(Matrix o) => _elementwise(o, (a, b) => a - b);

  Matrix _elementwise(Matrix o, double Function(double, double) f) {
    _requireSameShape(o);
    final m = Matrix(rows, cols);
    for (var i = 0; i < _d.length; i++) {
      m._d[i] = f(_d[i], o._d[i]);
    }
    return m;
  }

  Matrix scaled(double k) {
    final m = Matrix(rows, cols);
    for (var i = 0; i < _d.length; i++) {
      m._d[i] = _d[i] * k;
    }
    return m;
  }

  Matrix operator *(Matrix o) {
    if (cols != o.rows) {
      throw ArgumentError('cannot multiply ${rows}x$cols by ${o.rows}x${o.cols}');
    }
    final m = Matrix(rows, o.cols);
    for (var r = 0; r < rows; r++) {
      final rowOff = r * cols;
      final outOff = r * o.cols;
      for (var k = 0; k < cols; k++) {
        final a = _d[rowOff + k];
        if (a == 0) continue;
        final oOff = k * o.cols;
        for (var c = 0; c < o.cols; c++) {
          m._d[outOff + c] += a * o._d[oOff + c];
        }
      }
    }
    return m;
  }

  Matrix get transposed {
    final m = Matrix(cols, rows);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        m._d[c * rows + r] = _d[r * cols + c];
      }
    }
    return m;
  }

  /// `(this + thisᵀ) / 2`. Covariance matrices drift out of symmetry through
  /// floating-point error; re-symmetrising every update keeps them usable
  /// (§62 numerical safety).
  Matrix symmetrized() {
    if (!isSquare) throw StateError('symmetrized() needs a square matrix');
    final m = Matrix(rows, cols);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        m._d[r * cols + c] = 0.5 * (at(r, c) + at(c, r));
      }
    }
    return m;
  }

  /// Raises diagonal entries below [floor] up to it, in place. Stops a
  /// covariance from collapsing to (or below) zero variance, which would make
  /// the next inverse singular.
  void floorDiagonal(double floor) {
    for (var i = 0; i < math.min(rows, cols); i++) {
      if (_d[i * cols + i] < floor) _d[i * cols + i] = floor;
    }
  }

  /// Gauss-Jordan inverse with partial pivoting.
  ///
  /// Returns null when the matrix is singular to working precision — callers
  /// skip the update rather than propagating NaN through the filter.
  Matrix? inverse() {
    if (!isSquare) throw StateError('inverse() needs a square matrix');
    final n = rows;
    final a = Float64List.fromList(_d);
    final inv = Matrix.identity(n);
    final b = inv._d;

    for (var col = 0; col < n; col++) {
      var pivot = col;
      var best = a[col * n + col].abs();
      for (var r = col + 1; r < n; r++) {
        final v = a[r * n + col].abs();
        if (v > best) {
          best = v;
          pivot = r;
        }
      }
      if (best < 1e-300 || !best.isFinite) return null;
      if (pivot != col) {
        _swapRows(a, n, col, pivot);
        _swapRows(b, n, col, pivot);
      }
      final d = a[col * n + col];
      for (var c = 0; c < n; c++) {
        a[col * n + c] /= d;
        b[col * n + c] /= d;
      }
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final f = a[r * n + col];
        if (f == 0) continue;
        for (var c = 0; c < n; c++) {
          a[r * n + c] -= f * a[col * n + c];
          b[r * n + c] -= f * b[col * n + c];
        }
      }
    }
    return inv.isFinite ? inv : null;
  }

  static void _swapRows(Float64List m, int n, int r1, int r2) {
    for (var c = 0; c < n; c++) {
      final t = m[r1 * n + c];
      m[r1 * n + c] = m[r2 * n + c];
      m[r2 * n + c] = t;
    }
  }

  bool get isFinite {
    for (final v in _d) {
      if (!v.isFinite) return false;
    }
    return true;
  }

  /// True when every diagonal entry is positive and the matrix is symmetric to
  /// [tolerance]. A cheap stand-in for a full positive-definiteness check; the
  /// filter uses it as a health signal, not a proof.
  bool isSymmetricPositiveDiagonal({double tolerance = 1e-9}) {
    if (!isSquare) return false;
    for (var r = 0; r < rows; r++) {
      if (!(at(r, r) > 0)) return false;
      for (var c = r + 1; c < cols; c++) {
        final d = (at(r, c) - at(c, r)).abs();
        final scale = math.max(1.0, at(r, c).abs());
        if (d > tolerance * scale) return false;
      }
    }
    return true;
  }

  /// Column vector as a plain list.
  List<double> get columnValues {
    if (cols != 1) throw StateError('columnValues() needs a column vector');
    return List<double>.from(_d);
  }

  void _requireSameShape(Matrix o) {
    if (rows != o.rows || cols != o.cols) {
      throw ArgumentError('shape ${rows}x$cols vs ${o.rows}x${o.cols}');
    }
  }

  @override
  String toString() {
    final b = StringBuffer();
    for (var r = 0; r < rows; r++) {
      b.write('[');
      for (var c = 0; c < cols; c++) {
        if (c > 0) b.write(', ');
        b.write(at(r, c).toStringAsFixed(6));
      }
      b.writeln(']');
    }
    return b.toString();
  }
}

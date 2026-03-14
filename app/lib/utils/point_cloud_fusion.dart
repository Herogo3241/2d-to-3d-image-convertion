import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────────────────────
// Point3D — canonical definition. Import from here in ALL files.
// ─────────────────────────────────────────────────────────────────────────────
class Point3D {
  final double x, y, z;
  final int r, g, b;
  final int viewIndex;

  const Point3D({
    required this.x,
    required this.y,
    required this.z,
    required this.r,
    required this.g,
    required this.b,
    this.viewIndex = 0,
  });

  Point3D transformed(Matrix4x4 m) {
    return Point3D(
      x: m[0] * x + m[1] * y + m[2] * z + m[3],
      y: m[4] * x + m[5] * y + m[6] * z + m[7],
      z: m[8] * x + m[9] * y + m[10] * z + m[11],
      r: r, g: g, b: b, viewIndex: viewIndex,
    );
  }

  double distanceTo(Point3D other) {
    final dx = x - other.x, dy = y - other.y, dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Matrix4x4
// ─────────────────────────────────────────────────────────────────────────────
class Matrix4x4 {
  final List<double> _m;
  Matrix4x4(List<double> v) : _m = List<double>.from(v) { assert(_m.length == 16); }

  double operator [](int i) => _m[i];

  static Matrix4x4 identity() => Matrix4x4([
    1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1,
  ]);

  /// Pure translation matrix.
  static Matrix4x4 translation(double tx, double ty, double tz) => Matrix4x4([
    1,0,0,tx, 0,1,0,ty, 0,0,1,tz, 0,0,0,1,
  ]);

  Matrix4x4 operator *(Matrix4x4 o) {
    final r = List<double>.filled(16, 0);
    for (int row = 0; row < 4; row++)
      for (int col = 0; col < 4; col++)
        for (int k = 0; k < 4; k++)
          r[row*4+col] += _m[row*4+k] * o._m[k*4+col];
    return Matrix4x4(r);
  }

  // ── ARCore pose parsers ───────────────────────────────────────────────────

  /// ARCore column-major 4×4 → row-major.
  static Matrix4x4 fromArCoreMatrix16(List<double> p) {
    assert(p.length == 16);
    return Matrix4x4([
      p[0], p[4], p[8],  p[12],
      p[1], p[5], p[9],  p[13],
      p[2], p[6], p[10], p[14],
      p[3], p[7], p[11], p[15],
    ]);
  }

  /// ARCore 7-float pose stored as [tx, ty, tz, qx, qy, qz, qw]
  /// (translation-first — ARCore's Pose.getTranslation() + getRotationQuaternion() order).
  static Matrix4x4 fromArCore7_TxyzQxyzw(List<double> p) {
    assert(p.length >= 7);
    final tx = p[0], ty = p[1], tz = p[2];
    final qx = p[3], qy = p[4], qz = p[5], qw = p[6];
    return _quatTranslationToMatrix(qx, qy, qz, qw, tx, ty, tz);
  }

  /// Alternative 7-float layout: [qx, qy, qz, qw, tx, ty, tz]
  static Matrix4x4 fromArCore7_QxyzwTxyz(List<double> p) {
    assert(p.length >= 7);
    final qx = p[0], qy = p[1], qz = p[2], qw = p[3];
    final tx = p[4], ty = p[5], tz = p[6];
    return _quatTranslationToMatrix(qx, qy, qz, qw, tx, ty, tz);
  }

  static Matrix4x4 _quatTranslationToMatrix(
      double qx, double qy, double qz, double qw,
      double tx, double ty, double tz) {
    final x2=qx+qx, y2=qy+qy, z2=qz+qz;
    final xx=qx*x2, xy=qx*y2, xz=qx*z2;
    final yy=qy*y2, yz=qy*z2, zz=qz*z2;
    final wx=qw*x2, wy=qw*y2, wz=qw*z2;
    return Matrix4x4([
      1-(yy+zz), xy-wz,     xz+wy,     tx,
      xy+wz,     1-(xx+zz), yz-wx,     ty,
      xz-wy,     yz+wx,     1-(xx+yy), tz,
      0,         0,         0,         1,
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PointCloudFusion
// ─────────────────────────────────────────────────────────────────────────────
class PointCloudFusion {

  // ── Centroid helpers ──────────────────────────────────────────────────────

  static (double, double, double) centroid(List<Point3D> pts) {
    if (pts.isEmpty) return (0, 0, 0);
    double sx = 0, sy = 0, sz = 0;
    for (final p in pts) { sx += p.x; sy += p.y; sz += p.z; }
    final n = pts.length.toDouble();
    return (sx / n, sy / n, sz / n);
  }

  static List<Point3D> translateToCentroid(List<Point3D> pts) {
    final (cx, cy, cz) = centroid(pts);
    final m = Matrix4x4.translation(-cx, -cy, -cz);
    return pts.map((p) => p.transformed(m)).toList();
  }

  static List<Point3D> translateBy(List<Point3D> pts, double tx, double ty, double tz) {
    final m = Matrix4x4.translation(tx, ty, tz);
    return pts.map((p) => p.transformed(m)).toList();
  }

  // ── Pose-based world transform (best-effort) ──────────────────────────────
  //
  // ARCore's relativePose can come in several formats depending on how the
  // Android side serializes it. We try to detect the correct interpretation
  // by checking whether the quaternion part is normalised.
  //
  // If the pose looks bad (non-unit quaternion, or length-0 translation when
  // we expect movement), fall back to centroid alignment instead.

  static ({List<Point3D> cloud, bool usedPose}) transformToWorldFrame(
    List<Point3D> points,
    List<double> pose,
  ) {
    try {
      if (pose.length == 16) {
        final m = Matrix4x4.fromArCoreMatrix16(pose);
        if (_isReasonableMatrix(m)) {
          return (cloud: points.map((p) => p.transformed(m)).toList(), usedPose: true);
        }
      } else if (pose.length == 7) {
        // Try translation-first layout [tx,ty,tz,qx,qy,qz,qw]
        final m1 = Matrix4x4.fromArCore7_TxyzQxyzw(pose);
        if (_isReasonableMatrix(m1)) {
          return (cloud: points.map((p) => p.transformed(m1)).toList(), usedPose: true);
        }
        // Try quaternion-first layout [qx,qy,qz,qw,tx,ty,tz]
        final m2 = Matrix4x4.fromArCore7_QxyzwTxyz(pose);
        if (_isReasonableMatrix(m2)) {
          return (cloud: points.map((p) => p.transformed(m2)).toList(), usedPose: true);
        }
      }
    } catch (_) {}

    // Pose unusable — return points unchanged; ICP will align them
    return (cloud: points, usedPose: false);
  }

  /// Returns false if the matrix contains NaN/Inf or has a wildly non-unit
  /// rotation determinant (indicates a bad parse).
  static bool _isReasonableMatrix(Matrix4x4 m) {
    for (int i = 0; i < 16; i++) {
      if (m[i].isNaN || m[i].isInfinite) return false;
    }
    // Check translation: If the camera moved 100 meters, something is wrong.
    // In AR, movements are usually < 10m.
    double tx = m[3].abs();
    double ty = m[7].abs();
    double tz = m[11].abs();
    if (tx > 20 || ty > 20 || tz > 20) return false;

    final det =
        m[0] * (m[5] * m[10] - m[6] * m[9]) -
        m[1] * (m[4] * m[10] - m[6] * m[8]) +
        m[2] * (m[4] * m[9] - m[5] * m[8]);

    // Be VERY generous with the determinant (0.5 instead of 0.15)
    return (det - 1.0).abs() < 0.5;
  }

  // ── ICP ───────────────────────────────────────────────────────────────────

  /// Fine-align [source] onto [target] using iterative closest point.
  ///
  /// Pre-aligns centroids before the ICP loop so the initial overlap is good
  /// regardless of whether the pose transform was used.
  static List<Point3D> icpRefine(
    List<Point3D> source,
    List<Point3D> target, {
    int maxIterations = 50,
    double maxDistance = 0.30, 
    double convergence = 1e-6,
  }) {
    if (source.isEmpty || target.isEmpty) return source;

    // Pre-align centroids so the clouds actually overlap before we start
    final (scx, scy, scz) = centroid(source);
    final (tcx, tcy, tcz) = centroid(target);
    List<Point3D> current = translateBy(source, tcx - scx, tcy - scy, tcz - scz);

    final targetSample = _subsample(target, 1500);
    double prevError = double.infinity;

    for (int iter = 0; iter < maxIterations; iter++) {
      // Subsample source differently each iteration to prevent getting stuck
      final sourceSample = _subsample(current, 800);
      final corr = <(Point3D, Point3D)>[];
      double totalError = 0;

      for (final sp in sourceSample) {
        Point3D? nearest;
        double bestDistSq = maxDistance * maxDistance;
        
        for (final tp in targetSample) {
          final dx = sp.x - tp.x;
          final dy = sp.y - tp.y;
          final dz = sp.z - tp.z;
          final d2 = dx*dx + dy*dy + dz*dz;
          if (d2 < bestDistSq) {
            bestDistSq = d2;
            nearest = tp;
          }
        }
        if (nearest != null) {
          corr.add((sp, nearest));
          totalError += math.sqrt(bestDistSq);
        }
      }

      if (corr.length < 10) break; // Not enough overlap
      totalError /= corr.length;

      final t = _computeRigidTransform(corr);
      current = current.map((p) => p.transformed(t)).toList();

      if ((prevError - totalError).abs() < convergence) break;
      prevError = totalError;
    }
    return current;
  }
  // ── Merge ─────────────────────────────────────────────────────────────────

  static List<Point3D> mergeAndDeduplicate(
    List<List<Point3D>> clouds, {
    double voxelSize = 0.015,
  }) {
    final voxelMap = <String, _VoxelAccum>{};

    for (final cloud in clouds) {
      for (final p in cloud) {
        final key =
            '${(p.x/voxelSize).round()},${(p.y/voxelSize).round()},${(p.z/voxelSize).round()}';
        final acc = voxelMap[key];
        if (acc == null) {
          voxelMap[key] = _VoxelAccum(p.x, p.y, p.z, p.r, p.g, p.b, p.viewIndex);
        } else {
          acc.add(p.x, p.y, p.z, p.r, p.g, p.b);
        }
      }
    }

    return voxelMap.values.map((a) => a.toPoint3D()).toList();
  }

  // ── Outlier removal ───────────────────────────────────────────────────────

  static List<Point3D> statisticalOutlierRemoval(
    List<Point3D> points, {
    int k = 12, // Increased k for better density estimation
    double stdDevMultiplier = 2.0,
  }) {
    if (points.length < k + 1) return points;

    // IMPORTANT: Because we don't have a KD-Tree in Dart, we must search 
    // a larger subset of the list or the whole list. Using indices is a bug.
    final distances = List<double>.filled(points.length, 0);
    
    // To keep it performant, we check against a spatially-shuffled subsample
    final reference = _subsample(points, 2000); 

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final dList = <double>[];
      for (final refP in reference) {
        final d = p.distanceTo(refP);
        if (d > 0) dList.add(d);
      }
      dList.sort();
      final actualK = math.min(k, dList.length);
      distances[i] = dList.take(actualK).reduce((a, b) => a + b) / actualK;
    }

    final mean = distances.reduce((a, b) => a + b) / distances.length;
    final variance = distances.fold<double>(0, (s, d) => s + (d-mean)*(d-mean)) / distances.length;
    final threshold = mean + stdDevMultiplier * math.sqrt(variance);

    return [
      for (int i = 0; i < points.length; i++)
        if (distances[i] <= threshold) points[i]
    ];
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static double _meanKnnDist(List<Point3D> pts, int idx, int k) {
    final p = pts[idx];
    final dists = <double>[];
    final lo = math.max(0, idx - 200);
    final hi = math.min(pts.length - 1, idx + 200);
    for (int j = lo; j <= hi; j++) {
      if (j != idx) dists.add(p.distanceTo(pts[j]));
    }
    if (dists.isEmpty) return 0;
    dists.sort();
    final take = math.min(k, dists.length);
    return dists.take(take).reduce((a, b) => a + b) / take;
  }

  static List<Point3D> _subsample(List<Point3D> pts, int maxCount) {
    if (pts.length <= maxCount) return pts;
    final step = pts.length ~/ maxCount;
    return [for (int i = 0; i < pts.length; i += step) pts[i]];
  }

  static Matrix4x4 _computeRigidTransform(List<(Point3D, Point3D)> corr) {
    double sx=0, sy=0, sz=0, tx=0, ty=0, tz=0;
    final n = corr.length.toDouble();
    for (final (s, t) in corr) { sx+=s.x; sy+=s.y; sz+=s.z; tx+=t.x; ty+=t.y; tz+=t.z; }
    sx/=n; sy/=n; sz/=n; tx/=n; ty/=n; tz/=n;

    final H = List<double>.filled(9, 0);
    for (final (s, t) in corr) {
      final dx=s.x-sx, dy=s.y-sy, dz=s.z-sz;
      final px=t.x-tx, py=t.y-ty, pz=t.z-tz;
      H[0]+=dx*px; H[1]+=dx*py; H[2]+=dx*pz;
      H[3]+=dy*px; H[4]+=dy*py; H[5]+=dy*pz;
      H[6]+=dz*px; H[7]+=dz*py; H[8]+=dz*pz;
    }

    final ax=H[7]-H[5], ay=H[2]-H[6], az=H[3]-H[1];
    final angle = math.sqrt(ax*ax + ay*ay + az*az);
    List<double> R;

    if (angle < 1e-8) {
      R = [1,0,0, 0,1,0, 0,0,1];
    } else {
      final s = math.sin(angle)/angle, c = 1-math.cos(angle);
      final ux=ax/angle, uy=ay/angle, uz=az/angle;
      R = [
        1+c*(ux*ux-1), -s*uz+c*ux*uy,  s*uy+c*ux*uz,
        s*uz+c*ux*uy,  1+c*(uy*uy-1), -s*ux+c*uy*uz,
       -s*uy+c*ux*uz,  s*ux+c*uy*uz,  1+c*(uz*uz-1),
      ];
    }

    return Matrix4x4([
      R[0],R[1],R[2], tx-(R[0]*sx+R[1]*sy+R[2]*sz),
      R[3],R[4],R[5], ty-(R[3]*sx+R[4]*sy+R[5]*sz),
      R[6],R[7],R[8], tz-(R[6]*sx+R[7]*sy+R[8]*sz),
      0,   0,   0,    1,
    ]);
  }
}

// ── Internal voxel accumulator ────────────────────────────────────────────────
class _VoxelAccum {
  double x, y, z;
  double r, g, b;
  final int viewIndex;
  int count;

  _VoxelAccum(this.x, this.y, this.z, int ri, int gi, int bi, this.viewIndex)
      : r = ri.toDouble(), g = gi.toDouble(), b = bi.toDouble(), count = 1;

  void add(double nx, double ny, double nz, int ri, int gi, int bi) {
    x += nx; y += ny; z += nz;
    r += ri; g += gi; b += bi;
    count++;
  }

  Point3D toPoint3D() => Point3D(
    x: x/count, y: y/count, z: z/count,
    r: (r/count).round().clamp(0,255),
    g: (g/count).round().clamp(0,255),
    b: (b/count).round().clamp(0,255),
    viewIndex: viewIndex,
  );
}
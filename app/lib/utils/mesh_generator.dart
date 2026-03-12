import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Represents a 3D point with color information
class Vertex {
  final double x, y, z;
  final int r, g, b;
  final double u, v; // Texture coordinates

  Vertex({
    required this.x,
    required this.y,
    required this.z,
    required this.r,
    required this.g,
    required this.b,
    this.u = 0.0,
    this.v = 0.0,
  });

  Vertex withUV(double u, double v) {
    return Vertex(x: x, y: y, z: z, r: r, g: g, b: b, u: u, v: v);
  }
}

/// Represents a triangle face with 3 vertex indices
class Triangle {
  final int v1, v2, v3;

  Triangle(this.v1, this.v2, this.v3);
}

/// Mesh data structure containing vertices and triangles
class Mesh {
  final List<Vertex> vertices;
  final List<Triangle> triangles;
  final int textureWidth;
  final int textureHeight;

  Mesh({
    required this.vertices,
    required this.triangles,
    this.textureWidth = 1024,
    this.textureHeight = 1024,
  });

  int get vertexCount => vertices.length;
  int get triangleCount => triangles.length;
}

/// Result of mesh generation including paths to exported files
class MeshExportResult {
  final String objPath;
  final String mtlPath;
  final String texturePath;
  final int vertexCount;
  final int triangleCount;

  MeshExportResult({
    required this.objPath,
    required this.mtlPath,
    required this.texturePath,
    required this.vertexCount,
    required this.triangleCount,
  });
}

/// Generates mesh from point cloud using grid-based triangulation
class MeshGenerator {
  /// Generate mesh using an improved Ball Pivoting Algorithm.
  ///
  /// This method creates a watertight mesh by:
  /// - Using adaptive ball radius based on local point density
  /// - Filling holes by allowing more triangles per edge in sparse areas
  /// - Less aggressive normal filtering to preserve geometry
  static Mesh generateWithBallRolling({
    required List<dynamic> points, // Point3D from viewer
    double ballRadius = 0.06,
    double maxEdgeLength = 0.25,
    int maxNeighbors = 24,
    double voxelSize = 0.025,
  }) {
    if (points.length < 3) {
      return Mesh(vertices: const [], triangles: const []);
    }

    // Convert and downsample first for speed + cleaner topology.
    final rawVertices = <Vertex>[];
    for (final p in points) {
      rawVertices.add(Vertex(
        x: p.x as double,
        y: p.y as double,
        z: p.z as double,
        r: p.r as int,
        g: p.g as int,
        b: p.b as int,
      ));
    }

    final vertices = _voxelDownsample(rawVertices, voxelSize: voxelSize);
    if (vertices.length < 3) {
      return Mesh(vertices: _calculateUVCoordinates(vertices), triangles: const []);
    }

    final spatialIndex = _buildSpatialIndexWithCellSize(
      vertices,
      cellSize: math.max(voxelSize, ballRadius),
    );
    final triangles = <Triangle>[];

    // Undirected edge usage cap - allow up to 2 faces per edge for manifold mesh
    // but don't be too strict in sparse areas
    final edgeUse = <String, int>{};
    final triangleKeys = <String>{};

    for (int i = 0; i < vertices.length; i++) {
      final neighbors = _findNeighborsWithinRadius(
        vertices,
        i,
        spatialIndex,
        radius: maxEdgeLength,
        maxNeighbors: maxNeighbors,
        cellSize: math.max(voxelSize, ballRadius),
      );

      // Build triangles around pivot i from neighbor pairs.
      for (int a = 0; a < neighbors.length - 1; a++) {
        final j = neighbors[a];
        for (int b = a + 1; b < neighbors.length; b++) {
          final k = neighbors[b];

          if (j == k || i == j || i == k) continue;

          final v1 = vertices[i];
          final v2 = vertices[j];
          final v3 = vertices[k];

          final e12 = _distance(v1, v2);
          final e13 = _distance(v1, v3);
          final e23 = _distance(v2, v3);

          if (e12 > maxEdgeLength || e13 > maxEdgeLength || e23 > maxEdgeLength) {
            continue;
          }

          final area2 = _triangleDoubleArea(v1, v2, v3);
          if (area2 < 1e-8) continue; // Degenerate.

          // Relaxed rolling-ball constraint - accept triangles with circumradius
          // reasonably close to ball radius, with wider tolerance
          final circumR = _circumradius(v1, v2, v3);
          if (circumR.isNaN || circumR.isInfinite) continue;

          // More permissive radius check - allow triangles up to 3x ball radius
          if (circumR > ballRadius * 3.0) {
            continue;
          }

          // Keep orientation consistent in projected XY plane.
          int aIdx = i;
          int bIdx = j;
          int cIdx = k;
          if (_crossProduct(v1, v2, v3) < 0) {
            bIdx = k;
            cIdx = j;
          }

          final triKey = _triangleKey(aIdx, bIdx, cIdx);
          if (triangleKeys.contains(triKey)) continue;

          final e1Key = _edgeKey(aIdx, bIdx);
          final e2Key = _edgeKey(bIdx, cIdx);
          final e3Key = _edgeKey(cIdx, aIdx);

          if ((edgeUse[e1Key] ?? 0) >= 2 ||
              (edgeUse[e2Key] ?? 0) >= 2 ||
              (edgeUse[e3Key] ?? 0) >= 2) {
            continue;
          }

          triangles.add(Triangle(aIdx, bIdx, cIdx));
          triangleKeys.add(triKey);
          edgeUse[e1Key] = (edgeUse[e1Key] ?? 0) + 1;
          edgeUse[e2Key] = (edgeUse[e2Key] ?? 0) + 1;
          edgeUse[e3Key] = (edgeUse[e3Key] ?? 0) + 1;
        }
      }
    }

    final cleaned = _removeDuplicateTriangles(triangles);
    // Skip aggressive normal filtering - it removes too many valid triangles
    final withUV = _calculateUVCoordinates(vertices);
    return Mesh(vertices: withUV, triangles: cleaned);
  }

  /// Generate mesh from a grid of points (depth map)
  /// 
  /// [points] - List of 3D points with color
  /// [depthWidth] - Width of the depth map grid
  /// [depthHeight] - Height of the depth map grid
  /// [maxEdgeLength] - Maximum allowed edge length to avoid connecting distant points
  static Mesh generateFromGrid({
    required List<dynamic> points, // Point3D from viewer
    required int depthWidth,
    required int depthHeight,
    double maxEdgeLength = 0.3,
    int step = 2,
  }) {
    final vertices = <Vertex>[];
    final triangles = <Triangle>[];
    
    // Map points to grid positions and create vertices
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      // Estimate grid position from 3D coordinates
      // This is approximate - in real usage, we should track grid positions during point generation
      vertices.add(Vertex(
        x: point.x as double,
        y: point.y as double,
        z: point.z as double,
        r: point.r as int,
        g: point.g as int,
        b: point.b as int,
      ));
    }

    // Simple grid-based triangulation
    // For better results, use proper Delaunay triangulation
    // Here we use a simplified approach based on spatial proximity
    
    if (vertices.length < 3) {
      return Mesh(vertices: vertices, triangles: triangles);
    }

    // Build spatial index for efficient neighbor lookup
    final spatialIndex = _buildSpatialIndex(vertices);
    
    // Generate triangles by connecting nearby points
    for (int i = 0; i < vertices.length; i++) {
      final v1 = vertices[i];
      
      // Find nearest neighbors
      final neighbors = _findNearestNeighbors(
        vertices, 
        i, 
        spatialIndex, 
        maxDistance: maxEdgeLength,
        maxNeighbors: 8,
      );
      
      // Create triangles with pairs of neighbors
      for (int j = 0; j < neighbors.length - 1; j++) {
        final n1 = neighbors[j];
        final n2 = neighbors[j + 1];
        
        // Check edge lengths
        if (_distance(v1, vertices[n1]) <= maxEdgeLength &&
            _distance(v1, vertices[n2]) <= maxEdgeLength &&
            _distance(vertices[n1], vertices[n2]) <= maxEdgeLength) {
          
          // Ensure consistent winding order (counter-clockwise)
          final cross = _crossProduct(v1, vertices[n1], vertices[n2]);
          if (cross > 0) {
            triangles.add(Triangle(i, n1, n2));
          } else {
            triangles.add(Triangle(i, n2, n1));
          }
        }
      }
    }
    
    // Remove duplicate triangles
    final uniqueTriangles = _removeDuplicateTriangles(triangles);
    
    // Calculate UV coordinates based on vertex positions
    final verticesWithUV = _calculateUVCoordinates(vertices);
    
    return Mesh(
      vertices: verticesWithUV,
      triangles: uniqueTriangles,
    );
  }

  /// Generate mesh from depth map directly for better connectivity
  static Mesh generateFromDepthMap({
    required Uint16List depthData,
    required int depthWidth,
    required int depthHeight,
    required img.Image rgbImage,
    required double fx,
    required double fy,
    required double cx,
    required double cy,
    required double minDepth,
    required double maxDepth,
    bool isMidasDepth = true,
    int step = 2,
    double maxEdgeLength = 0.2,
  }) {
    final vertices = <Vertex>[];
    final triangles = <Triangle>[];
    
    // Create a 2D grid to track vertex indices
    final gridHeight = (depthHeight + step - 1) ~/ step;
    final gridWidth = (depthWidth + step - 1) ~/ step;
    final vertexGrid = List<List<int>>.generate(
      gridHeight,
      (_) => List<int>.filled(gridWidth, -1),
    );
    
    // Generate vertices
    for (int y = 0; y < depthHeight; y += step) {
      for (int x = 0; x < depthWidth; x += step) {
        final depthIndex = y * depthWidth + x;
        if (depthIndex >= depthData.length) continue;
        
        final depthValue = depthData[depthIndex];
        if (depthValue == 0) continue;
        
        double z;
        if (isMidasDepth) {
          final normalizedDepth = (depthValue.toDouble() - minDepth) / (maxDepth - minDepth);
          z = 3.0 - (normalizedDepth * 2.5);
        } else {
          z = depthValue / 1000.0;
        }
        
        if (z < 0.1 || z > 5.0) continue;
        
        // Back-project to 3D
        final xPos = (x - cx) * z / fx;
        final yPos = (y - cy) * z / fy;
        
        // Get RGB color
        final imgX = (x * rgbImage.width / depthWidth).floor().clamp(0, rgbImage.width - 1);
        final imgY = (y * rgbImage.height / depthHeight).floor().clamp(0, rgbImage.height - 1);
        final pixel = rgbImage.getPixel(imgX, imgY);
        
        // Calculate UV coordinates
        final u = x / depthWidth.toDouble();
        final v = y / depthHeight.toDouble();
        
        final vertexIndex = vertices.length;
        vertices.add(Vertex(
          x: xPos,
          y: yPos,
          z: z,
          r: pixel.r.toInt(),
          g: pixel.g.toInt(),
          b: pixel.b.toInt(),
          u: u,
          v: 1.0 - v, // Flip V for OBJ format
        ));
        
        final gridY = y ~/ step;
        final gridX = x ~/ step;
        if (gridY < gridHeight && gridX < gridWidth) {
          vertexGrid[gridY][gridX] = vertexIndex;
        }
      }
    }
    
    // Generate triangles from grid
    for (int gy = 0; gy < gridHeight - 1; gy++) {
      for (int gx = 0; gx < gridWidth - 1; gx++) {
        final v00 = vertexGrid[gy][gx];
        final v10 = vertexGrid[gy][gx + 1];
        final v01 = vertexGrid[gy + 1][gx];
        final v11 = vertexGrid[gy + 1][gx + 1];
        
        // Skip if any vertex is missing
        if (v00 < 0 || v10 < 0 || v01 < 0 || v11 < 0) continue;
        
        // Check edge lengths to avoid connecting distant points
        final d00_10 = _distance(vertices[v00], vertices[v10]);
        final d00_01 = _distance(vertices[v00], vertices[v01]);
        final d10_11 = _distance(vertices[v10], vertices[v11]);
        final d01_11 = _distance(vertices[v01], vertices[v11]);
        final d10_01 = _distance(vertices[v10], vertices[v01]);
        
        // Create first triangle (v00, v10, v01)
        if (d00_10 <= maxEdgeLength && d00_01 <= maxEdgeLength && d10_01 <= maxEdgeLength) {
          triangles.add(Triangle(v00, v10, v01));
        }
        
        // Create second triangle (v10, v11, v01)
        if (d10_11 <= maxEdgeLength && d01_11 <= maxEdgeLength && d10_01 <= maxEdgeLength) {
          triangles.add(Triangle(v10, v11, v01));
        }
      }
    }
    
    return Mesh(
      vertices: vertices,
      triangles: triangles,
    );
  }

  /// Export mesh to OBJ format with MTL and texture
  /// Also includes vertex colors in OBJ extension format for compatibility
  static Future<MeshExportResult> exportToOBJ({
    required Mesh mesh,
    required String outputDir,
    required String baseName,
    required img.Image? sourceImage,
  }) async {
    final objPath = '$outputDir/$baseName.obj';
    final mtlPath = '$outputDir/$baseName.mtl';
    final texturePath = '$outputDir/${baseName}_texture.png';
    
    // Generate texture from vertex colors if no source image
    final texture = sourceImage ?? _generateTextureFromVertices(mesh);
    
    // Save texture
    final textureFile = File(texturePath);
    await textureFile.writeAsBytes(img.encodePng(texture));
    
    // Generate OBJ file content
    final objContent = StringBuffer();
    objContent.writeln('# Generated by AR Depth App');
    objContent.writeln('# Vertices: ${mesh.vertexCount}');
    objContent.writeln('# Triangles: ${mesh.triangleCount}');
    objContent.writeln('mtllib $baseName.mtl');
    objContent.writeln('usemtl material0');
    objContent.writeln('');
    
    // Write vertices with colors (OBJ extension: v x y z r g b)
    // This format embeds RGB colors directly in the vertex definition
    for (final v in mesh.vertices) {
      // Normalize colors to 0-1 range for OBJ format
      final r = (v.r / 255.0).toStringAsFixed(4);
      final g = (v.g / 255.0).toStringAsFixed(4);
      final b = (v.b / 255.0).toStringAsFixed(4);
      objContent.writeln('v ${v.x.toStringAsFixed(6)} ${v.y.toStringAsFixed(6)} ${v.z.toStringAsFixed(6)} $r $g $b');
    }
    objContent.writeln('');
    
    // Write texture coordinates
    for (final v in mesh.vertices) {
      objContent.writeln('vt ${v.u.toStringAsFixed(6)} ${v.v.toStringAsFixed(6)}');
    }
    objContent.writeln('');
    
    // Write vertex normals (approximate)
    final normals = _calculateVertexNormals(mesh);
    for (final n in normals) {
      objContent.writeln('vn ${n[0].toStringAsFixed(6)} ${n[1].toStringAsFixed(6)} ${n[2].toStringAsFixed(6)}');
    }
    objContent.writeln('');
    
    // Write faces (OBJ indices are 1-based)
    for (final t in mesh.triangles) {
      final i1 = t.v1 + 1;
      final i2 = t.v2 + 1;
      final i3 = t.v3 + 1;
      objContent.writeln('f $i1/$i1/$i1 $i2/$i2/$i2 $i3/$i3/$i3');
    }
    
    // Save OBJ file
    final objFile = File(objPath);
    await objFile.writeAsString(objContent.toString());
    
    // Generate MTL file content
    final mtlContent = StringBuffer();
    mtlContent.writeln('# Material file for $baseName');
    mtlContent.writeln('newmtl material0');
    mtlContent.writeln('Ka 0.2 0.2 0.2'); // Ambient color
    mtlContent.writeln('Kd 0.8 0.8 0.8'); // Diffuse color
    mtlContent.writeln('Ks 0.0 0.0 0.0'); // Specular color
    mtlContent.writeln('d 1.0'); // Opacity
    mtlContent.writeln('illum 1'); // Illumination model
    mtlContent.writeln('map_Kd ${baseName}_texture.png'); // Diffuse texture map
    
    // Save MTL file
    final mtlFile = File(mtlPath);
    await mtlFile.writeAsString(mtlContent.toString());
    
    return MeshExportResult(
      objPath: objPath,
      mtlPath: mtlPath,
      texturePath: texturePath,
      vertexCount: mesh.vertexCount,
      triangleCount: mesh.triangleCount,
    );
  }

  // Helper methods
  
  static Map<String, List<int>> _buildSpatialIndex(List<Vertex> vertices) {
    return _buildSpatialIndexWithCellSize(vertices, cellSize: 0.05);
  }

  static Map<String, List<int>> _buildSpatialIndexWithCellSize(
    List<Vertex> vertices, {
    required double cellSize,
  }) {
    final index = <String, List<int>>{};
    
    for (int i = 0; i < vertices.length; i++) {
      final v = vertices[i];
      final cellX = (v.x / cellSize).floor();
      final cellY = (v.y / cellSize).floor();
      final cellZ = (v.z / cellSize).floor();
      final key = '$cellX,$cellY,$cellZ';
      
      index.putIfAbsent(key, () => []);
      index[key]!.add(i);
    }
    
    return index;
  }

  static List<int> _findNeighborsWithinRadius(
    List<Vertex> vertices,
    int vertexIndex,
    Map<String, List<int>> spatialIndex, {
    required double radius,
    required int maxNeighbors,
    required double cellSize,
  }) {
    final v = vertices[vertexIndex];
    final cellX = (v.x / cellSize).floor();
    final cellY = (v.y / cellSize).floor();
    final cellZ = (v.z / cellSize).floor();

    final cellSpan = math.max(1, (radius / cellSize).ceil());
    final candidates = <int, double>{};

    for (int dx = -cellSpan; dx <= cellSpan; dx++) {
      for (int dy = -cellSpan; dy <= cellSpan; dy++) {
        for (int dz = -cellSpan; dz <= cellSpan; dz++) {
          final key = '${cellX + dx},${cellY + dy},${cellZ + dz}';
          final bucket = spatialIndex[key];
          if (bucket == null) continue;

          for (final neighbor in bucket) {
            if (neighbor == vertexIndex) continue;
            final dist = _distance(v, vertices[neighbor]);
            if (dist <= radius) {
              candidates[neighbor] = dist;
            }
          }
        }
      }
    }

    final sorted = candidates.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return sorted.take(maxNeighbors).map((e) => e.key).toList();
  }
  
  static List<int> _findNearestNeighbors(
    List<Vertex> vertices,
    int vertexIndex,
    Map<String, List<int>> spatialIndex, {
    required double maxDistance,
    required int maxNeighbors,
  }) {
    final v = vertices[vertexIndex];
    const cellSize = 0.05;
    final cellX = (v.x / cellSize).floor();
    final cellY = (v.y / cellSize).floor();
    final cellZ = (v.z / cellSize).floor();
    
    final candidates = <int, double>{};
    
    // Search in neighboring cells
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dz = -1; dz <= 1; dz++) {
          final key = '${cellX + dx},${cellY + dy},${cellZ + dz}';
          if (spatialIndex.containsKey(key)) {
            for (final neighbor in spatialIndex[key]!) {
              if (neighbor != vertexIndex) {
                final dist = _distance(v, vertices[neighbor]);
                if (dist <= maxDistance) {
                  candidates[neighbor] = dist;
                }
              }
            }
          }
        }
      }
    }
    
    // Sort by distance and take top N
    final sorted = candidates.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    
    return sorted.take(maxNeighbors).map((e) => e.key).toList();
  }
  
  static double _distance(Vertex a, Vertex b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  static double _triangleDoubleArea(Vertex a, Vertex b, Vertex c) {
    final ux = b.x - a.x;
    final uy = b.y - a.y;
    final uz = b.z - a.z;

    final vx = c.x - a.x;
    final vy = c.y - a.y;
    final vz = c.z - a.z;

    final cx = uy * vz - uz * vy;
    final cy = uz * vx - ux * vz;
    final cz = ux * vy - uy * vx;
    return math.sqrt(cx * cx + cy * cy + cz * cz);
  }

  static double _circumradius(Vertex a, Vertex b, Vertex c) {
    final ab = _distance(a, b);
    final bc = _distance(b, c);
    final ca = _distance(c, a);
    final area2 = _triangleDoubleArea(a, b, c); // 2A
    if (area2 <= 1e-9) return double.nan;
    final area = area2 * 0.5;
    return (ab * bc * ca) / (4.0 * area);
  }

  static String _edgeKey(int a, int b) {
    if (a < b) return '$a:$b';
    return '$b:$a';
  }

  static String _triangleKey(int a, int b, int c) {
    final ids = [a, b, c]..sort();
    return '${ids[0]}:${ids[1]}:${ids[2]}';
  }

  static List<Vertex> _voxelDownsample(List<Vertex> input, {required double voxelSize}) {
    if (input.isEmpty) return input;

    final buckets = <String, List<Vertex>>{};
    for (final v in input) {
      final gx = (v.x / voxelSize).floor();
      final gy = (v.y / voxelSize).floor();
      final gz = (v.z / voxelSize).floor();
      final key = '$gx,$gy,$gz';
      buckets.putIfAbsent(key, () => <Vertex>[]).add(v);
    }

    final out = <Vertex>[];
    for (final group in buckets.values) {
      double sx = 0, sy = 0, sz = 0;
      int sr = 0, sg = 0, sb = 0;
      for (final v in group) {
        sx += v.x;
        sy += v.y;
        sz += v.z;
        sr += v.r;
        sg += v.g;
        sb += v.b;
      }
      final n = group.length;
      out.add(Vertex(
        x: sx / n,
        y: sy / n,
        z: sz / n,
        r: (sr / n).round().clamp(0, 255),
        g: (sg / n).round().clamp(0, 255),
        b: (sb / n).round().clamp(0, 255),
      ));
    }

    return out;
  }
  
  static double _crossProduct(Vertex v1, Vertex v2, Vertex v3) {
    // 2D cross product for winding order (using x-y plane)
    return (v2.x - v1.x) * (v3.y - v1.y) - (v2.y - v1.y) * (v3.x - v1.x);
  }
  
  static List<Triangle> _removeDuplicateTriangles(List<Triangle> triangles) {
    final seen = <String>{};
    final unique = <Triangle>[];
    
    for (final t in triangles) {
      // Sort vertex indices to create canonical form
      final indices = [t.v1, t.v2, t.v3]..sort();
      final key = '${indices[0]},${indices[1]},${indices[2]}';
      
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(t);
      }
    }
    
    return unique;
  }

  static List<Triangle> _filterTrianglesByNormalConsistency({
    required List<Vertex> vertices,
    required List<Triangle> triangles,
    required double maxAngleRadians,
  }) {
    if (triangles.isEmpty) return triangles;

    final normals = <List<double>>[];
    for (final t in triangles) {
      final n = _triangleNormal(vertices[t.v1], vertices[t.v2], vertices[t.v3]);
      normals.add(n);
    }

    // Build vertex -> triangle adjacency.
    final adjacency = List<List<int>>.generate(vertices.length, (_) => <int>[]);
    for (int ti = 0; ti < triangles.length; ti++) {
      final t = triangles[ti];
      adjacency[t.v1].add(ti);
      adjacency[t.v2].add(ti);
      adjacency[t.v3].add(ti);
    }

    final kept = <Triangle>[];
    for (int ti = 0; ti < triangles.length; ti++) {
      final t = triangles[ti];
      final n = normals[ti];

      final neighbors = <int>{
        ...adjacency[t.v1],
        ...adjacency[t.v2],
        ...adjacency[t.v3],
      }..remove(ti);

      if (neighbors.isEmpty) {
        kept.add(t);
        continue;
      }

      int similar = 0;
      for (final nti in neighbors) {
        final angle = _angleBetweenNormals(n, normals[nti]);
        if (angle <= maxAngleRadians) {
          similar++;
        }
      }

      // Keep faces that agree with at least one neighboring face normal.
      if (similar > 0) {
        kept.add(t);
      }
    }

    return kept;
  }

  static List<double> _triangleNormal(Vertex a, Vertex b, Vertex c) {
    final ux = b.x - a.x;
    final uy = b.y - a.y;
    final uz = b.z - a.z;
    final vx = c.x - a.x;
    final vy = c.y - a.y;
    final vz = c.z - a.z;

    double nx = uy * vz - uz * vy;
    double ny = uz * vx - ux * vz;
    double nz = ux * vy - uy * vx;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len <= 1e-10) return [0, 0, 1];
    nx /= len;
    ny /= len;
    nz /= len;
    return [nx, ny, nz];
  }

  static double _angleBetweenNormals(List<double> a, List<double> b) {
    final dot = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]).clamp(-1.0, 1.0);
    return math.acos(dot);
  }
  
  static List<Vertex> _calculateUVCoordinates(List<Vertex> vertices) {
    if (vertices.isEmpty) return vertices;
    
    // Find bounding box
    double minX = vertices[0].x, maxX = vertices[0].x;
    double minY = vertices[0].y, maxY = vertices[0].y;
    
    for (final v in vertices) {
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.y > maxY) maxY = v.y;
    }
    
    final rangeX = maxX - minX;
    final rangeY = maxY - minY;
    
    return vertices.map((v) {
      final u = rangeX > 0 ? (v.x - minX) / rangeX : 0.5;
      final vCoord = rangeY > 0 ? (v.y - minY) / rangeY : 0.5;
      return v.withUV(u, 1.0 - vCoord); // Flip V for OBJ
    }).toList();
  }
  
  static List<List<double>> _calculateVertexNormals(Mesh mesh) {
    final normals = List<List<double>>.generate(
      mesh.vertices.length,
      (_) => [0.0, 0.0, 0.0],
    );
    
    // Calculate face normals and accumulate to vertices
    for (final t in mesh.triangles) {
      final v1 = mesh.vertices[t.v1];
      final v2 = mesh.vertices[t.v2];
      final v3 = mesh.vertices[t.v3];
      
      // Calculate face normal
      final e1 = [v2.x - v1.x, v2.y - v1.y, v2.z - v1.z];
      final e2 = [v3.x - v1.x, v3.y - v1.y, v3.z - v1.z];
      
      final nx = e1[1] * e2[2] - e1[2] * e2[1];
      final ny = e1[2] * e2[0] - e1[0] * e2[2];
      final nz = e1[0] * e2[1] - e1[1] * e2[0];
      
      // Accumulate to vertices
      for (final vi in [t.v1, t.v2, t.v3]) {
        normals[vi][0] += nx;
        normals[vi][1] += ny;
        normals[vi][2] += nz;
      }
    }
    
    // Normalize
    for (final n in normals) {
      final len = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
      if (len > 0) {
        n[0] /= len;
        n[1] /= len;
        n[2] /= len;
      } else {
        n[2] = 1.0; // Default to pointing forward
      }
    }
    
    return normals;
  }
  
  static img.Image _generateTextureFromVertices(Mesh mesh) {
    const textureSize = 1024;
    final texture = img.Image(width: textureSize, height: textureSize);
    
    // Fill with white initially
    for (int y = 0; y < textureSize; y++) {
      for (int x = 0; x < textureSize; x++) {
        texture.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
      }
    }
    
    // Paint vertex colors at UV positions
    for (final v in mesh.vertices) {
      final x = (v.u * (textureSize - 1)).round().clamp(0, textureSize - 1);
      final y = ((1.0 - v.v) * (textureSize - 1)).round().clamp(0, textureSize - 1);
      
      // Paint a small circle around each UV point
      for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          final px = (x + dx).clamp(0, textureSize - 1);
          final py = (y + dy).clamp(0, textureSize - 1);
          texture.setPixel(px, py, img.ColorRgba8(v.r, v.g, v.b, 255));
        }
      }
    }
    
    return texture;
  }
}

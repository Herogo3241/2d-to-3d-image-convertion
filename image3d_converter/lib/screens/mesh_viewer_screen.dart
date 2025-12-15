import 'dart:typed_data';
import 'package:ditredi/ditredi.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

class MeshViewer extends StatefulWidget {
  final Float32List vertices; // xyz xyz ...
  final Float32List colors; // rgb rgb ...
  final Int32List indices; // triangle indices

  const MeshViewer({
    super.key,
    required this.vertices,
    required this.colors,
    required this.indices,
  });

  @override
  State<MeshViewer> createState() => _MeshViewerState();
}

class _MeshViewerState extends State<MeshViewer> {
  final DiTreDiController _controller = DiTreDiController(
    viewScale: 1.0, // assumes [-1,1] normalized mesh
  );

  late final List<Model3D<Model3D<dynamic>>> _meshModels;

  double _lastRotationX = 0;
  double _lastRotationY = 0;
  double _lastScale = 1.0;



  @override
  void initState() {
    super.initState();
    _meshModels = _buildMesh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("3D Mesh Viewer")),
      body: GestureDetector(
        onScaleStart: (_) {
          _lastRotationX = _controller.rotationX;
          _lastRotationY = _controller.rotationY;
          _lastScale = _controller.viewScale;
        },
        onScaleUpdate: (details) {
          setState(() {
            _controller.rotationY =
                _lastRotationY + details.focalPointDelta.dx * 0.01;

            _controller.rotationX =
                _lastRotationX + details.focalPointDelta.dy * 0.01;

            _controller.viewScale = (_lastScale * details.scale).clamp(
              0.3,
              10.0,
            );
          });
        },
        child: DiTreDi(
          figures: _meshModels,
          controller: _controller,
          config: const DiTreDiConfig(supportZIndex: true),
        ),
      ),
    );
  }

  // ===================================================
  // FAST + NORMALIZED + DECIMATED MESH BUILDER
  // ===================================================
  List<Model3D<Model3D<dynamic>>> _buildMesh() {
    final faces = <Face3D>[];

    // ---------- 1. Compute bounding box ----------
    vector.Vector3 minV = vector.Vector3(1e9, 1e9, 1e9);
    vector.Vector3 maxV = vector.Vector3(-1e9, -1e9, -1e9);

    for (int i = 0; i < widget.vertices.length; i += 3) {
      final v = vector.Vector3(
        widget.vertices[i],
        widget.vertices[i + 1],
        widget.vertices[i + 2],
      );
      minV.x = minV.x < v.x ? minV.x : v.x;
      minV.y = minV.y < v.y ? minV.y : v.y;
      minV.z = minV.z < v.z ? minV.z : v.z;
      maxV.x = maxV.x > v.x ? maxV.x : v.x;
      maxV.y = maxV.y > v.y ? maxV.y : v.y;
      maxV.z = maxV.z > v.z ? maxV.z : v.z;
    }

    final center = (minV + maxV) / 2;
    final diff = maxV - minV;
    final double scale =
        [diff.x, diff.y, diff.z].reduce((a, b) => a > b ? a : b) / 2;

    vector.Vector3 normalize(int vi) {
      return (vector.Vector3(
                widget.vertices[vi * 3],
                widget.vertices[vi * 3 + 1],
                widget.vertices[vi * 3 + 2],
              ) -
              center) /
          scale;
    }

    // ---------- 2. Aggressive triangle decimation ----------
    const int triangleStride = 4; // KEEP 1 / 4 triangles

    for (int i = 0; i < widget.indices.length; i += 3 * triangleStride) {
      if (i + 2 >= widget.indices.length) break;

      final i0 = widget.indices[i];
      final i1 = widget.indices[i + 1];
      final i2 = widget.indices[i + 2];

      final v0 = normalize(i0);
      final v1 = normalize(i1);
      final v2 = normalize(i2);

      final int r = ((widget.colors[i0 * 3]).clamp(0.0, 1.0) * 255).toInt();
      final int g = ((widget.colors[i0 * 3 + 1]).clamp(0.0, 1.0) * 255).toInt();
      final int b = ((widget.colors[i0 * 3 + 2]).clamp(0.0, 1.0) * 255).toInt();

      faces.add(
        Face3D(
          vector.Triangle.points(
            v0,
            v2, // correct winding
            v1,
          ),
          color: Color.fromARGB(255, r, g, b),
        ),
      );
    }

    return [Mesh3D(faces)];
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'dart:math' as math;
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_cube/flutter_cube.dart' as cube;
import 'package:vector_math/vector_math_64.dart' as vmath;
import 'utils/session_metadata.dart';
import 'utils/point_cloud_fusion.dart'; // ← Point3D lives here now
import 'package:image_background_remover/image_background_remover.dart';

// Point3D is imported from utils/point_cloud_fusion.dart — do NOT redefine here.
import 'utils/mesh_generator.dart';

class PointCloudViewerScreen extends StatefulWidget {
  const PointCloudViewerScreen({super.key});

  @override
  State<PointCloudViewerScreen> createState() => _PointCloudViewerScreenState();
}

class _PointCloudViewerScreenState extends State<PointCloudViewerScreen> {
  List<Directory> _sessions = [];
  bool _loading = true;
  Directory? _selectedSession;
  List<Map<String, dynamic>> _captures = [];
  int _currentIndex = 0;
  List<Point3D>? _pointCloud;
  double _rotationX = -0.5;
  double _rotationY = 0.0;
  double _zoom = 1.0;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  double _panX = 0.0;
  double _panY = 0.0;
  bool _useMidasDepth = false;
  String? _statusMessage;
  
  // Mesh generation state
  Mesh? _mesh;
  MeshExportResult? _meshExportResult;
  bool _generatingMesh = false;
  bool _isSharingMesh = false;

  @override
  void initState() {
    super.initState();
    BackgroundRemover.instance.initializeOrt();
    _loadSessions();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final appDir = await getApplicationDocumentsDirectory();
    final capturesDir = Directory('${appDir.path}/captures');
    if (await capturesDir.exists()) {
      final entities = capturesDir.listSync();
      _sessions = entities.whereType<Directory>().toList()
        ..sort((a, b) => b.path.compareTo(a.path));
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _renameSession(Directory sessionDir) async {
    final currentAlias = await SessionMetadata.getSessionAlias(sessionDir);
    final controller = TextEditingController(text: currentAlias);

    if (!mounted) return;
    final newAlias = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Original: ${sessionDir.path.split(Platform.pathSeparator).last}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'Enter custom name',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newAlias != null && newAlias.isNotEmpty) {
      try {
        await SessionMetadata.setSessionAlias(sessionDir, newAlias);
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session name updated successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to update name: $e')));
      }
    }
  }

  Future<void> _deleteSession(Directory sessionDir) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: const Text(
          'Are you sure you want to delete this session? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await sessionDir.delete(recursive: true);
        await _loadSessions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  Uint16List _smoothDepthMap(
    Uint16List depthData,
    int width,
    int height, {
    int kernelSize = 5,
  }) {
    final smoothed = Uint16List(depthData.length);
    final radius = kernelSize ~/ 2;
    final kernel = <int>[];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        kernel.clear();
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final ny = y + dy;
            final nx = x + dx;
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              final idx = ny * width + nx;
              if (depthData[idx] > 0) kernel.add(depthData[idx]);
            }
          }
        }
        if (kernel.isNotEmpty) {
          kernel.sort();
          smoothed[y * width + x] = kernel[kernel.length ~/ 2];
        } else {
          smoothed[y * width + x] = depthData[y * width + x];
        }
      }
    }
    return smoothed;
  }

  List<Point3D> _filterIsolatedPoints(
    List<Point3D> points, {
    double maxNeighborDistance = 0.15,
    int minNeighbors = 3,
  }) {
    if (points.isEmpty) return points;
    final filtered = <Point3D>[];
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      int neighborCount = 0;
      for (int j = 0; j < points.length; j++) {
        if (i == j) continue;
        if (point.distanceTo(points[j]) <= maxNeighborDistance) {
          neighborCount++;
        }
      }
      if (neighborCount >= minNeighbors) filtered.add(point);
    }
    return filtered;
  }

  Future<void> _loadCapturesFromSession(Directory session) async {
    setState(() {
      _selectedSession = session;
      _captures = [];
      _currentIndex = 0;
      _pointCloud = null;
    });

    final jsonFile = File('${session.path}/captures.json');
    if (await jsonFile.exists()) {
      final jsonContent = await jsonFile.readAsString();
      final List<dynamic> data = json.decode(jsonContent);

      final fixedCaptures = data.map((capture) {
        final captureMap = Map<String, dynamic>.from(capture);
        final imageFilename = captureMap['imagePath']
            .toString()
            .split('/')
            .last
            .split('\\')
            .last;
        final depthFilename = captureMap['depthPath']
            .toString()
            .split('/')
            .last
            .split('\\')
            .last;
        captureMap['imagePath'] = '${session.path}/$imageFilename';
        captureMap['depthPath'] = '${session.path}/$depthFilename';
        return captureMap;
      }).toList();

      setState(() {
        _captures = fixedCaptures;
      });
    }
  }

  Future<void> _generatePointCloud() async {
    if (_captures.isEmpty || _currentIndex >= _captures.length) return;

    final capture = _captures[_currentIndex];
    final imagePath = capture['imagePath'];
    final depthPath = capture['depthPath'];

    if (_useMidasDepth) {
      final sessionDir = _selectedSession!.path;
      final depthFilename = depthPath.split('/').last;
      final frameNumber = depthFilename.replaceAll(RegExp(r'[^0-9]'), '');
      final midasDepthPath = '$sessionDir/enhanced_depth_$frameNumber.raw';

      if (!await File(midasDepthPath).exists()) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('MiDaS Depth Not Available'),
            content: const Text(
              'MiDaS depth map has not been generated for this image.\n\n'
              'Please go to Depth Estimation screen and process this image first.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        setState(() {
          _statusMessage = 'MiDaS depth not available - process image first';
        });
        return;
      }
    }

    setState(() {
      _pointCloud = null;
      _statusMessage = 'Generating 3D point cloud...';
    });

    try {
      double minDepth = double.infinity;
      double maxDepth = 0.0;

      final sessionDir = _selectedSession!.path;
      final depthFilename = depthPath.split('/').last;
      final frameNumber = depthFilename.replaceAll(RegExp(r'[^0-9]'), '');
      final midasDepthPath = '$sessionDir/enhanced_depth_$frameNumber.raw';

      String actualDepthPath = depthPath;
      bool usingMidas = false;

      if (_useMidasDepth && await File(midasDepthPath).exists()) {
        actualDepthPath = midasDepthPath;
        usingMidas = true;
      }

      final imageBytes = await File(imagePath).readAsBytes();
      final rgbImage = img.decodeImage(imageBytes);
      if (rgbImage == null) throw Exception('Failed to decode RGB image');

      Uint16List depthData;
      int depthWidth = 256;
      int depthHeight = 256;

      if (usingMidas) {
        final depthBytes = await File(actualDepthPath).readAsBytes();
        if (depthBytes.length > 8) {
          final header = ByteData.sublistView(depthBytes, 0, 8);
          final headerWidth = header.getUint32(0, Endian.little);
          final headerHeight = header.getUint32(4, Endian.little);
          final expectedSize = 8 + headerWidth * headerHeight * 2;
          if (headerWidth > 0 &&
              headerWidth <= 4096 &&
              headerHeight > 0 &&
              headerHeight <= 4096 &&
              depthBytes.length == expectedSize) {
            depthWidth = headerWidth;
            depthHeight = headerHeight;
            depthData = depthBytes.buffer.asUint16List(8);
          } else {
            final totalPixels = depthBytes.length ~/ 2;
            depthData = depthBytes.buffer.asUint16List();
            if (totalPixels == 256 * 256) {
              depthWidth = depthHeight = 256;
            } else {
              final sqrtVal = math.sqrt(totalPixels).round();
              depthWidth = depthHeight =
                  (sqrtVal * sqrtVal == totalPixels) ? sqrtVal : 256;
            }
          }
        } else {
          throw Exception('Invalid depth file format');
        }
      } else {
        final depthBytes = await File(actualDepthPath).readAsBytes();
        depthData = depthBytes.buffer.asUint16List();
        depthWidth = 160;
        depthHeight = 90;
      }

      final points = <Point3D>[];

      if (usingMidas) {
        for (int i = 0; i < depthData.length; i++) {
          if (depthData[i] > 0) {
            final d = depthData[i].toDouble();
            if (d < minDepth) minDepth = d;
            if (d > maxDepth) maxDepth = d;
          }
        }
      }

      final fovH = 60.0 * math.pi / 180.0;
      final fx = depthWidth / (2.0 * math.tan(fovH / 2.0));
      final fy = fx;
      final cx = depthWidth / 2.0;
      final cy = depthHeight / 2.0;

      depthData = _smoothDepthMap(depthData, depthWidth, depthHeight);

      final step = usingMidas ? 2 : 1;

      for (int y = 0; y < depthHeight; y += step) {
        for (int x = 0; x < depthWidth; x += step) {
          final depthIndex = y * depthWidth + x;
          if (depthIndex >= depthData.length) continue;
          final depthValue = depthData[depthIndex];
          if (depthValue == 0) continue;

          double z;
          if (usingMidas) {
            // MiDaS saved map in this pipeline is relative inverse to metric depth.
            // Normalize to 0..1 where higher value means farther scene content.
            final normalizedDepth = (depthValue.toDouble() - minDepth) / (maxDepth - minDepth);
            // Convert to metric depth: low value -> close, high value -> far
            z = 0.5 + (normalizedDepth * 2.5); // Maps to 0.5m (close) to 3.0m (far)
          } else {
            z = depthValue / 1000.0;
          }
          if (z < 0.1 || z > 5.0) continue;

          final xPos = (x - cx) * z / fx;
          final yPos = (y - cy) * z / fy;

          final imgX = (x * rgbImage.width / depthWidth).floor();
          final imgY = (y * rgbImage.height / depthHeight).floor();

          if (imgX >= 0 &&
              imgX < rgbImage.width &&
              imgY >= 0 &&
              imgY < rgbImage.height) {
            final pixel = rgbImage.getPixel(imgX, imgY);
            points.add(Point3D(
              x: xPos,
              y: yPos,
              z: z,
              r: pixel.r.toInt(),
              g: pixel.g.toInt(),
              b: pixel.b.toInt(),
            ));
          }
        }
      }

      final filteredPoints = _filterIsolatedPoints(
        points,
        maxNeighborDistance: 0.12,
        minNeighbors: 2,
      );

      setState(() {
        _pointCloud = points;
        _mesh = null; // Reset mesh when regenerating point cloud
        _meshExportResult = null;
        final depthInfo = usingMidas && minDepth != double.infinity 
            ? ' | Range: ${(minDepth/256/1000).toStringAsFixed(2)}-${(maxDepth/256/1000).toStringAsFixed(2)}m'
            : '';
        final reduction = points.isNotEmpty
            ? ((1 - filteredPoints.length / points.length) * 100)
                .toStringAsFixed(1)
            : '0';
        _statusMessage =
            '${filteredPoints.length} points (filtered $reduction%) | ${usingMidas ? "MiDaS" : "ARCore"} depth$depthInfo';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating point cloud: $e')),
      );
    }
  }

  Future<void> _generateMesh() async {
    if (_pointCloud == null || _pointCloud!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generate point cloud first')),
      );
      return;
    }

    setState(() {
      _generatingMesh = true;
      _statusMessage = 'Generating mesh...';
    });

    try {
      final capture = _captures[_currentIndex];
      final imagePath = capture['imagePath'];
      
      // Load source image for texture
      final imageBytes = await File(imagePath).readAsBytes();
      final sourceImage = img.decodeImage(imageBytes);
      
      // Generate mesh from point cloud using rolling-ball triangulation
      final rawMesh = MeshGenerator.generateWithBallRolling(
        points: _pointCloud!,
        ballRadius: 0.08,
        maxEdgeLength: 0.18,
        maxNeighbors: 12,
        voxelSize: 0.03,
      );

      // Keep a render-safe triangle budget to avoid runtime parser/render stalls.
      final mesh = _decimateMeshForRuntime(rawMesh, maxTriangles: 22000);

      if (mesh.triangleCount == 0) {
        throw Exception('Mesh generation produced no valid faces. Try another frame or depth map.');
      }

      // Export mesh to files
      final sessionDir = _selectedSession!.path;
      final frameNumber = capture['depthPath'].toString().split('/').last.replaceAll(RegExp(r'[^0-9]'), '');
      final baseName = 'mesh_frame_$frameNumber';
      
      final exportResult = await MeshGenerator.exportToOBJ(
        mesh: mesh,
        outputDir: sessionDir,
        baseName: baseName,
        sourceImage: sourceImage,
      );

      setState(() {
        _mesh = mesh;
        _meshExportResult = exportResult;
        _generatingMesh = false;
        _statusMessage =
            'Mesh (Ball Rolling): ${exportResult.vertexCount} vertices, ${exportResult.triangleCount} triangles';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mesh exported: $baseName.obj'),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () => _shareMesh(),
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _generatingMesh = false;
        _statusMessage = 'Error generating mesh: $e';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _shareMesh() async {
    if (_meshExportResult == null || _isSharingMesh) return;

    try {
      setState(() {
        _isSharingMesh = true;
      });

      // Share as a single zip to reduce memory pressure and avoid activity crashes.
      final result = _meshExportResult!;
      final zipPath = result.objPath.replaceAll('.obj', '.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      encoder.addFile(File(result.objPath));
      encoder.addFile(File(result.mtlPath));
      encoder.addFile(File(result.texturePath));
      encoder.close();
      
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zipPath)],
          subject: '3D Mesh Export',
          text: 'Exported 3D mesh (${result.vertexCount} vertices) as ZIP',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharingMesh = false;
        });
      }
    }
  }

  Future<void> _openRenderedMeshViewer() async {
    if (_meshExportResult == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RenderedMeshViewerScreen(
          objPath: _meshExportResult!.objPath,
          texturePath: _meshExportResult!.texturePath,
        ),
      ),
    );
  }

  Mesh _decimateMeshForRuntime(Mesh mesh, {required int maxTriangles}) {
    if (mesh.triangleCount <= maxTriangles) return mesh;

    final stride = (mesh.triangleCount / maxTriangles).ceil();
    final reduced = <Triangle>[];
    for (int i = 0; i < mesh.triangles.length; i += stride) {
      reduced.add(mesh.triangles[i]);
    }

    return Mesh(
      vertices: mesh.vertices,
      triangles: reduced,
      textureWidth: mesh.textureWidth,
      textureHeight: mesh.textureHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('3D Viewer')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_selectedSession == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Select Session')),
        body: _sessions.isEmpty
            ? const Center(child: Text('No sessions found'))
            : ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final session = _sessions[index];
                  final sessionName = session.path.split('/').last;
                  return FutureBuilder<String>(
                    future: SessionMetadata.getSessionAlias(session),
                    builder: (context, snapshot) {
                      final displayName = snapshot.data ?? sessionName;
                      return ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(displayName),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _renameSession(session),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteSession(session),
                            ),
                          ],
                        ),
                        onTap: () => _loadCapturesFromSession(session),
                      );
                    },
                  );
                },
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            Text('3D Viewer (${_currentIndex + 1}/${_captures.length})'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _selectedSession = null;
              _captures = [];
              _currentIndex = 0;
              _pointCloud = null;
            });
          },
        ),
      ),
      body: _captures.isEmpty
          ? const Center(child: Text('No captures in this session'))
          : Column(
              children: [
                Expanded(
                  child: _pointCloud == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.view_in_ar,
                                  size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              const Text('No point cloud generated'),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _generatePointCloud,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Generate Point Cloud'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('Use MiDaS Depth: '),
                                  Switch(
                                    value: _useMidasDepth,
                                    onChanged: (value) {
                                      setState(() {
                                        _useMidasDepth = value;
                                        _pointCloud = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_statusMessage != null)
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(_statusMessage!,
                                      style:
                                          const TextStyle(color: Colors.grey)),
                                ),
                            ],
                          ),
                        )
                      : GestureDetector(
                          onScaleStart: (details) {
                            setState(() {
                              _offsetX = 0.0;
                              _offsetY = 0.0;
                            });
                          },
                          onScaleUpdate: (details) {
                            setState(() {
                              if (details.scale != 1.0) {
                                _zoom *= details.scale;
                                _zoom = _zoom.clamp(0.1, 10.0);
                              }
                              if (details.pointerCount == 1) {
                                _rotationY +=
                                    details.focalPointDelta.dx * 0.01;
                                _rotationX +=
                                    details.focalPointDelta.dy * 0.01;
                              } else if (details.pointerCount == 2) {
                                _panX += details.focalPointDelta.dx / 100;
                                _panY += details.focalPointDelta.dy / 100;
                              }
                            });
                          },
                          onScaleEnd: (details) {
                            // no-op
                          },
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: PointCloudPainter(
                                points: _pointCloud!,
                                rotationX: _rotationX,
                                rotationY: _rotationY,
                                zoom: _zoom,
                                offsetX: _offsetX + _panX * 100,
                                offsetY: _offsetY + _panY * 100,
                              ),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                ),
                if (_pointCloud != null)
                  Column(
                    children: [
                      if (_statusMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          color: Colors.black87,
                          child: Text(
                            _statusMessage!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: Colors.black54,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.add,
                                      color: Colors.white),
                                  onPressed: () {
                                    setState(() {
                                      _zoom = (_zoom * 1.2).clamp(0.1, 10.0);
                                    });
                                  },
                                ),
                                const Text('Zoom',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 10)),
                                IconButton(
                                  icon: const Icon(Icons.remove,
                                      color: Colors.white),
                                  onPressed: () {
                                    setState(() {
                                      _zoom = (_zoom / 1.2).clamp(0.1, 10.0);
                                    });
                                  },
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                const Text('Drag to rotate',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 12)),
                                const SizedBox(height: 4),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Reset View'),
                                  onPressed: () {
                                    setState(() {
                                      _rotationX = -0.5;
                                      _rotationY = 0.0;
                                      _zoom = 1.0;
                                      _offsetX = 0.0;
                                      _offsetY = 0.0;
                                      _panX = 0.0;
                                      _panY = 0.0;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Mesh generation controls
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: Colors.black38,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (_mesh != null) ...[
                              ElevatedButton.icon(
                                icon: const Icon(Icons.threed_rotation, size: 16),
                                label: const Text('View Rendered 3D'),
                                onPressed: _meshExportResult != null ? _openRenderedMeshViewer : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                              // Share button
                              ElevatedButton.icon(
                                icon: _isSharingMesh
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Icon(Icons.share, size: 16),
                                label: Text(_isSharingMesh ? 'Preparing...' : 'Export'),
                                onPressed: _meshExportResult != null && !_isSharingMesh ? _shareMesh : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ] else ...[
                              // Generate mesh button
                              ElevatedButton.icon(
                                icon: _generatingMesh 
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Icon(Icons.view_in_ar, size: 16),
                                label: Text(_generatingMesh ? 'Generating...' : 'Generate Mesh'),
                                onPressed: _generatingMesh ? null : _generateMesh,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _currentIndex > 0
                            ? () {
                                setState(() {
                                  _currentIndex--;
                                  _pointCloud = null;
                                });
                              }
                            : null,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Previous'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _generatePointCloud,
                        icon: const Icon(Icons.threed_rotation),
                        label: const Text('Generate 3D'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _currentIndex < _captures.length - 1
                            ? () {
                                setState(() {
                                  _currentIndex++;
                                  _pointCloud = null;
                                });
                              }
                            : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PointCloudPainter — shared by PointCloudViewerScreen and MultiViewFusionScreen
// ─────────────────────────────────────────────────────────────────────────────
class PointCloudPainter extends CustomPainter {
  final List<Point3D> points;
  final double rotationX;
  final double rotationY;
  final double zoom;
  final double offsetX;
  final double offsetY;

  PointCloudPainter({
    required this.points,
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2 + offsetX;
    final centerY = size.height / 2 + offsetY;
    final scale = math.min(size.width, size.height) * 0.3 * zoom;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black,
    );

    final sortedPoints = List<Point3D>.from(points);
    sortedPoints.sort((a, b) => _rotateZ(a).compareTo(_rotateZ(b)));

    for (final point in sortedPoints) {
      final rotated = _rotate3D(point);
      final screenX = centerX + rotated.x * scale;
      final screenY = centerY - rotated.y * scale;

      if (screenX < 0 ||
          screenX > size.width ||
          screenY < 0 ||
          screenY > size.height) continue;

      final pointSize = math.max(1.5, 3.0 / (1.0 + rotated.z.abs()));
      canvas.drawCircle(
        Offset(screenX, screenY),
        pointSize,
        Paint()
          ..color = Color.fromRGBO(point.r, point.g, point.b, 1.0)
          ..style = PaintingStyle.fill,
      );
    }

    _drawAxes(canvas, centerX, centerY, scale);
  }

  void _drawAxes(Canvas canvas, double centerX, double centerY, double scale) {
    const axisLength = 0.2;
    final xEnd = _rotate3D(
        Point3D(x: axisLength, y: 0, z: 0, r: 255, g: 0, b: 0));
    canvas.drawLine(Offset(centerX, centerY),
        Offset(centerX + xEnd.x * scale, centerY - xEnd.y * scale),
        Paint()
          ..color = Colors.red
          ..strokeWidth = 2);

    final yEnd = _rotate3D(
        Point3D(x: 0, y: axisLength, z: 0, r: 0, g: 255, b: 0));
    canvas.drawLine(Offset(centerX, centerY),
        Offset(centerX + yEnd.x * scale, centerY - yEnd.y * scale),
        Paint()
          ..color = Colors.green
          ..strokeWidth = 2);

    final zEnd = _rotate3D(
        Point3D(x: 0, y: 0, z: axisLength, r: 0, g: 0, b: 255));
    canvas.drawLine(Offset(centerX, centerY),
        Offset(centerX + zEnd.x * scale, centerY - zEnd.y * scale),
        Paint()
          ..color = Colors.blue
          ..strokeWidth = 2);
  }

  Point3D _rotate3D(Point3D point) {
    final cosX = math.cos(rotationX), sinX = math.sin(rotationX);
    final y1 = point.y * cosX - point.z * sinX;
    final z1 = point.y * sinX + point.z * cosX;

    final cosY = math.cos(rotationY), sinY = math.sin(rotationY);
    final x2 = point.x * cosY + z1 * sinY;
    final z2 = -point.x * sinY + z1 * cosY;

    return Point3D(x: x2, y: y1, z: z2, r: point.r, g: point.g, b: point.b);
  }

  double _rotateZ(Point3D point) {
    final z1 = point.y * math.sin(rotationX) + point.z * math.cos(rotationX);
    return -point.x * math.sin(rotationY) + z1 * math.cos(rotationY);
  }

  @override
  bool shouldRepaint(PointCloudPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.rotationX != rotationX ||
        oldDelegate.rotationY != rotationY ||
        oldDelegate.zoom != zoom ||
        oldDelegate.offsetX != offsetX ||
        oldDelegate.offsetY != offsetY;
  }
}

/// Painter for rendering mesh with wireframe and filled triangles
class MeshPainter extends CustomPainter {
  final Mesh mesh;
  final double rotationX;
  final double rotationY;
  final double zoom;
  final double offsetX;
  final double offsetY;
  final bool interactionMode;

  MeshPainter({
    required this.mesh,
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    required this.offsetX,
    required this.offsetY,
    this.interactionMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2 + offsetX;
    final centerY = size.height / 2 + offsetY;
    final scale = math.min(size.width, size.height) * 0.4 * zoom;

    // Precompute rotated vertices once per frame to avoid repeated trig work.
    final rotatedVertices = List<Vertex>.generate(
      mesh.vertices.length,
      (i) => _rotate3D(mesh.vertices[i]),
      growable: false,
    );

    // Interaction mode: reduce load aggressively for smooth manipulation.
    final triangleStride = interactionMode ? 3 : 1;
    final drawWireframe = !interactionMode;
    final drawFilled = true;

    // Sort triangles by depth for proper rendering (painter's algorithm)
    final sortedTriangles = List<int>.generate(mesh.triangles.length, (i) => i);
    if (!interactionMode) {
      sortedTriangles.sort((a, b) {
        final ta = mesh.triangles[a];
        final tb = mesh.triangles[b];

        final za = (rotatedVertices[ta.v1].z +
                rotatedVertices[ta.v2].z +
                rotatedVertices[ta.v3].z) /
            3;
        final zb = (rotatedVertices[tb.v1].z +
                rotatedVertices[tb.v2].z +
                rotatedVertices[tb.v3].z) /
            3;
        return zb.compareTo(za); // Back to front
      });
    }

    // Draw triangles
    for (int idx = 0; idx < sortedTriangles.length; idx += triangleStride) {
      final ti = sortedTriangles[idx];
      final t = mesh.triangles[ti];
      final v1 = mesh.vertices[t.v1];
      final v2 = mesh.vertices[t.v2];
      final v3 = mesh.vertices[t.v3];

      // Use cached rotated vertices
      final r1 = rotatedVertices[t.v1];
      final r2 = rotatedVertices[t.v2];
      final r3 = rotatedVertices[t.v3];

      // Calculate screen positions
      final p1 = Offset(centerX + r1.x * scale, centerY - r1.y * scale);
      final p2 = Offset(centerX + r2.x * scale, centerY - r2.y * scale);
      final p3 = Offset(centerX + r3.x * scale, centerY - r3.y * scale);

      // Skip if any point is too far off screen
      final allPoints = [p1, p2, p3];
      if (allPoints.any((p) => p.dx < -size.width || p.dx > size.width * 2 ||
                               p.dy < -size.height || p.dy > size.height * 2)) {
        continue;
      }

      // Calculate face normal for backface culling and lighting
      final nx = (r2.y - r1.y) * (r3.z - r1.z) - (r2.z - r1.z) * (r3.y - r1.y);
      final ny = (r2.z - r1.z) * (r3.x - r1.x) - (r2.x - r1.x) * (r3.z - r1.z);
      final nz = (r2.x - r1.x) * (r3.y - r1.y) - (r2.y - r1.y) * (r3.x - r1.x);
      
      // Simple backface culling - skip if facing away
      if (nz < 0) continue;

      // Calculate average color for the triangle
      final avgR = ((v1.r + v2.r + v3.r) / 3).round();
      final avgG = ((v1.g + v2.g + v3.g) / 3).round();
      final avgB = ((v1.b + v2.b + v3.b) / 3).round();

      // Simple lighting based on face normal
      final normalLen = math.sqrt(nx * nx + ny * ny + nz * nz);
      final light = normalLen > 0 ? (nz / normalLen).clamp(0.3, 1.0) : 0.5;

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..close();

      if (drawFilled) {
        final fillPaint = Paint()
          ..color = Color.fromRGBO(
            (avgR * light).round().clamp(0, 255),
            (avgG * light).round().clamp(0, 255),
            (avgB * light).round().clamp(0, 255),
            interactionMode ? 0.85 : 0.9,
          )
          ..style = PaintingStyle.fill;

        canvas.drawPath(path, fillPaint);
      }

      if (drawWireframe) {
        final edgePaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;

        canvas.drawPath(path, edgePaint);
      }
    }

    // Draw coordinate axes
    _drawAxes(canvas, centerX, centerY, scale);
  }

  void _drawAxes(Canvas canvas, double centerX, double centerY, double scale) {
    const axisLength = 0.2;
    
    // X axis (red)
    final xEnd = _rotate3D(Vertex(x: axisLength, y: 0, z: 0, r: 255, g: 0, b: 0));
    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX + xEnd.x * scale, centerY - xEnd.y * scale),
      Paint()..color = Colors.red..strokeWidth = 2,
    );
    
    // Y axis (green)
    final yEnd = _rotate3D(Vertex(x: 0, y: axisLength, z: 0, r: 0, g: 255, b: 0));
    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX + yEnd.x * scale, centerY - yEnd.y * scale),
      Paint()..color = Colors.green..strokeWidth = 2,
    );
    
    // Z axis (blue)
    final zEnd = _rotate3D(Vertex(x: 0, y: 0, z: axisLength, r: 0, g: 0, b: 255));
    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX + zEnd.x * scale, centerY - zEnd.y * scale),
      Paint()..color = Colors.blue..strokeWidth = 2,
    );
  }

  Vertex _rotate3D(Vertex v) {
    // Rotate around X axis
    final cosX = math.cos(rotationX);
    final sinX = math.sin(rotationX);
    final y1 = v.y * cosX - v.z * sinX;
    final z1 = v.y * sinX + v.z * cosX;

    // Rotate around Y axis
    final cosY = math.cos(rotationY);
    final sinY = math.sin(rotationY);
    final x2 = v.x * cosY + z1 * sinY;
    final z2 = -v.x * sinY + z1 * cosY;

    return Vertex(x: x2, y: y1, z: z2, r: v.r, g: v.g, b: v.b);
  }

  @override
  bool shouldRepaint(MeshPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.rotationX != rotationX ||
        oldDelegate.rotationY != rotationY ||
        oldDelegate.zoom != zoom ||
        oldDelegate.offsetX != offsetX ||
        oldDelegate.offsetY != offsetY ||
        oldDelegate.interactionMode != interactionMode;
  }
}

class RenderedMeshViewerScreen extends StatefulWidget {
  final String objPath;
  final String texturePath;

  const RenderedMeshViewerScreen({
    super.key,
    required this.objPath,
    required this.texturePath,
  });

  @override
  State<RenderedMeshViewerScreen> createState() => _RenderedMeshViewerScreenState();
}

class _RenderedMeshViewerScreenState extends State<RenderedMeshViewerScreen> {
  String? _error;
  bool _sceneReady = false;

  @override
  void initState() {
    super.initState();
    _validateFiles();
  }

  Future<void> _validateFiles() async {
    final objExists = await File(widget.objPath).exists();
    final texExists = await File(widget.texturePath).exists();

    if (!objExists) {
      setState(() {
        _error = 'OBJ file missing at ${widget.objPath}';
      });
      return;
    }

    if (!texExists) {
      // Not fatal for viewing, but useful context for user.
      setState(() {
        _error = 'Texture missing. Mesh can still render without texture.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendered Mesh Viewer'),
      ),
      body: Stack(
        children: [
          cube.Cube(
            onSceneCreated: (cube.Scene scene) {
              try {
                scene.camera.zoom = 10;
                scene.camera.position.setValues(0, 0, 10);

                final object = cube.Object(
                  fileName: widget.objPath,
                  isAsset: false,
                  scale: vmath.Vector3.all(1.0),
                  position: vmath.Vector3.zero(),
                  rotation: vmath.Vector3.zero(),
                );

                scene.world.add(object);

                if (mounted) {
                  setState(() {
                    _sceneReady = true;
                    if (_error != null && _error!.startsWith('Texture missing')) {
                      // keep non-fatal warning hidden after scene loads
                      _error = null;
                    }
                  });
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _error = 'Failed to load mesh: $e';
                  });
                }
              }
            },
          ),
          if (!_sceneReady && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

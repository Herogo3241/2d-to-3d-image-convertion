import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import 'utils/point_cloud_fusion.dart';
import 'point_cloud_viewer_screen.dart' show PointCloudPainter;
import 'utils/session_metadata.dart';


class MultiViewFusionScreen extends StatefulWidget {
  const MultiViewFusionScreen({super.key});

  @override
  State<MultiViewFusionScreen> createState() => _MultiViewFusionScreenState();
}

class _MultiViewFusionScreenState extends State<MultiViewFusionScreen> {
  List<Directory> _sessions = [];
  bool _loading = true;
  Directory? _selectedSession;
  List<Map<String, dynamic>> _captures = [];

  bool _fusing = false;
  String _status = '';
  final List<String> _log = [];
  List<Point3D>? _fusedCloud;

  double _rotationX = -0.5;
  double _rotationY = 0.0;
  double _zoom = 1.0;
  double _panX = 0.0;
  double _panY = 0.0;
  bool _useMidasDepth = true;
  bool _runIcp = true;
  int _activeViewFilter = -1;

  static const int _arDepthWidth = 160;
  static const int _arDepthHeight = 90;
  static const int _midasSize = 256;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  void log(String msg) => setState(() {
    _log.add(msg);
    _status = msg;
  });

  // ── Sessions ──────────────────────────────────────────────────────────────

  Future<void> _loadSessions() async {
    final appDir = await getApplicationDocumentsDirectory();
    final capturesDir = Directory('${appDir.path}/captures');
    if (await capturesDir.exists()) {
      final entities = capturesDir.listSync();
      _sessions = entities.whereType<Directory>().toList()
        ..sort((a, b) => b.path.compareTo(a.path));
    }
    setState(() => _loading = false);
  }

  Future<void> _loadCapturesFromSession(Directory session) async {
    final jsonFile = File('${session.path}/captures.json');
    if (!await jsonFile.exists()) return;

    final data = json.decode(await jsonFile.readAsString()) as List<dynamic>;
    final fixed = data.map((c) {
      final m = Map<String, dynamic>.from(c as Map);
      final imgName = m['imagePath']
          .toString()
          .split('/')
          .last
          .split('\\')
          .last;
      final depName = m['depthPath']
          .toString()
          .split('/')
          .last
          .split('\\')
          .last;
      m['imagePath'] = '${session.path}/$imgName';
      m['depthPath'] = '${session.path}/$depName';
      return m;
    }).toList();

    setState(() {
      _selectedSession = session;
      _captures = fixed;
      _fusedCloud = null;
      _log.clear();
      _status = '${fixed.length} captures loaded';
    });

    await _loadExistingFusedCloud();
  }

  // ── Per-view cloud generation ─────────────────────────────────────────────

  // Diagnostic mode: skip ALL filtering so you can see raw depth coverage.
  // Turn on from the fusion setup screen to find where points are being lost.
  bool _diagnosticMode = false;

  Future<List<Point3D>> _generateViewCloud(
    Map<String, dynamic> capture,
    int viewIndex,
  ) async {
    final imagePath = capture['imagePath'] as String;
    final depthPath = capture['depthPath'] as String;
    final sessionDir = _selectedSession!.path;

    final depthName = depthPath.split('/').last.split('\\').last;
    final frameNumber = depthName.replaceAll(RegExp(r'[^0-9]'), '');

    final midasPath = '$sessionDir/enhanced_depth_$frameNumber.raw';
    final nobgPath = _nobgPathFor(imagePath);
    final nobgExists = await File(nobgPath).exists();
    final arDepthExists = await File(depthPath).exists();

    log(
      '  View $viewIndex: rgb=${await File(imagePath).exists()} arDepth=$arDepthExists midas=${await File(midasPath).exists()} nobg=$nobgExists frameNum="$frameNumber"',
    );

    final midasExists = await File(midasPath).exists();
    final useMidas = _useMidasDepth && midasExists;
    if (!useMidas && !arDepthExists) {
      log('  View $viewIndex: NO DEPTH FILE — skipping');
      return [];
    }
    final actualDepthPath = useMidas ? midasPath : depthPath;

    final rgbImage = img.decodeImage(await File(imagePath).readAsBytes());
    if (rgbImage == null) {
      log('  View $viewIndex: failed to decode RGB');
      return [];
    }

    // Mask from _nobg.png — applied in RGB image space (not depth-grid space)
    // to avoid resolution mismatch. Auto-discarded if bg remover failed on
    // this angle (fg ratio < 4%).
    img.Image? maskImage;
    if (!_diagnosticMode && nobgExists) {
      maskImage = img.decodeImage(await File(nobgPath).readAsBytes());
      if (maskImage != null) {
        int fgCount = 0;
        final sampleStep = 8;
        int sampleTotal = 0;
        for (int py = 0; py < maskImage.height; py += sampleStep) {
          for (int px = 0; px < maskImage.width; px += sampleStep) {
            if (maskImage.getPixel(px, py).a >= 5) fgCount++;
            sampleTotal++;
          }
        }
        final fgRatio = fgCount / sampleTotal;
        log('  View $viewIndex mask fg=${(fgRatio * 100).toStringAsFixed(1)}%');
        if (fgRatio < 0.04) {
          log('  View $viewIndex: mask almost empty — discarding mask');
          maskImage = null;
        }
      }
    }

    Uint16List depthData;
    int dw, dh;

    if (useMidas) {
      final bytes = await File(actualDepthPath).readAsBytes();
      if (bytes.length <= 8) {
        log('  View $viewIndex: MiDaS file too small');
        return [];
      }
      final header = ByteData.sublistView(bytes, 0, 8);
      final hw = header.getUint32(0, Endian.little);
      final hh = header.getUint32(4, Endian.little);
      if (hw > 0 &&
          hw <= 4096 &&
          hh > 0 &&
          hh <= 4096 &&
          bytes.length == 8 + hw * hh * 2) {
        dw = hw;
        dh = hh;
        depthData = bytes.buffer.asUint16List(8);
      } else {
        log('  View $viewIndex: MiDaS header invalid (${hw}x$hh) fallback raw');
        dw = _midasSize;
        dh = _midasSize;
        depthData = bytes.buffer.asUint16List();
      }
    } else {
      final bytes = await File(actualDepthPath).readAsBytes();
      dw = _arDepthWidth;
      dh = _arDepthHeight;
      depthData = bytes.buffer.asUint16List();
    }

    final nonZero = depthData.where((v) => v > 0).length;
    log(
      '  View $viewIndex depth: ${useMidas ? "MiDaS" : "ARCore"} ${dw}x$dh nonZero=$nonZero',
    );

    if (nonZero == 0) {
      log(
        '  View $viewIndex: ALL ZEROS — depth estimation may not have run for this frame',
      );
      return [];
    }

    double minD = double.infinity, maxD = 0;
    if (useMidas) {
      for (final v in depthData) {
        if (v > 0) {
          if (v < minD) minD = v.toDouble();
          if (v > maxD) maxD = v.toDouble();
        }
      }
    }

    final fovH = 60.0 * math.pi / 180.0;
    final fx = dw / (2.0 * math.tan(fovH / 2.0));
    final cx = dw / 2.0, cy = dh / 2.0;

    final points = <Point3D>[];
    int skippedZ = 0, skippedMask = 0;

    for (int y = 0; y < dh; y++) {
      for (int x = 0; x < dw; x++) {
        final idx = y * dw + x;
        if (idx >= depthData.length) continue;

        final dv = depthData[idx];
        if (dv == 0) continue;

        double z;
        if (useMidas) {
          // dv is now 0 (Far) to 65535 (Close)
          // Normalize to 0.0 - 1.0
          final norm = dv / 65535.0;

          // Convert disparity to metric-like distance
          // norm 1.0 (close) -> 0.5m
          // norm 0.0 (far)   -> 4.5m
          z = 0.5 + (1.0 - norm) * 4.0;
        } else {
          z = dv / 1000.0; // Standard ARCore metric
        }

        // Relax your Z-Filter to see the results
        if (z < 0.1 || z > 10.0) {
          skippedZ++;
          continue;
        }

        // 2. FIXED MASK COORDINATES
        if (maskImage != null) {
          // Map depth (dw/dh) directly to mask resolution
          final mx = (x * maskImage.width / dw).floor().clamp(
            0,
            maskImage.width - 1,
          );
          final my = (y * maskImage.height / dh).floor().clamp(
            0,
            maskImage.height - 1,
          );

          final pixel = maskImage.getPixel(mx, my);
          // Check if pixel is transparent or too dark (masking logic)
          if (pixel.a < 10) {
            skippedMask++;
            continue;
          }
        }

        final xPos = (x - cx) * z / fx;
        final yPos = (y - cy) * z / fx;

        // Map depth to RGB image
        final imgX = (x * rgbImage.width / dw).floor().clamp(
          0,
          rgbImage.width - 1,
        );
        final imgY = (y * rgbImage.height / dh).floor().clamp(
          0,
          rgbImage.height - 1,
        );
        final pixel = rgbImage.getPixel(imgX, imgY);

        points.add(
          Point3D(
            x: xPos,
            y: yPos,
            z: z,
            r: pixel.r.toInt(),
            g: pixel.g.toInt(),
            b: pixel.b.toInt(),
            viewIndex: viewIndex,
          ),
        );
      }
    }

    // CRITICAL: Remove the log from inside the loop!
    // Only log the final result for the view.
    log(
      'View $viewIndex Done: Total=${points.length} (MaskCut=$skippedMask, ZCut=$skippedZ)',
    );
    return points;
  }

  static String _nobgPathFor(String imagePath) {
    final file = File(imagePath);
    final dir = file.parent.path;
    final name = file.uri.pathSegments.last;
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    return '$dir/${stem}_nobg.png';
  }

  // ── Fusion pipeline ───────────────────────────────────────────────────────

  Future<void> _runFusion() async {
    if (_captures.isEmpty) return;
    setState(() {
      _fusing = true;
      _fusedCloud = null;
      _log.clear();
    });

    try {
      // Step 1: per-view clouds in camera space
      final viewClouds = <List<Point3D>>[];
      for (int i = 0; i < _captures.length; i++) {
        log('Generating cloud for view ${i + 1}/${_captures.length}...');
        final cloud = await _generateViewCloud(_captures[i], i);
        log('  → ${cloud.length} points');
        viewClouds.add(cloud);
      }

      // Step 2: attempt pose-based world transform, log result
      log('Attempting pose transforms...');
      final worldClouds = <List<Point3D>>[];
      int poseSuccessCount = 0;

      for (int i = 0; i < viewClouds.length; i++) {
        final pose = (_captures[i]['relativePose'] as List<dynamic>)
            .cast<double>();
        log(
          '  View $i: pose len=${pose.length}  '
          'first4=${pose.take(4).map((v) => v.toStringAsFixed(3)).toList()}',
        );

        final result = PointCloudFusion.transformToWorldFrame(
          viewClouds[i],
          pose,
        );
        if (result.usedPose) {
          poseSuccessCount++;
          log('  → pose applied');
        } else {
          log('  → pose unusable, using centroid alignment instead');
        }
        worldClouds.add(result.cloud);
      }

      log('Pose used for $poseSuccessCount/${worldClouds.length} views');

      // Step 3: ICP — only for views with enough points to align reliably.
      // Step 3: ICP
      List<List<Point3D>> aligned = [worldClouds[0]];
      List<Point3D> masterModel = List.from(worldClouds[0]);

      for (int i = 1; i < worldClouds.length; i++) {
        List<Point3D> currentView = worldClouds[i];
        if (currentView.isEmpty) continue;

        log('Aligning View $i (${currentView.length} pts)...');

        // MANDATORY Centroid Alignment before ICP
        final (scx, scy, scz) = PointCloudFusion.centroid(currentView);
        final (tcx, tcy, tcz) = PointCloudFusion.centroid(masterModel);
        currentView = PointCloudFusion.translateBy(
          currentView,
          tcx - scx,
          tcy - scy,
          tcz - scz,
        );

        // Only run ICP if we have enough points, otherwise stick with Centroid
        if (currentView.length > 100) {
          currentView = PointCloudFusion.icpRefine(
            currentView,
            masterModel,
            maxIterations: 40,
            maxDistance: 0.5, // Large distance to catch the sparse points
          );
        }

        aligned.add(currentView);
        // Keep the master model updated so View 2 aligns to View 0 + View 1
        masterModel = PointCloudFusion.mergeAndDeduplicate([
          masterModel,
          currentView,
        ], voxelSize: 0.01);
      }

      // Step 4: final merge + voxel deduplicate
      log('Final merge (voxel 1.5 cm)...');
      final merged = PointCloudFusion.mergeAndDeduplicate(
        aligned,
        voxelSize: 0.015,
      );
      log('  → ${merged.length} points');

      // Step 5: outlier removal — gentle settings so sparse views aren't wiped.
      // k=6 (smaller neighbourhood), multiplier=2.5 (only remove real outliers).
      log('Removing outliers...');
      final cleaned = PointCloudFusion.statisticalOutlierRemoval(
        merged,
        k: 6,
        stdDevMultiplier: 2.5,
      );
      log(
        '✓ Done: ${cleaned.length} pts from ${_captures.length} views (removed ${merged.length - cleaned.length})',
      );

      await _saveFusedCloud(cleaned);

      setState(() {
        _fusedCloud = cleaned;
        _fusing = false;
        _status = '${cleaned.length} pts  •  ${_captures.length} views fused';
      });
    } catch (e, st) {
      log('Error: $e');
      debugPrint('Fusion error: $e\n$st');
      setState(() => _fusing = false);
    }
  }

  Future<void> _saveFusedCloud(List<Point3D> cloud) async {
    if (_selectedSession == null) return;
    try {
      final data = cloud
          .map(
            (p) => {
              'x': p.x,
              'y': p.y,
              'z': p.z,
              'r': p.r,
              'g': p.g,
              'b': p.b,
              'v': p.viewIndex,
            },
          )
          .toList();
      await File(
        '${_selectedSession!.path}/fused_cloud.json',
      ).writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  Future<void> _loadExistingFusedCloud() async {
    if (_selectedSession == null) return;
    final file = File('${_selectedSession!.path}/fused_cloud.json');
    if (!await file.exists()) return;
    try {
      final data = json.decode(await file.readAsString()) as List<dynamic>;
      final cloud = data
          .map(
            (d) => Point3D(
              x: (d['x'] as num).toDouble(),
              y: (d['y'] as num).toDouble(),
              z: (d['z'] as num).toDouble(),
              r: d['r'] as int,
              g: d['g'] as int,
              b: d['b'] as int,
              viewIndex: (d['v'] as int?) ?? 0,
            ),
          )
          .toList();
      setState(() {
        _fusedCloud = cloud;
        _status = 'Loaded saved cloud: ${cloud.length} pts';
      });
    } catch (e) {
      debugPrint('Load error: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Point3D> get _displayCloud {
    if (_fusedCloud == null) return [];
    if (_activeViewFilter == -1) return _fusedCloud!;
    return _fusedCloud!.where((p) => p.viewIndex == _activeViewFilter).toList();
  }

  static const _viewColors = [
    Colors.cyan,
    Colors.orange,
    Colors.lime,
    Colors.pink,
    Colors.purple,
  ];

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Multi-View Fusion')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_selectedSession == null) return _buildSessionPicker();
    if (_fusing) return _buildFusingProgress();
    if (_fusedCloud == null) return _buildFusionSetup();
    return _buildViewer();
  }

  Widget _buildSessionPicker() {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Session to Fuse')),
      body: _sessions.isEmpty
          ? const Center(child: Text('No sessions found'))
          : ListView.builder(
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                return FutureBuilder<String>(
                  future: SessionMetadata.getSessionAlias(session),
                  builder: (context, snap) {
                    final name = snap.data ?? session.path.split('/').last;
                    return ListTile(
                      leading: const Icon(Icons.folder_open),
                      title: Text(name),
                      subtitle: Text(
                        session.path.split('/').last,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => _loadCapturesFromSession(session),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildFusionSetup() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-View Fusion'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            _selectedSession = null;
            _captures = [];
          }),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session: ${_selectedSession!.path.split('/').last}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('${_captures.length} captures ready for fusion'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: List.generate(_captures.length, (i) {
                        final pose =
                            (_captures[i]['relativePose'] as List<dynamic>);
                        return Chip(
                          label: Text('View $i  (${pose.length}D pose)'),
                          backgroundColor: _viewColors[i % _viewColors.length]
                              .withValues(alpha: 0.2),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Options',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Use MiDaS depth'),
              subtitle: const Text('Better quality if depth was estimated'),
              value: _useMidasDepth,
              onChanged: (v) => setState(() => _useMidasDepth = v),
            ),
            SwitchListTile(
              title: const Text('Run ICP refinement'),
              subtitle: const Text('Aligns views after centroid pre-alignment'),
              value: _runIcp,
              onChanged: (v) => setState(() => _runIcp = v),
            ),
            SwitchListTile(
              title: const Text('Diagnostic mode'),
              subtitle: const Text(
                'Skip ALL filters — see raw depth coverage per view',
              ),
              value: _diagnosticMode,
              onChanged: (v) => setState(() => _diagnosticMode = v),
            ),
            const SizedBox(height: 20),
            if (_status.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _status,
                  style: TextStyle(color: Colors.blue.shade900),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _runFusion,
                    icon: const Icon(Icons.merge_type),
                    label: const Text('Run Fusion'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _loadExistingFusedCloud,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Load Saved'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFusingProgress() {
    return Scaffold(
      appBar: AppBar(title: const Text('Fusing...')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 20),
            Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _log.length,
                  itemBuilder: (ctx, i) => Text(
                    _log[i],
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer() {
    final cloud = _displayCloud;
    return Scaffold(
      appBar: AppBar(
        title: Text('Fused  ${cloud.length} pts'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _fusedCloud = null),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Re-fuse',
            onPressed: _runFusion,
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _activeViewFilter == -1,
                  onSelected: (_) => setState(() => _activeViewFilter = -1),
                ),
                const SizedBox(width: 8),
                ...List.generate(
                  _captures.length,
                  (i) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('View $i'),
                      selected: _activeViewFilter == i,
                      selectedColor: _viewColors[i % _viewColors.length]
                          .withValues(alpha: 0.3),
                      onSelected: (_) => setState(() => _activeViewFilter = i),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.black87,
            child: Text(
              _status,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onScaleUpdate: (details) {
                setState(() {
                  if (details.scale != 1.0) {
                    _zoom = (_zoom * details.scale).clamp(0.1, 10.0);
                  }
                  if (details.pointerCount == 1) {
                    _rotationY += details.focalPointDelta.dx * 0.01;
                    _rotationX += details.focalPointDelta.dy * 0.01;
                  } else if (details.pointerCount == 2) {
                    _panX += details.focalPointDelta.dx / 100;
                    _panY += details.focalPointDelta.dy / 100;
                  }
                });
              },
              child: CustomPaint(
                painter: PointCloudPainter(
                  points: cloud,
                  rotationX: _rotationX,
                  rotationY: _rotationY,
                  zoom: _zoom,
                  offsetX: _panX * 100,
                  offsetY: _panY * 100,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white),
                      onPressed: () => setState(
                        () => _zoom = (_zoom * 1.2).clamp(0.1, 10.0),
                      ),
                    ),
                    const Text(
                      'Zoom',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove, color: Colors.white),
                      onPressed: () => setState(
                        () => _zoom = (_zoom / 1.2).clamp(0.1, 10.0),
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reset'),
                  onPressed: () => setState(() {
                    _rotationX = -0.5;
                    _rotationY = 0.0;
                    _zoom = 1.0;
                    _panX = _panY = 0.0;
                  }),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('Export PLY'),
                  onPressed: () => _exportPly(cloud),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPly(List<Point3D> cloud) async {
    if (_selectedSession == null) return;
    try {
      final buf = StringBuffer()
        ..writeln('ply')
        ..writeln('format ascii 1.0')
        ..writeln('element vertex ${cloud.length}')
        ..writeln('property float x')
        ..writeln('property float y')
        ..writeln('property float z')
        ..writeln('property uchar red')
        ..writeln('property uchar green')
        ..writeln('property uchar blue')
        ..writeln('end_header');
      for (final p in cloud) {
        buf.writeln(
          '${p.x.toStringAsFixed(5)} ${p.y.toStringAsFixed(5)} ${p.z.toStringAsFixed(5)} ${p.r} ${p.g} ${p.b}',
        );
      }
      await File(
        '${_selectedSession!.path}/fused_cloud.ply',
      ).writeAsString(buf.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exported to fused_cloud.ply')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:image/image.dart' as img;
import 'package:image_background_remover/image_background_remover.dart';

class ArCaptureScreen extends StatefulWidget {
  const ArCaptureScreen({super.key});

  @override
  State<ArCaptureScreen> createState() => _ArCaptureScreenState();
}

class _ArCaptureScreenState extends State<ArCaptureScreen> {
  static const String viewType = 'ar_view';
  static const MethodChannel _channel = MethodChannel('com.example.app/ar');

  String _status = 'Checking Permissions...';
  String? _imagePath;
  String? _depthPath;
  List<double>? _pose;
  bool _hasPermissions = false;
  final List<Map<String, dynamic>> _captures = [];
  Directory? _sessionDirectory;

  // Background removal queue state
  final List<String> _removalQueue = [];
  int _processingCount = 0;
  int _completedCount = 0;
  bool _isProcessingQueue = false;

  @override
  void initState() {
    super.initState();
    BackgroundRemover.instance.initializeOrt();
    _checkPermissions();
    _createSessionDirectory();
  }

  @override
  void dispose() {
    BackgroundRemover.instance.dispose();
    super.dispose();
  }

  Future<void> _createSessionDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final dir = Directory('${appDir.path}/captures/session_$timestamp');
    await dir.create(recursive: true);
    setState(() {
      _sessionDirectory = dir;
    });
  }

  Future<void> _checkPermissions() async {
    final cameraStatus = await Permission.camera.request();
    if (cameraStatus.isGranted) {
      setState(() {
        _hasPermissions = true;
        _status = 'Ready';
      });
    } else {
      setState(() {
        _status = 'Camera permission required';
      });
    }
  }

  // ── Background removal queue ──────────────────────────────────────────────

  void _enqueueBackgroundRemoval(String imagePath) {
    setState(() {
      _removalQueue.add(imagePath);
    });
    if (!_isProcessingQueue) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_removalQueue.isNotEmpty) {
      final imagePath = _removalQueue.removeAt(0);

      if (mounted) setState(() => _processingCount++);

      try {
        await _removeBackgroundSeparate(imagePath);
      } catch (e) {
        print('BG removal failed for $imagePath: $e');
      }

      if (mounted) {
        setState(() {
          _processingCount--;
          _completedCount++;
        });
      }

      await Future.delayed(Duration.zero);
    }

    _isProcessingQueue = false;

    if (mounted) {
      setState(() {
        _status = 'Ready  •  $_completedCount bg removed';
      });
    }
  }

  /// Reads the original JPEG at [imagePath], removes the background, and saves
  /// the result as a SEPARATE file: same name but with _nobg.png suffix.
  ///
  /// The original JPEG is NEVER modified — it is needed by depth estimation
  /// and fusion for accurate colour sampling and pixel alignment.
  ///
  /// Example:
  ///   input:  session_123/frame_001.jpg   ← kept intact
  ///   output: session_123/frame_001_nobg.png  ← new file, RGBA PNG
  Future<void> _removeBackgroundSeparate(String imagePath) async {
    final rawBytes = await File(imagePath).readAsBytes();
    final rawImage = img.decodeImage(rawBytes);
    if (rawImage == null) return;

    try {
      final pngBytes = Uint8List.fromList(img.encodePng(rawImage));
      final ui.Image? uiImage =
          await BackgroundRemover.instance.removeBg(pngBytes);

      if (uiImage != null) {
        final ByteData? byteData = await uiImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (byteData != null) {
          // Derive the _nobg path from the original path
          final nobgPath = _nobgPathFor(imagePath);
          await File(nobgPath).writeAsBytes(byteData.buffer.asUint8List());
          return;
        }
      }
    } catch (e) {
      print('Background removal error: $e');
    }
    // If anything failed, no file is written — original is always untouched.
  }

  /// Returns the sibling _nobg.png path for a given image path.
  /// e.g. /session/frame_001.jpg  →  /session/frame_001_nobg.png
  static String _nobgPathFor(String imagePath) {
    final file = File(imagePath);
    final dir = file.parent.path;
    final name = file.uri.pathSegments.last;
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    return '$dir/${stem}_nobg.png';
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _placeAnchor() async {
    try {
      final bool success = await _channel.invokeMethod('placeAnchor');
      setState(() {
        _status = success
            ? 'Anchor Placed'
            : 'Failed to place anchor (try moving phone)';
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Error: ${e.message}';
      });
    }
  }

  Future<void> _capture() async {
    if (_sessionDirectory == null) return;
    try {
      setState(() {
        _status = 'Capturing...';
      });

      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('captureFrame', {
        'dirPath': _sessionDirectory!.path,
        'aspectRatio': '1:1',
      });

      final imagePath = result['imagePath'] as String?;
      final depthPath = result['depthPath'] as String?;
      final poseList = result['relativePose'] as List<dynamic>?;
      final pose = poseList?.cast<double>();

      if (imagePath != null && depthPath != null && pose != null) {
        final captureData = {
          'imagePath': imagePath,
          'depthPath': depthPath,
          // nobgPath is derived at read-time via _nobgPathFor — no need to store it
          'relativePose': pose,
          'timestamp': DateTime.now().toIso8601String(),
        };
        _captures.add(captureData);
        await _saveCaptures();

        // Queue bg removal — writes _nobg.png alongside the original JPEG
        _enqueueBackgroundRemoval(imagePath);
      }

      setState(() {
        _imagePath = imagePath;
        _depthPath = depthPath;
        _pose = pose;
        _status =
            'Captured (${_captures.length} total)  •  queue: ${_removalQueue.length + _processingCount}';
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Capture Error: ${e.message}';
      });
    }
  }

  Future<void> _saveCaptures() async {
    if (_captures.isEmpty || _sessionDirectory == null) return;
    try {
      final file = File('${_sessionDirectory!.path}/captures.json');
      await file.writeAsString(jsonEncode(_captures));
    } catch (e) {
      print('Error saving captures: $e');
    }
  }

  // ── Queue status badge ────────────────────────────────────────────────────

  Widget _buildQueueBadge() {
    final pending = _removalQueue.length + _processingCount;
    if (pending == 0 && _completedCount == 0) return const SizedBox.shrink();

    final label = pending > 0
        ? 'Removing bg: $pending left...'
        : '✓ BG removed: $_completedCount';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: pending > 0
            ? Colors.orange.withValues(alpha: 0.85)
            : Colors.green.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending > 0) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermissions) {
      return Scaffold(
        appBar: AppBar(title: const Text('AR 3D Scanner')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_status),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _checkPermissions,
                child: const Text('Grant Permissions'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('AR 3D Scanner')),
      body: Stack(
        children: [
          AndroidView(
            viewType: viewType,
            creationParams: const <String, dynamic>{},
            creationParamsCodec: const StandardMessageCodec(),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: _buildQueueBadge(),
          ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black54,
                  child: Text(
                    _status,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_imagePath != null)
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      'RGB: ...${_imagePath!.substring(_imagePath!.length - 20)}\nDepth: ...${_depthPath!.substring(_depthPath!.length - 20)}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                if (_pose != null)
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      'Pose: ${_pose!.take(4).toList()}...',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _placeAnchor,
                      child: const Text('Place Anchor'),
                    ),
                    ElevatedButton(
                      onPressed: _capture,
                      child: const Text('Capture'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Center(
            child: Icon(Icons.add, color: Colors.white, size: 40),
          ),
        ],
      ),
    );
  }
}
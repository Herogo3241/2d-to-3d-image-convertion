import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

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

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _createSessionDirectory();
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

  Future<void> _placeAnchor() async {
    try {
      final bool success = await _channel.invokeMethod('placeAnchor');
      setState(() {
        _status = success ? 'Anchor Placed' : 'Failed to place anchor (try moving phone)';
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
      
      final Map<dynamic, dynamic> result = await _channel.invokeMethod('captureFrame', {
        'dirPath': _sessionDirectory!.path,
      });
      
      final imagePath = result['imagePath'] as String?;
      final depthPath = result['depthPath'] as String?;
      final poseList = result['relativePose'] as List<dynamic>?;
      final pose = poseList?.cast<double>();

      if (imagePath != null && depthPath != null && pose != null) {
        final captureData = {
          'imagePath': imagePath,
          'depthPath': depthPath,
          'relativePose': pose,
          'timestamp': DateTime.now().toIso8601String(),
        };
        _captures.add(captureData);
        await _saveCaptures();
      }

      setState(() {
        _imagePath = imagePath;
        _depthPath = depthPath;
        _pose = pose;
        _status = 'Capture Success (${_captures.length} saved)';
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
      print('Saved ${_captures.length} captures to ${file.path}');
    } catch (e) {
      print('Error saving captures: $e');
    }
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
          // Native AR View
          AndroidView(
            viewType: viewType,
            creationParams: const <String, dynamic>{},
            creationParamsCodec: const StandardMessageCodec(),
          ),
          
          // UI Overlay
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
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                if (_pose != null)
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      'Pose: ${_pose!.take(4).toList()}...',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
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
          
          // Crosshair
          const Center(
            child: Icon(Icons.add, color: Colors.white, size: 40),
          ),
        ],
      ),
    );
  }
}

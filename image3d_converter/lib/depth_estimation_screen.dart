import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:convert';
import 'utils/session_metadata.dart';

class DepthEstimationScreen extends StatefulWidget {
  const DepthEstimationScreen({super.key});

  @override
  State<DepthEstimationScreen> createState() => _DepthEstimationScreenState();
}

class _DepthEstimationScreenState extends State<DepthEstimationScreen> {
  List<Directory> _sessions = [];
  bool _loading = true;
  Directory? _selectedSession;
  List<Map<String, dynamic>> _captures = [];
  bool _processing = false;
  String? _statusMessage;
  Interpreter? _interpreter;
  int _currentIndex = 0;
  Uint8List? _depthMapImage;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadModel();
  }

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/midas_small.tflite');
      setState(() {
        _statusMessage = 'Model loaded successfully';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error loading model: $e\nPlease add midas_small.tflite to assets/models/';
      });
    }
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
        setState(() {}); // Refresh the list
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session name updated successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update name: $e')),
        );
      }
    }
  }

  Future<void> _deleteSession(Directory sessionDir) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: const Text('Are you sure you want to delete this session? This action cannot be undone.'),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  Future<void> _loadCapturesFromSession(Directory session) async {
    setState(() {
      _selectedSession = session;
      _captures = [];
      _currentIndex = 0;
      _depthMapImage = null;
    });

    final jsonFile = File('${session.path}/captures.json');
    if (await jsonFile.exists()) {
      final jsonContent = await jsonFile.readAsString();
      final List<dynamic> data = json.decode(jsonContent);
      
      // Reconstruct paths based on current session directory
      final fixedCaptures = data.map((capture) {
        final captureMap = Map<String, dynamic>.from(capture);
        
        // Extract just the filename from the stored paths
        final imageFilename = captureMap['imagePath'].toString().split('/').last.split('\\').last;
        final depthFilename = captureMap['depthPath'].toString().split('/').last.split('\\').last;
        
        // Reconstruct full paths based on current session directory
        captureMap['imagePath'] = '${session.path}/$imageFilename';
        captureMap['depthPath'] = '${session.path}/$depthFilename';
        
        return captureMap;
      }).toList();
      
      setState(() {
        _captures = fixedCaptures;
      });
    }
  }

  Future<Uint8List> _runDepthEstimation(String imagePath) async {
    if (_interpreter == null) {
      throw Exception('Model not loaded');
    }

    // Load and preprocess image
    final imageFile = File(imagePath);
    final imageBytes = await imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes);
    
    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Resize to model input size (256x256 for MiDaS Small)
    final resized = img.copyResize(image, width: 256, height: 256);
    
    // Convert to float32 and normalize to [0, 1]
    final input = List.generate(
      1,
      (_) => List.generate(
        256,
        (y) => List.generate(
          256,
          (x) => List.generate(3, (c) {
            final pixel = resized.getPixel(x, y);
            if (c == 0) return pixel.r / 255.0;
            if (c == 1) return pixel.g / 255.0;
            return pixel.b / 255.0;
          }),
        ),
      ),
    );

    // Prepare output buffer [1, 256, 256, 1]
    final output = List.generate(
      1,
      (_) => List.generate(
        256,
        (_) => List.generate(256, (_) => List.filled(1, 0.0)),
      ),
    );

    // Run inference
    _interpreter!.run(input, output);

    // Post-process: normalize depth values to [0, 255] for visualization
    // Extract values from [1, 256, 256, 1] to flat list
    double minVal = output[0][0][0][0];
    double maxVal = output[0][0][0][0];
    
    for (int y = 0; y < 256; y++) {
      for (int x = 0; x < 256; x++) {
        final val = output[0][y][x][0];
        if (val < minVal) minVal = val;
        if (val > maxVal) maxVal = val;
      }
    }

    final range = maxVal - minVal;
    
    // Create grayscale depth image at native 256x256 resolution
    // Do NOT resize - preserving native MiDaS resolution prevents interpolation artifacts
    final depthImage = img.Image(width: 256, height: 256);
    for (int y = 0; y < 256; y++) {
      for (int x = 0; x < 256; x++) {
        final normalized = ((output[0][y][x][0] - minVal) / range * 255).toInt();
        final pixel = img.ColorUint8.rgb(normalized, normalized, normalized);
        depthImage.setPixel(x, y, pixel);
      }
    }
    
    return Uint8List.fromList(img.encodePng(depthImage));
  }

  Future<void> _processCurrentImage() async {
    if (_captures.isEmpty || _currentIndex >= _captures.length) return;

    setState(() {
      _processing = true;
      _statusMessage = 'Processing image ${_currentIndex + 1}/${_captures.length}...';
    });

    try {
      final capture = _captures[_currentIndex];
      final imagePath = capture['imagePath'];
      
      final depthBytes = await _runDepthEstimation(imagePath);
      
      // Save enhanced depth map as binary file
      final depthFilename = capture['depthPath'].split('/').last;
      final frameNumber = depthFilename.replaceAll(RegExp(r'[^0-9]'), '');
      final sessionDir = _selectedSession!.path;
      final enhancedDepthPath = '$sessionDir/enhanced_depth_$frameNumber.raw';
      
      // Convert PNG back to 16-bit depth data for 3D viewer
      // Depth is at native MiDaS resolution (256x256) - NOT resized
      final depthImage = img.decodeImage(depthBytes);
      if (depthImage != null) {
        final depthWidth = depthImage.width;   // Should be 256
        final depthHeight = depthImage.height; // Should be 256
        
        // MiDaS outputs inverse depth: brighter pixels = closer objects
        // Save directly without inversion: higher uint16 = closer
        final depthData = Uint16List(depthWidth * depthHeight);
        for (int i = 0; i < depthData.length; i++) {
          final pixel = depthImage.getPixel(i % depthWidth, i ~/ depthWidth);
          // Preserve MiDaS semantics: brightness (0-255) -> depth value (0-65535)
          // Higher value = closer object
          depthData[i] = (pixel.r.toInt() * 256);
        }
        
        // Save as binary file with header containing dimensions
        // Format: [width:4 bytes][height:4 bytes][depth data:width*height*2 bytes]
        final headerBuffer = ByteData(8);
        headerBuffer.setUint32(0, depthWidth, Endian.little);
        headerBuffer.setUint32(4, depthHeight, Endian.little);
        
        final file = File(enhancedDepthPath);
        final outputBytes = Uint8List(8 + depthData.length * 2);
        outputBytes.setRange(0, 8, headerBuffer.buffer.asUint8List());
        outputBytes.setRange(8, outputBytes.length, depthData.buffer.asUint8List());
        await file.writeAsBytes(outputBytes);
      }
      
      setState(() {
        _depthMapImage = depthBytes;
        _processing = false;
        _statusMessage = 'Depth estimation complete for image ${_currentIndex + 1}\nSaved to: enhanced_depth_$frameNumber.raw';
      });
    } catch (e) {
      setState(() {
        _processing = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Depth Estimation')),
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
        title: Text('Depth Estimation (${_currentIndex + 1}/${_captures.length})'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _selectedSession = null;
              _captures = [];
              _currentIndex = 0;
              _depthMapImage = null;
            });
          },
        ),
      ),
      body: _captures.isEmpty
          ? const Center(child: Text('No captures in this session'))
          : Column(
              children: [
                if (_statusMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: _statusMessage!.contains('Error')
                        ? Colors.red.shade100
                        : Colors.blue.shade100,
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(
                        color: _statusMessage!.contains('Error')
                            ? Colors.red.shade900
                            : Colors.blue.shade900,
                      ),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        const Text(
                          'Original Image',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Image.file(
                          File(_captures[_currentIndex]['imagePath']),
                          height: 300,
                        ),
                        const SizedBox(height: 16),
                        if (_depthMapImage != null) ...[
                          const Text(
                            'Depth Map (MiDaS)',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Image.memory(
                            _depthMapImage!,
                            height: 300,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Lighter = Closer, Darker = Farther',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  ),
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
                                  _depthMapImage = null;
                                });
                              }
                            : null,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Previous'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _processing ? null : _processCurrentImage,
                        icon: _processing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: const Text('Estimate Depth'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _currentIndex < _captures.length - 1
                            ? () {
                                setState(() {
                                  _currentIndex++;
                                  _depthMapImage = null;
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

// lib/native_mesh.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class NativeMeshApi {
  static const MethodChannel _channel = MethodChannel('native_mesh_channel');

  /// Calls platform channel to generate mesh on native side.
  /// depth: Float32List (W*H floats) - will be sent as bytes
  /// rgba: Uint8List (W*H*4 bytes)
  static Future<Map<String, dynamic>> generateMesh({
    required Float32List depth,
    required Uint8List rgba,
    required int width,
    required int height,
  }) async {
    // send depth as raw bytes (Float32 as bytes) and rgba bytes
    final result = await _channel.invokeMethod('generateMesh', {
      'depth': depth.buffer.asUint8List(),
      'image': rgba,
      'width': width,
      'height': height,
    });

    // result maps to lists from platform (List<dynamic>)
    final List<dynamic> vList = result['vertices'] ?? <dynamic>[];
    final List<dynamic> cList = result['colors'] ?? <dynamic>[];
    final List<dynamic> iList = result['indices'] ?? <dynamic>[];

    // Convert to typed lists
    final Float32List vertices = Float32List(vList.length);
    for (int i = 0; i < vList.length; i++) {
      vertices[i] = (vList[i] as num).toDouble();
    }

    final Float32List colors = Float32List(cList.length);
    for (int i = 0; i < cList.length; i++) {
      colors[i] = (cList[i] as num).toDouble();
    }

    final Int32List indices = Int32List(iList.length);
    for (int i = 0; i < iList.length; i++) {
      indices[i] = (iList[i] as num).toInt();
    }

    return {
      'vertices': vertices,
      'colors': colors,
      'indices': indices,
    };
  }
}

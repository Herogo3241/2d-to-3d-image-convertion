import 'package:flutter/material.dart';
import '../../ar_capture_screen.dart';

/// AR Capture Module
/// Handles camera-based AR scanning and data capture
class ARCaptureModule {
  static const String moduleName = 'AR Capture';
  static const String moduleDescription = 'Scan objects using AR camera and depth sensors';
  static const IconData moduleIcon = Icons.camera_alt;
  
  /// Navigate to AR capture screen
  static void launch(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ArCaptureScreen(),
      ),
    );
  }
  
  /// Check if module is available (check permissions, hardware support)
  static Future<bool> isAvailable() async {
    // TODO: Add actual hardware/permission checks
    return true;
  }
}

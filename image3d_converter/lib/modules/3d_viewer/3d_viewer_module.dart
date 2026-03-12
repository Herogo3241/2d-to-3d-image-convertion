import 'package:flutter/material.dart';
import '../../point_cloud_viewer_screen.dart';

/// 3D Viewer Module
/// Handles 3D reconstruction and visualization
class ThreeDViewerModule {
  static const String moduleName = '3D Viewer';
  static const String moduleDescription = 'View and interact with 3D reconstructions';
  static const IconData moduleIcon = Icons.view_in_ar;
  
  /// Navigate to 3D viewer screen
  static void launch(BuildContext context, {String? sessionPath}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PointCloudViewerScreen(),
      ),
    );
  }
  
  /// Check if 3D viewer is available
  static bool isAvailable() => true;
}

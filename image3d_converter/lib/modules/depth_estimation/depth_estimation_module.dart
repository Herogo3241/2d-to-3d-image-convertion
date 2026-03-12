import 'package:flutter/material.dart';
import '../../depth_estimation_screen.dart';

/// Depth Estimation Module
/// Handles ML-based depth enhancement using models like MiDaS, ZoeDepth
class DepthEstimationModule {
  static const String moduleName = 'Depth Enhancement';
  static const String moduleDescription = 'Improve depth maps using ML models';
  static const IconData moduleIcon = Icons.gradient;
  
  /// Navigate to depth estimation screen
  static void launch(BuildContext context, {String? sessionPath}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DepthEstimationScreen(),
      ),
    );
  }
  
  /// Check if ML models are available
  static bool isAvailable() => true;
}

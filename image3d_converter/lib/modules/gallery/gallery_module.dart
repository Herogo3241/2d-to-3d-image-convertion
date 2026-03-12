import 'package:flutter/material.dart';

/// Gallery Module
/// Handles session management and data export
class GalleryModule {
  static const String moduleName = 'Gallery';
  static const String moduleDescription = 'Browse and manage captured sessions';
  static const IconData moduleIcon = Icons.photo_library;
  
  /// Navigate to gallery screen
  static void launch(BuildContext context) {
    // Gallery screen is imported separately to avoid circular dependencies
    throw UnimplementedError('Use GalleryScreen directly from main.dart');
  }
  
  /// Get all available sessions
  static Future<List<SessionInfo>> getSessions() async {
    // TODO: Implement session listing
    throw UnimplementedError('Session listing not yet implemented');
  }
  
  /// Export a session
  static Future<String> exportSession(String sessionPath) async {
    // TODO: Implement export
    throw UnimplementedError('Export not yet implemented');
  }
}

/// Session information
class SessionInfo {
  final String path;
  final String name;
  final DateTime timestamp;
  final int imageCount;
  final int depthCount;
  
  SessionInfo({
    required this.path,
    required this.name,
    required this.timestamp,
    required this.imageCount,
    required this.depthCount,
  });
}

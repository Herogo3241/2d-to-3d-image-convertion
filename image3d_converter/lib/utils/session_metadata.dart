import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class SessionMetadata {
  static const String _metadataFileName = '.session_metadata.json';
  
  /// Get the display name (alias) for a session directory
  static Future<String> getSessionAlias(Directory sessionDir) async {
    final metadataFile = File('${sessionDir.path}/$_metadataFileName');
    
    if (await metadataFile.exists()) {
      try {
        final content = await metadataFile.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        if (data['alias'] != null && data['alias'].toString().isNotEmpty) {
          return data['alias'] as String;
        }
      } catch (e) {
        // If there's an error reading metadata, fall back to default name
      }
    }
    
    // Return default name based on folder name
    return _getDefaultDisplayName(sessionDir);
  }
  
  /// Set an alias for a session directory
  static Future<void> setSessionAlias(Directory sessionDir, String alias) async {
    final metadataFile = File('${sessionDir.path}/$_metadataFileName');
    
    final data = <String, dynamic>{
      'alias': alias.trim(),
      'created': DateTime.now().toIso8601String(),
      'originalName': sessionDir.path.split(Platform.pathSeparator).last,
    };
    
    await metadataFile.writeAsString(json.encode(data));
  }
  
  /// Get the default display name for a session (formatted timestamp)
  static String _getDefaultDisplayName(Directory sessionDir) {
    final folderName = sessionDir.path.split(Platform.pathSeparator).last;
    
    // If it starts with "session_", try to parse the timestamp
    if (folderName.startsWith('session_')) {
      final timestampStr = folderName.split('_').last;
      final timestamp = int.tryParse(timestampStr);
      if (timestamp != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        return 'Session: ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    }
    
    // Otherwise return the folder name as-is
    return folderName;
  }
  
  /// Delete the metadata file (optional cleanup)
  static Future<void> deleteMetadata(Directory sessionDir) async {
    final metadataFile = File('${sessionDir.path}/$_metadataFileName');
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
  }
  
  /// Get all sessions with their aliases
  static Future<Map<Directory, String>> getAllSessionsWithAliases() async {
    final appDir = await getApplicationDocumentsDirectory();
    final capturesDir = Directory('${appDir.path}/captures');
    final result = <Directory, String>{};
    
    if (await capturesDir.exists()) {
      final entities = capturesDir.listSync();
      final sessions = entities.whereType<Directory>().toList();
      
      for (var session in sessions) {
        final alias = await getSessionAlias(session);
        result[session] = alias;
      }
    }
    
    return result;
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'utils/session_metadata.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<Directory> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final appDir = await getApplicationDocumentsDirectory();
    final capturesDir = Directory('${appDir.path}/captures');
    if (await capturesDir.exists()) {
      final entities = capturesDir.listSync();
      _sessions = entities.whereType<Directory>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    }
    setState(() {
      _loading = false;
    });
  }

  Future<int> _countImagesInSession(Directory dir) async {
    try {
      if (!await dir.exists()) return 0;
      final files = dir.listSync().where((e) => e.path.endsWith('.jpg')).toList();
      return files.length;
    } catch (e) {
      return 0;
    }
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

  Future<void> _exportSession(Directory sessionDir) async {
    try {
      // Create zip in temp directory
      final tempDir = await getTemporaryDirectory();
      final sessionName = sessionDir.path.split(Platform.pathSeparator).last;
      final zipFile = File('${tempDir.path}/$sessionName.zip');
      
      if (await zipFile.exists()) {
        await zipFile.delete();
      }

      // Create the archive manually to ensure all files are included
      final archive = Archive();
      final files = sessionDir.listSync();
      
      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No files to export in this session')),
          );
        }
        return;
      }

      for (var file in files) {
        if (file is File) {
          final filename = file.path.split(Platform.pathSeparator).last;
          final bytes = await file.readAsBytes();
          final archiveFile = ArchiveFile(filename, bytes.length, bytes);
          archive.addFile(archiveFile);
        }
      }

      // Add README with instructions
      final readmeContent = '''
Session Export Data
===================

Files:
- *.jpg: RGB Images
- depth_*.bin: Raw Depth Maps (16-bit unsigned integer, millimeters)
- captures.json: Metadata including timestamps and pose matrices.

Pose Data:
The 'relativePose' in captures.json is a 4x4 transformation matrix (column-major) representing the Camera's position relative to the Anchor (Stick).

Depth Data:
The .bin files contain raw depth values. Each pixel is a 16-bit integer representing distance in millimeters.
Resolution depends on the device (e.g., 160x120 or 640x360).

Python Example to Read Data:
----------------------------
import json
import numpy as np
import os

with open('captures.json', 'r') as f:
    data = json.load(f)

for capture in data:
    # Pose
    pose = np.array(capture['relativePose']).reshape((4,4)).T
    print(f"Timestamp: {capture['timestamp']}")
    print("Pose:\\n", pose)
    
    # Depth
    depth_file = f"depth_{capture['timestamp']}.bin"
    if os.path.exists(depth_file):
        depth_data = np.fromfile(depth_file, dtype=np.uint16)
        print(f"Depth pixels: {len(depth_data)}")
''';
      archive.addFile(ArchiveFile('README.txt', readmeContent.length, readmeContent.codeUnits));

      // Encode the archive
      final encoder = ZipEncoder();
      final zipBytes = encoder.encode(archive);
      
      // Write to disk
      await zipFile.writeAsBytes(zipBytes);

      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(zipFile.path)], text: 'Export Session Data');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gallery')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(child: Text('No sessions found'))
              : ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final dir = _sessions[index];
                    final name = dir.path.split(Platform.pathSeparator).last;
                    final date = DateTime.fromMillisecondsSinceEpoch(
                        int.tryParse(name.split('_').last) ?? 0);
                    final formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(date);
                    
                    return FutureBuilder<String>(
                      future: SessionMetadata.getSessionAlias(dir),
                      builder: (context, aliasSnapshot) {
                        final displayName = aliasSnapshot.data ?? name;
                        
                        return ListTile(
                          title: Text(displayName),
                          subtitle: FutureBuilder<int>(
                            future: _countImagesInSession(dir),
                            builder: (context, snapshot) {
                              return Text('${snapshot.data ?? 0} images • $formattedDate');
                            },
                          ),
                          trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _renameSession(dir),
                            tooltip: 'Rename',
                          ),
                          IconButton(
                            icon: const Icon(Icons.share),
                            onPressed: () => _exportSession(dir),
                            tooltip: 'Export',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteSession(dir),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SessionDetailScreen(sessionDir: dir),
                          ),
                        );
                      },
                    );
                      },
                    );
                  },
                ),
    );
  }
}

class SessionDetailScreen extends StatelessWidget {
  final Directory sessionDir;

  const SessionDetailScreen({super.key, required this.sessionDir});

  @override
  Widget build(BuildContext context) {
    List<File> files = [];
    try {
      files = sessionDir.listSync()
          .where((e) => e.path.endsWith('.jpg'))
          .cast<File>()
          .toList();
    } catch (e) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session Images')),
        body: Center(
          child: Text('Error loading images: $e'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Session Images')),
      body: files.isEmpty
          ? const Center(child: Text('No images found in this session'))
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: files.length,
              itemBuilder: (context, index) {
                return Image.file(
                  files[index],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image),
                    );
                  },
                );
              },
            ),
    );
  }
}

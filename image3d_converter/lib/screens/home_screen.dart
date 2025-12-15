import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image3d_converter/screens/depth_screen.dart';
import 'package:image3d_converter/screens/mesh_viewer_screen.dart';
import 'package:image3d_converter/services/native_mesh.dart';
import 'package:image_picker/image_picker.dart';

class HomeScreen extends StatefulWidget {
  final Function(Uint8List) onImageSelected;
  final Uint8List? depthPreview;
  final List<List<double>>? depthData;
  final Uint8List? rgbaImage;

  const HomeScreen({
    super.key,
    required this.onImageSelected,
    required this.depthPreview,
    required this.depthData,
    required this.rgbaImage,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Uint8List? selectedImage;

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => selectedImage = bytes);
    widget.onImageSelected(bytes);
  }

  Future<void> createMesh() async {
    if (widget.depthData == null || widget.rgbaImage == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Depth or image not ready")));
      return;
    }

    // depth as 2D list
    final depth2D = widget.depthData!;
    final rgbaBytes = widget.rgbaImage!;

    final int height = depth2D.length;
    final int width = depth2D[0].length;

    // Flatten depth into Float32List
    final Float32List depthFloats = Float32List(width * height);
    int i = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        depthFloats[i++] = depth2D[y][x].toDouble();
      }
    }

    // show progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {

      final meshData = await NativeMeshApi.generateMesh(
        depth: depthFloats,
        rgba: rgbaBytes,
        width: width,
        height: height,
      );

      final vertices = meshData['vertices'] as Float32List;
      final colors = meshData['colors'] as Float32List;
      final indices = meshData['indices'] as Int32List;

      Navigator.push(context, MaterialPageRoute(builder: (context) => MeshViewer(vertices: vertices, colors: colors, indices: indices)));

    } catch (e) {
      Navigator.of(context).pop(); // close progress
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Mesh generation failed: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = selectedImage != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text("2D → 3D Image Converter"),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepPurple, width: 1),
                ),
                child: selectedImage == null
                    ? const Center(
                        child: Text(
                          "No Image Selected",
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(selectedImage!, fit: BoxFit.cover),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: pickImage,
                icon: const Icon(Icons.photo_library),
                label: const Text("Pick Image", style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: hasImage
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              DepthScreen(widget.depthPreview!),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.threed_rotation),
                label: const Text("Preview Depth Map"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  disabledBackgroundColor: Colors.teal.withAlpha(102),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: hasImage
                    ? createMesh
                    : null,
                icon: const Icon(Icons.threed_rotation),
                label: const Text("3D image generation"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  disabledBackgroundColor: Colors.teal.withAlpha(102),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ), 
          ],
        ),
      ),
      backgroundColor: Colors.black,
    );
  }
}

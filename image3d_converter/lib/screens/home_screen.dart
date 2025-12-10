import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../screens/depth_screen.dart'; // <-- IMPORT THIS

class HomeScreen extends StatefulWidget {
  final Function(Uint8List) onImageSelected;
  final Uint8List? depthPreview;

  const HomeScreen({
    super.key,
    required this.onImageSelected,
    required this.depthPreview,
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

  void openDepthScreen() {
    if (widget.depthPreview == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DepthScreen(widget.depthPreview!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            // Image Preview
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

            // Pick Image button
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

            // Generate Depth button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: selectedImage == null ? null : openDepthScreen,
                icon: const Icon(Icons.threed_rotation),
                label: const Text("Generate 3D View (Depth Preview)"),
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

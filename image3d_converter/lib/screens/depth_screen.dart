import 'dart:typed_data';
import 'package:flutter/material.dart';

class DepthScreen extends StatelessWidget {
  final Uint8List depthImage;

  const DepthScreen(this.depthImage, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Depth Map Preview"),
        backgroundColor: Colors.deepPurple,
      ),
      body: Center(
        child: Image.memory(depthImage),
      ),
      backgroundColor: Colors.black,
    );
  }
}

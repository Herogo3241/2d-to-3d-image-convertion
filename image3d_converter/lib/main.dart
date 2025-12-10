import 'dart:typed_data';
import 'package:flutter/material.dart';
// import 'package:image3d_converter/screens/depth_screen.dart';
import 'package:image3d_converter/screens/home_screen.dart';
import 'package:image3d_converter/services/depth_service.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final DepthEstimator estimator = DepthEstimator();
  Uint8List? depthPreview;

  @override
  void initState() {
    super.initState();
    estimator.loadModel();
  }

  Future<void> handleImageSelected(Uint8List bytes) async {
    print("Running MiDaS...");

    final depth = await estimator.runDepth(bytes);
    final preview = estimator.depthToImage(depth);

    setState(() => depthPreview = preview);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: HomeScreen(
        onImageSelected: handleImageSelected,
        depthPreview: depthPreview,
      ),
    );
  }
}

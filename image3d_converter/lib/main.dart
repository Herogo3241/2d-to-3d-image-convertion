import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'services/depth_service.dart'; 
import 'package:image/image.dart' as img;
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  List<List<double>>? depthData;
  Uint8List? rgbaImage;
  Uint8List? selectedImageBytes;

  @override
  void initState() {
    super.initState();
    estimator.loadModel();
  }

  // Called when HomeScreen picks an image
  Future<void> handleImageSelected(Uint8List bytes) async {
    selectedImageBytes = bytes;
    // Run depth model (MiDaS)
    final depth = await estimator.runDepth(bytes);
    depthData = depth;
    depthPreview = estimator.depthToImage(depth);

    // Convert original bytes to RGBA bytes with the same size as model input
    // We will convert to model input size (estimator.inputSize)
    rgbaImage = convertToRGBA(bytes, estimator.inputSize, estimator.inputSize);

    setState(() {});
  }

  // Convert arbitrary image bytes to RGBA bytes of given width/height (row-major, 4 channels)
  Uint8List convertToRGBA(Uint8List imageBytes, int outW, int outH) {
    final img.Image? image = img.decodeImage(imageBytes);
    if (image == null) {
      throw Exception("Failed to decode image for RGBA conversion");
    }

    final img.Image resized = img.copyResize(image, width: outW, height: outH);
    final Uint8List out = Uint8List(outW * outH * 4);
    int p = 0;
    for (int y = 0; y < outH; y++) {
      for (int x = 0; x < outW; x++) {
        final pixel = resized.getPixelSafe(x, y);
        out[p++] = pixel.r.toInt();   // red
        out[p++] = pixel.g.toInt(); // green
        out[p++] = pixel.b.toInt();  // blue
        out[p++] = pixel.a.toInt(); // alpha
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '2D → 3D',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: HomeScreen(
        onImageSelected: handleImageSelected,
        depthPreview: depthPreview,
        depthData: depthData,
        rgbaImage: rgbaImage,
      ),
    );
  }
}

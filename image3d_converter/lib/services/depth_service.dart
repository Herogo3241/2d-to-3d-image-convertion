import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class DepthEstimator {
  late Interpreter interpreter;
  final int inputSize = 256;

  Future<void> loadModel() async {
    interpreter = await Interpreter.fromAsset(
      'assets/model/MiDaS.tflite', // path as declared in pubspec (no leading 'assets/')
      options: InterpreterOptions()..threads = 2,
    );

    if (kDebugMode) {
      print("Model Loaded!");
      print("Input shape: ${interpreter.getInputTensor(0).shape}");
      print("Output shape: ${interpreter.getOutputTensor(0).shape}");
    }
  }

  Future<List<List<double>>> runDepth(Uint8List bytes) async {
    // Decode image and resize to model input size
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception("Failed to decode image bytes.");
    img.Image resized = img.copyResize(image, width: inputSize, height: inputSize);

    // Build input tensor as [1, H, W, 3] (NHWC)
    var input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (_) => List.generate(
          inputSize,
          (_) => List.filled(3, 0.0),
        ),
      ),
    );

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final p = resized.getPixelSafe(x, y);
        input[0][y][x][0] = p.r / 255.0;
        input[0][y][x][1] = p.g / 255.0;
        input[0][y][x][2] = p.b / 255.0;
      }
    }

    // Inspect output shape from the interpreter
    final outShape = interpreter.getOutputTensor(0).shape; // e.g. [1,256,256,1]

    // Build an output container that matches the exact shape
    late List output;
    if (outShape.length == 3) {
      // shape [1, H, W]
      output = List.generate(
        outShape[0],
        (_) => List.generate(outShape[1], (_) => List.filled(outShape[2], 0.0)),
      );
    } else if (outShape.length == 4) {
      // shape [1, H, W, C]  (C is usually 1)
      output = List.generate(
        outShape[0],
        (_) => List.generate(
          outShape[1],
          (_) => List.generate(
            outShape[2],
            (_) => List.filled(outShape[3], 0.0),
          ),
        ),
      );
    } else {
      // unexpected shape depth
      throw Exception("Unsupported output tensor shape: $outShape");
    }

    // Run inference
    interpreter.run(input, output);

    // Convert output to 2D depth map [H][W]
    final int H = outShape[1];
    final int W = outShape[2];
    List<List<double>> depth = List.generate(H, (y) => List.filled(W, 0.0));

    if (outShape.length == 3) {
      for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
          depth[y][x] = (output[0][y][x] as num).toDouble();
        }
      }
    } else {
      // outShape.length == 4 (e.g. [1,H,W,1])
      for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
          // channel 0
          depth[y][x] = (output[0][y][x][0] as num).toDouble();
        }
      }
    }

    return depth;
  }

  Uint8List depthToImage(List<List<double>> depth) {
    int h = depth.length;
    int w = depth[0].length;

    double minD = depth.expand((x) => x).reduce((a, b) => a < b ? a : b);
    double maxD = depth.expand((x) => x).reduce((a, b) => a > b ? a : b);
    // avoid division by zero
    if (maxD - minD < 1e-6) maxD = minD + 1e-6;

    final imgOut = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int v = (((depth[y][x] - minD) / (maxD - minD)) * 255).clamp(0,255).toInt();
        imgOut.setPixelRgb(x, y, v, v, v);
      }
    }

    return Uint8List.fromList(img.encodePng(imgOut));
  }
}

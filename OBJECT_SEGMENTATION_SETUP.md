# Object Segmentation for Point Cloud Filtering

## Overview
Use semantic segmentation to identify the main object and filter out background points from the 3D point cloud.

## Approach Options

### Option 1: DeepLab V3 (Recommended for Mobile)
- **Model**: DeepLab V3+ MobileNetV2
- **Size**: ~8 MB
- **Speed**: ~200-400ms on mobile
- **Output**: Pixel-wise segmentation mask
- **Classes**: 21 categories (PASCAL VOC) or 150 (ADE20K)

### Option 2: U-Net
- **Model**: Custom U-Net for foreground/background
- **Size**: ~5-15 MB (depending on architecture)
- **Speed**: ~100-300ms
- **Output**: Binary mask (foreground/background)

### Option 3: SAM (Segment Anything Model) - Advanced
- **Model**: SAM Mobile
- **Size**: ~40 MB
- **Speed**: ~1-2s on mobile
- **Quality**: State-of-the-art, but slower

## Step 1: Get Pre-trained Model

### DeepLab V3 TFLite
Download from TensorFlow Hub:
```bash
# Download DeepLab V3 model
wget https://tfhub.dev/tensorflow/lite-model/deeplabv3/1/metadata/2?lite-format=tflite -O deeplabv3.tflite

# Or use MobileNet V3 variant (smaller, faster)
wget https://storage.googleapis.com/download.tensorflow.org/models/tflite/gpu/deeplabv3_257_mv_gpu.tflite
```

### Alternative: U-Net for Binary Segmentation
If you want simpler foreground/background detection:

```python
# Train a custom U-Net (optional)
import tensorflow as tf

def unet_model(input_shape=(256, 256, 3)):
    inputs = tf.keras.layers.Input(shape=input_shape)
    
    # Encoder
    c1 = tf.keras.layers.Conv2D(64, (3, 3), activation='relu', padding='same')(inputs)
    p1 = tf.keras.layers.MaxPooling2D((2, 2))(c1)
    
    c2 = tf.keras.layers.Conv2D(128, (3, 3), activation='relu', padding='same')(p1)
    p2 = tf.keras.layers.MaxPooling2D((2, 2))(c2)
    
    # Bottleneck
    c3 = tf.keras.layers.Conv2D(256, (3, 3), activation='relu', padding='same')(p2)
    
    # Decoder
    u1 = tf.keras.layers.UpSampling2D((2, 2))(c3)
    u1 = tf.keras.layers.concatenate([u1, c2])
    c4 = tf.keras.layers.Conv2D(128, (3, 3), activation='relu', padding='same')(u1)
    
    u2 = tf.keras.layers.UpSampling2D((2, 2))(c4)
    u2 = tf.keras.layers.concatenate([u2, c1])
    c5 = tf.keras.layers.Conv2D(64, (3, 3), activation='relu', padding='same')(u2)
    
    outputs = tf.keras.layers.Conv2D(1, (1, 1), activation='sigmoid')(c5)
    
    return tf.keras.Model(inputs, outputs)

# Convert to TFLite
model = unet_model()
converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()
```

## Step 2: Integration Architecture

```dart
// lib/utils/object_segmentation.dart
class ObjectSegmentation {
  Interpreter? _interpreter;
  
  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/models/deeplabv3.tflite');
  }
  
  Future<Uint8List> segmentImage(String imagePath) async {
    // Load and preprocess image
    final imageFile = File(imagePath);
    final imageBytes = await imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes)!;
    
    // Resize to model input (257×257 for DeepLab)
    final resized = img.copyResize(image, width: 257, height: 257);
    
    // Normalize and prepare input tensor
    final input = _imageToByteListFloat32(resized);
    final output = List.filled(257 * 257, 0).reshape([1, 257, 257]);
    
    // Run inference
    _interpreter!.run(input, output);
    
    // Convert to binary mask (1 = object, 0 = background)
    final mask = _outputToMask(output, targetClass: 15); // 15 = person in PASCAL VOC
    
    // Resize mask back to original image size
    return mask;
  }
  
  Uint8List _outputToMask(List output, {int? targetClass}) {
    // Convert segmentation output to binary mask
    final mask = Uint8List(257 * 257);
    
    for (int i = 0; i < 257 * 257; i++) {
      if (targetClass != null) {
        // Filter specific class
        mask[i] = output[0][i ~/ 257][i % 257] == targetClass ? 255 : 0;
      } else {
        // Any foreground object
        mask[i] = output[0][i ~/ 257][i % 257] > 0 ? 255 : 0;
      }
    }
    
    return mask;
  }
}
```

## Step 3: Apply Mask to Point Cloud

```dart
// lib/point_cloud_viewer_screen.dart

Future<void> _generateFilteredPointCloud() async {
  // 1. Get segmentation mask
  final segmentation = ObjectSegmentation();
  await segmentation.loadModel();
  final mask = await segmentation.segmentImage(imagePath);
  
  // 2. Load depth data
  final depthData = await _loadDepthData(depthPath);
  
  // 3. Filter points using mask
  final points = <Point3D>[];
  
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final idx = y * width + x;
      
      // Skip if pixel is background (mask = 0)
      if (mask[idx] == 0) continue;
      
      // Only include points where mask = 255 (foreground)
      final depth = depthData[idx];
      if (depth > 100 && depth < 5000) {
        final point3d = _backprojectPixel(x, y, depth);
        points.add(point3d);
      }
    }
  }
  
  setState(() {
    _pointCloud = points;
    _statusMessage = '${points.length} filtered points';
  });
}
```

## Step 4: UI Enhancement

Add segmentation controls to the 3D viewer:

```dart
// Add to point_cloud_viewer_screen.dart UI
Column(
  children: [
    SwitchListTile(
      title: const Text('Enable Object Filtering'),
      value: _enableObjectFilter,
      onChanged: (value) {
        setState(() => _enableObjectFilter = value);
      },
    ),
    if (_enableObjectFilter)
      DropdownButton<String>(
        value: _targetClass,
        items: [
          DropdownMenuItem(value: 'auto', child: Text('Auto-detect main object')),
          DropdownMenuItem(value: 'person', child: Text('Person')),
          DropdownMenuItem(value: 'furniture', child: Text('Furniture')),
          DropdownMenuItem(value: 'foreground', child: Text('All foreground')),
        ],
        onChanged: (value) {
          setState(() => _targetClass = value!);
        },
      ),
  ],
)
```

## Step 5: Optimization Strategies

### Strategy 1: Center Object Detection (Simple)
Instead of full segmentation, detect the largest object in the center:

```dart
Uint8List _simpleCenterMask(int width, int height) {
  final mask = Uint8List(width * height);
  final centerX = width ~/ 2;
  final centerY = height ~/ 2;
  final radius = min(width, height) ~/ 3;
  
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final dx = x - centerX;
      final dy = y - centerY;
      final dist = sqrt(dx * dx + dy * dy);
      
      // Circular mask around center
      mask[y * width + x] = dist < radius ? 255 : 0;
    }
  }
  
  return mask;
}
```

### Strategy 2: Depth-Based Foreground Detection
Use depth values to separate foreground/background:

```dart
Uint8List _depthBasedMask(Uint16List depthData) {
  // Find median depth
  final sorted = List<int>.from(depthData)..sort();
  final medianDepth = sorted[sorted.length ~/ 2];
  
  // Create mask: closer than median = foreground
  final mask = Uint8List(depthData.length);
  for (int i = 0; i < depthData.length; i++) {
    mask[i] = depthData[i] < medianDepth ? 255 : 0;
  }
  
  return mask;
}
```

### Strategy 3: ARCore Plane Detection
Use ARCore's existing plane detection:

```kotlin
// In MainActivity.kt
fun getMainObjectMask(): ByteArray {
    val planes = session.getAllTrackables(Plane::class.java)
    // Find vertical planes (walls) and horizontal planes (floor/ceiling)
    // Return mask excluding these planes
}
```

## Step 6: Testing & Refinement

1. **Visual Debugging**: Show mask overlay on RGB image
2. **Tune Threshold**: Adjust segmentation confidence threshold
3. **Morphological Operations**: Apply erosion/dilation to clean mask
4. **Edge Refinement**: Use GrabCut for better object boundaries

## Recommended Implementation Order

1. ✅ **Start Simple**: Depth-based foreground detection (no ML)
2. ✅ **Add Center Mask**: Circular region of interest
3. ⏳ **Integrate DeepLab**: Full semantic segmentation
4. ⏳ **Add ZoeDepth**: Better depth + segmentation
5. ⏳ **Optimize**: Combine multiple cues (depth + segmentation + ARCore)

## Performance Tips

- Run segmentation once, cache mask for current image
- Use lower resolution for segmentation (128×128 or 192×192)
- Only re-segment when user changes image
- Consider running on device GPU if available

## Resources
- DeepLab V3: https://github.com/tensorflow/models/tree/master/research/deeplab
- TFLite Segmentation: https://www.tensorflow.org/lite/examples/segmentation/overview
- Mobile Segmentation Models: https://tfhub.dev/s?deployment-format=lite&module-type=image-segmentation

# Implementation Roadmap: ZoeDepth & Object Segmentation

## ✅ Phase 1: Depth-Based Object Filtering (COMPLETED)

**Status**: Implemented and ready to use!

**What's Available Now:**
- ✅ Automatic foreground detection (depth histogram)
- ✅ Center object focus
- ✅ Depth range filtering
- ✅ UI controls in 3D viewer
- ✅ Real-time filter statistics

**How to Use:**
1. Open 3D Viewer module
2. Select a session and image
3. Choose filter mode from dropdown:
   - **None**: All points (original behavior)
   - **Auto Foreground**: Automatically detects main object
   - **Center Object**: Focus on center of frame
   - **Depth Range**: Only points < 2 meters
4. Click "Generate Point Cloud"

**Files Added:**
- `app/lib/utils/point_cloud_filter.dart` - Filtering algorithms
- Updated `app/lib/point_cloud_viewer_screen.dart` - Integrated UI

---

## ⏳ Phase 2: ZoeDepth Integration (NEXT STEPS)

### Step 2.1: Model Acquisition (Your Action Required)

**Option A: Search for Pre-converted Model**
```bash
# Search TensorFlow Hub
https://tfhub.dev/
# Look for: "ZoeDepth", "metric depth", "NYU depth"
```

**Option B: Convert PyTorch Model** (Recommended if no TFLite available)
1. Clone ZoeDepth repo:
   ```bash
   git clone https://github.com/isl-org/ZoeDepth.git
   cd ZoeDepth
   pip install -r requirements.txt
   ```

2. Run conversion script (see `ZOEDEPTH_SETUP.md`)

3. Test model locally:
   ```python
   import numpy as np
   import tensorflow as tf
   
   interpreter = tf.lite.Interpreter(model_path="zoedepth.tflite")
   interpreter.allocate_tensors()
   
   # Test with dummy input
   input_details = interpreter.get_input_details()
   output_details = interpreter.get_output_details()
   
   print("Input shape:", input_details[0]['shape'])
   print("Output shape:", output_details[0]['shape'])
   ```

**Expected Model Specs:**
- Input: 384×512×3 (RGB, float32, normalized)
- Output: 384×512 (depth in meters, float32)
- Size: 90-150 MB (FP32), 40-80 MB (FP16)

### Step 2.2: Add Model to App

Once you have `zoedepth.tflite`:

1. Place in assets:
   ```
   app/assets/models/zoedepth_indoor.tflite
   ```

2. Update `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/models/midas_small.tflite
       - assets/models/zoedepth_indoor.tflite
   ```

3. Create inference wrapper:
   ```dart
   // app/lib/utils/zoedepth_inference.dart
   import 'package:tflite_flutter/tflite_flutter.dart';
   
   class ZoeDepthInference {
     Interpreter? _interpreter;
     
     Future<void> loadModel() async {
       _interpreter = await Interpreter.fromAsset(
         'assets/models/zoedepth_indoor.tflite'
       );
     }
     
     Future<Float32List> inferDepth(Uint8List imageBytes) async {
       // Implementation similar to MiDaS but returns metric depth
     }
   }
   ```

### Step 2.3: Integrate into Depth Estimation Screen

Add ZoeDepth as third option (alongside MiDaS):

```dart
// In depth_estimation_screen.dart
enum DepthModel { arcore, midas, zoedepth }

DepthModel _selectedModel = DepthModel.midas;

// UI dropdown
DropdownButton<DepthModel>(
  value: _selectedModel,
  items: [
    DropdownMenuItem(value: DepthModel.midas, child: Text('MiDaS (Relative)')),
    DropdownMenuItem(value: DepthModel.zoedepth, child: Text('ZoeDepth (Metric)')),
  ],
  onChanged: (value) => setState(() => _selectedModel = value!),
)
```

---

## ⏳ Phase 3: ML-Based Object Segmentation (FUTURE)

### Step 3.1: Get Segmentation Model

**Recommended: DeepLab V3 Mobile**
```bash
# Download pre-trained TFLite model
wget https://tfhub.dev/tensorflow/lite-model/deeplabv3/1/metadata/2?lite-format=tflite \
  -O deeplabv3_mobile.tflite
```

### Step 3.2: Implement Segmentation

```dart
// app/lib/utils/object_segmentation.dart
class ObjectSegmentation {
  Interpreter? _interpreter;
  
  Future<Uint8List> segmentImage(Uint8List imageBytes) async {
    // Load image
    // Run DeepLab inference
    // Return binary mask (255 = object, 0 = background)
  }
}
```

### Step 3.3: Combine with Depth Filtering

Update `point_cloud_filter.dart` to accept ML masks:

```dart
static Uint8List mlBasedMask(
  Uint8List segmentationMask,
  Uint16List depthData,
  int width,
  int height,
) {
  // Combine ML segmentation with depth filtering
  // More accurate than depth-only approach
}
```

---

## 📊 Current Status Summary

| Feature | Status | File | Notes |
|---------|--------|------|-------|
| MiDaS Depth | ✅ Working | `depth_estimation_screen.dart` | Relative depth |
| Depth Filtering | ✅ Working | `point_cloud_filter.dart` | 4 filter modes |
| 3D Viewer UI | ✅ Enhanced | `point_cloud_viewer_screen.dart` | Filter dropdown added |
| ZoeDepth | ⏳ Pending | N/A | Need model file |
| ML Segmentation | ⏳ Future | N/A | Optional enhancement |

---

## 🚀 Quick Start Guide

### Test Object Filtering Now:

1. **Run the app:**
   ```bash
   cd app
   flutter run
   ```

2. **Navigate to 3D Viewer**

3. **Try different filters:**
   - Start with "Auto Foreground" - works best for most scenes
   - Use "Center Object" if main object is centered
   - Use "Depth Range" for close-up objects

4. **Compare results:**
   - Generate with "None" filter
   - Generate with "Auto Foreground"
   - Notice how background clutter is removed

### Next Action Items:

**For ZoeDepth:**
1. ⏳ Obtain/convert ZoeDepth TFLite model
2. ⏳ Test model locally with Python
3. ⏳ Add to Flutter app assets
4. ⏳ Create inference wrapper
5. ⏳ Add UI toggle

**For ML Segmentation (Optional):**
1. ⏳ Download DeepLab V3 TFLite
2. ⏳ Test model locally
3. ⏳ Implement segmentation wrapper
4. ⏳ Integrate with filtering

---

## 💡 Pro Tips

### Performance Optimization:
- ZoeDepth is ~4-5x slower than MiDaS
- Consider running in Isolate for non-blocking UI
- Use FP16 quantization for smaller model size
- Cache depth maps to avoid re-computation

### Quality vs Speed:
- **Fast**: MiDaS + Depth filtering (current, ~300ms)
- **Balanced**: ZoeDepth + Depth filtering (~1000ms)
- **Best**: ZoeDepth + ML segmentation (~1500ms)

### Memory Management:
- Unload models when not in use
- Process one frame at a time
- Monitor RAM usage on device

---

## 📚 Documentation Reference

- `ZOEDEPTH_SETUP.md` - Detailed ZoeDepth guide
- `OBJECT_SEGMENTATION_SETUP.md` - ML segmentation guide
- `point_cloud_filter.dart` - Filtering API documentation

---

## ❓ FAQ

**Q: Why not use ZoeDepth immediately?**
A: Need to obtain/convert the model first. Not available as pre-built TFLite yet.

**Q: Is depth filtering enough without ML segmentation?**
A: Yes! For many use cases, depth-based filtering works well. ML segmentation is an enhancement.

**Q: Can I use both MiDaS and ZoeDepth?**
A: Yes! Keep both. MiDaS is faster, ZoeDepth is more accurate.

**Q: What if ZoeDepth conversion fails?**
A: Use ONNX Runtime instead of TFLite, or stick with MiDaS + filtering.

---

**Current Implementation**: ✅ Ready to use!
**Next Steps**: Obtain ZoeDepth model file
**Timeline**: Phase 2 depends on model availability

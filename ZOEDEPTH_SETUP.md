# ZoeDepth Integration Guide

## Overview
ZoeDepth provides **metric depth** (actual distances in meters) unlike MiDaS which gives relative depth. This is crucial for accurate 3D reconstruction.

## Step 1: Model Acquisition & Conversion

### Option A: Pre-converted TFLite Model (Recommended)
1. Check if ZoeDepth TFLite model is available on TensorFlow Hub:
   - Visit: https://tfhub.dev/
   - Search for "ZoeDepth" or "metric depth estimation"

2. If not available, you'll need to convert it yourself (see Option B)

### Option B: Convert PyTorch Model to TFLite
Since ZoeDepth is originally a PyTorch model, conversion is needed:

```bash
# 1. Clone ZoeDepth repository
git clone https://github.com/isl-org/ZoeDepth.git
cd ZoeDepth

# 2. Install dependencies
pip install torch torchvision
pip install timm
pip install -r requirements.txt

# 3. Download pretrained weights
# ZoeDepth-N (indoor): ~300MB
# ZoeDepth-K (outdoor): ~300MB
# ZoeDepth-NK (universal): ~300MB
```

**Conversion Script** (`convert_zoedepth_to_tflite.py`):
```python
import torch
import torch.nn as nn
import tensorflow as tf
from zoedepth.models.builder import build_model
from zoedepth.utils.config import get_config
import numpy as np

# Load ZoeDepth model
conf = get_config("zoedepth", "infer")
model = build_model(conf)
model.eval()

# Create dummy input
dummy_input = torch.randn(1, 3, 384, 512)  # ZoeDepth input size

# Trace the model
traced_model = torch.jit.trace(model, dummy_input)
traced_model.save("zoedepth_traced.pt")

# Convert to ONNX first
torch.onnx.export(
    model,
    dummy_input,
    "zoedepth.onnx",
    input_names=['input'],
    output_names=['output'],
    dynamic_axes={'input': {0: 'batch'}, 'output': {0: 'batch'}}
)

# Then use onnx-tensorflow to convert to TF
# pip install onnx-tf
from onnx_tf.backend import prepare
import onnx

onnx_model = onnx.load("zoedepth.onnx")
tf_rep = prepare(onnx_model)
tf_rep.export_graph("zoedepth_tf")

# Convert TF SavedModel to TFLite
converter = tf.lite.TFLiteConverter.from_saved_model("zoedepth_tf")
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]  # Use FP16 for smaller size
tflite_model = converter.convert()

with open("zoedepth.tflite", "wb") as f:
    f.write(tflite_model)

print("Model converted successfully!")
print(f"Model size: {len(tflite_model) / (1024*1024):.2f} MB")
```

### Option C: Use ONNX Runtime (Alternative)
If TFLite conversion is problematic, use ONNX with `onnxruntime_flutter` package:

```yaml
# pubspec.yaml
dependencies:
  onnxruntime: ^1.15.0
```

## Step 2: Model Integration

### Input/Output Specifications
**ZoeDepth Model:**
- **Input**: RGB image, size 384×512 (or 384×672), normalized [0,1]
- **Output**: Depth map, same resolution as input, values in meters
- **Range**: 0.1m to 10m (indoor), 0.1m to 100m (outdoor)

### File Structure
```
app/
  assets/
    models/
      midas_small.tflite          # Existing
      zoedepth_indoor.tflite      # New (90-150 MB)
      deeplabv3_segmentation.tflite  # For object detection (5-10 MB)
  lib/
    utils/
      session_metadata.dart
      zoedepth_inference.dart     # New
      object_segmentation.dart    # New
```

## Step 3: Add Models to Assets

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/models/midas_small.tflite
    - assets/models/zoedepth_indoor.tflite
    - assets/models/deeplabv3_segmentation.tflite
```

## Step 4: Performance Considerations

### Model Optimization
1. **Quantization**: Convert to INT8 for 4x size reduction
2. **Pruning**: Remove unnecessary weights
3. **Resolution**: Use 384×512 instead of 384×672 for speed

### Expected Performance
- **MiDaS Small**: ~200ms per frame, 256×256
- **ZoeDepth**: ~800-1500ms per frame, 384×512
- **Object Segmentation**: ~100-300ms per frame

### Optimization Strategy
```dart
// Run depth estimation in isolate for non-blocking UI
import 'dart:isolate';

Future<Uint8List> computeDepthInBackground(String imagePath) async {
  final receivePort = ReceivePort();
  await Isolate.spawn(_depthIsolate, receivePort.sendPort);
  // Process in background...
}
```

## Step 5: Testing Strategy

1. **Accuracy Test**: Compare depth values with ARCore ground truth
2. **Speed Test**: Measure inference time on target device
3. **Quality Test**: Visual inspection of 3D point clouds
4. **Memory Test**: Monitor RAM usage during inference

## Next Steps

After model setup:
1. Implement ZoeDepth inference wrapper (similar to MiDaS)
2. Add toggle in UI: ARCore / MiDaS / ZoeDepth
3. Implement object segmentation for point filtering
4. Test and optimize performance

## Alternative: Simplified Approach

If ZoeDepth is too complex, consider:
- **MiDaS v3.1**: Better than v2.1, still relative depth
- **DPT (Dense Prediction Transformer)**: Good accuracy, moderate size
- **Fast-Depth**: Lightweight, optimized for mobile

## Resources
- ZoeDepth Paper: https://arxiv.org/abs/2302.12288
- ZoeDepth GitHub: https://github.com/isl-org/ZoeDepth
- TFLite Conversion: https://www.tensorflow.org/lite/convert
- ONNX Runtime Flutter: https://pub.dev/packages/onnxruntime

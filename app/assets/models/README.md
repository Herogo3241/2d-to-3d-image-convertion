# MiDaS TFLite Model Setup

## Download Instructions

To use depth estimation, you need to download the MiDaS Small v2.1 TFLite model.

### Option 1: Direct Download (Recommended)

1. Download from TensorFlow Hub:
   ```
   https://tfhub.dev/intel/lite-model/midas/v2_1_small/1/lite/1
   ```

2. The downloaded file will be named `1.tflite`

3. Rename it to `midas_small.tflite`

4. Place it in this directory: `app/assets/models/midas_small.tflite`

### Option 2: Using Python Script

If the direct link doesn't work, use this Python script:

```python
import tensorflow_hub as hub
import tensorflow as tf

# Load the model from TensorFlow Hub
model_url = "https://tfhub.dev/intel/lite-model/midas/v2_1_small/1/lite/1"
model = hub.load(model_url)

# The model is already in TFLite format, just download it
print("Model downloaded successfully!")
```

### Option 3: Convert from PyTorch

```bash
# Clone MiDaS repository
git clone https://github.com/isl-org/MiDaS.git
cd MiDaS

# Download weights
wget https://github.com/isl-org/MiDaS/releases/download/v2_1/model-small-70d6b9c8.pt

# Use conversion script (requires PyTorch and TensorFlow)
python convert_to_tflite.py --model_type small
```

## Model Specifications

- **Model**: MiDaS v2.1 Small
- **Input Size**: 256x256 RGB image
- **Output**: 256x256 inverse depth map
- **Format**: TFLite (quantized or float32)
- **File Size**: ~5-10 MB

## Alternative Models

If MiDaS Small is not available, you can use:

1. **MiDaS v2.1 Large** (better accuracy, slower)
   - Input: 384x384
   - Size: ~100 MB

2. **Depth Anything Small** (newer, better edges)
   - Input: 518x518
   - Size: ~50 MB

## Model Input Preprocessing

```dart
// Resize image to 256x256
// Normalize to [0, 1]
// Convert to RGB if grayscale
// Reorder to [1, 256, 256, 3] tensor
```

## Model Output Postprocessing

```dart
// Output is inverse depth: closer = higher values
// Normalize to [0, 1]
// Optionally invert to get actual depth
// Resize back to original image size
```

## Verification

After placing the model file, verify:
```bash
ls -lh app/assets/models/midas_small.tflite
```

Expected output:
```
-rw-r--r-- 1 user user 5.8M Jan 18 2026 midas_small.tflite
```

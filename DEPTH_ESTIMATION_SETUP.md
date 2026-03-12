# Quick Setup Guide for Depth Estimation Module

## Current Status
✅ TensorFlow Lite dependencies installed
✅ Depth Estimation screen created
✅ 3D Point Cloud Viewer created
🔄 MiDaS model needs to be added

## Next Steps

### 1. Download MiDaS TFLite Model

You need to download the MiDaS Small TFLite model and place it in the assets folder.

**Option A: Direct Download (Easiest)**

Visit this URL in your browser:
```
https://tfhub.dev/intel/lite-model/midas/v2_1_small/1/lite/1
```

The file will download as `1.tflite` or similar. Rename it to `midas_small.tflite`.

**Option B: Using wget/curl**

```bash
cd c:\Users\ivinm\D-Drive\Repos\S8-Final-Project\app\assets\models
curl -L https://tfhub.dev/intel/lite-model/midas/v2_1_small/1/lite/1 -o midas_small.tflite
```

**Option C: Manual Download via Python**

```python
import urllib.request

url = "https://tfhub.dev/intel/lite-model/midas/v2_1_small/1/lite/1"
output_path = r"c:\Users\ivinm\D-Drive\Repos\S8-Final-Project\app\assets\models\midas_small.tflite"

print("Downloading MiDaS Small TFLite model...")
urllib.request.urlretrieve(url, output_path)
print(f"Model saved to: {output_path}")
```

### 2. Verify Installation

After placing the model, verify it's in the correct location:
```bash
ls c:\Users\ivinm\D-Drive\Repos\S8-Final-Project\app\assets\models\midas_small.tflite
```

Expected size: ~5-8 MB

### 3. Rebuild the App

After adding the model:
```bash
cd c:\Users\ivinm\D-Drive\Repos\S8-Final-Project\app
flutter run
```

## Features Available Now

### 1. Depth Estimation Module
- Select a captured session
- Navigate through captured images
- Click "Estimate Depth" to run MiDaS inference
- View side-by-side comparison of original image and depth map

### 2. 3D Point Cloud Viewer
- Select a captured session
- Click "Generate 3D" to create point cloud from depth + RGB
- Drag to rotate the 3D view
- Pinch to zoom in/out
- View colorized 3D point cloud

## How to Use

### Step 1: Capture Data
1. Open app → AR Capture module
2. Place anchor on a surface
3. Move around and capture multiple frames
4. Session is automatically saved

### Step 2: Test Depth Estimation
1. Go to Depth Estimation module
2. Select your captured session
3. Navigate to first image
4. Click "Estimate Depth"
5. Wait for processing (2-5 seconds per image)
6. View the generated depth map
7. Use Next/Previous to process other images

### Step 3: Visualize 3D
1. Go to 3D Viewer module
2. Select the same session
3. Navigate to an image
4. Click "Generate 3D"
5. The raw ARCore depth will be converted to a point cloud
6. Rotate and zoom to inspect the 3D reconstruction

## Expected Workflow

```
AR Capture → Depth Estimation → 3D Viewer
    ↓              ↓                ↓
Save RGB+     Enhance with      Visualize
Depth+Pose    MiDaS Model      Point Cloud
```

## Troubleshooting

### "Error loading model"
- Make sure `midas_small.tflite` is in `app/assets/models/`
- Rebuild the app after adding the model
- Check file size is around 5-8 MB

### "Failed to decode image"
- Make sure you captured images using AR Capture module
- Check that the session folder contains `.jpg` files

### "Point cloud is empty"
- Verify depth data exists (`.bin` files in session folder)
- Check that depth values are not all zero
- Try capturing on a textured surface (not plain walls)

### Performance Issues
- MiDaS inference takes 2-5 seconds per image on device
- Point cloud generation is instant
- For faster processing, use a smaller input size (currently 256x256)

## Model Information

**MiDaS Small v2.1**
- Input: 256x256 RGB image
- Output: 256x256 inverse depth map
- Quantization: Float32
- Runtime: 2-5 seconds on mobile CPU

**Why MiDaS?**
- Designed for mobile deployment
- Works on any image (no training data requirements)
- Provides relative depth (good for visualization)
- Small model size (~5 MB)

## Next Enhancements

Once basic depth estimation is working, you can:
1. Add batch processing (process all images at once)
2. Save enhanced depth maps alongside original ARCore depth
3. Implement mesh reconstruction (Poisson surface reconstruction)
4. Add texture mapping to mesh
5. Export to OBJ/PLY format
6. Compare MiDaS depth vs ARCore depth

# Depth Map Storage Format

## Overview
This document explains how MiDaS depth maps are generated, stored, and loaded for 3D point cloud visualization.

---

## Storage Pipeline

### 1. MiDaS Model Inference
**Location:** `depth_estimation_screen.dart` (lines 200-275)

- **Input:** RGB image resized to 256×256
- **Output:** Raw depth values in shape [1, 256, 256, 1]
- **Semantics:** MiDaS outputs **inverse depth** - higher raw values = closer objects

### 2. Visualization (PNG Export)
**Location:** `depth_estimation_screen.dart` (lines 262-274)

```dart
// Normalize raw output to 0-255 for visualization
final normalized = ((output[0][y][x][0] - minVal) / range * 255).toInt();
final pixel = img.ColorUint8.rgb(normalized, normalized, normalized);
```

- **Output:** Grayscale PNG image where **bright pixels = closer objects**
- **Purpose:** Visual feedback only (not used for 3D projection)

### 3. Binary Storage (.raw files)
**Location:** `depth_estimation_screen.dart` (lines 297-311)

```dart
// Preserve MiDaS semantics: brightness (0-255) -> depth value (0-65535)
// Higher value = closer object
depthData[i] = (pixel.r.toInt() * 256);
```

- **Storage Location:** `app_documents/captures/<session_name>/enhanced_depth_<frame_number>.raw`
- **Format:** Uint16 array (little-endian)
- **Dimensions:** Matches original image size (e.g., 1920×1080 → 1920×1080 pixels)
- **Value Range:** 0 to 65535
- **Semantics:** **Higher uint16 value = closer object**
- **File Size:** width × height × 2 bytes (e.g., 1920×1080 = 4.15 MB per frame)

---

## Loading Pipeline

### 1. File Read
**Location:** `point_cloud_viewer_screen.dart` (lines 225-240)

```dart
final depthBytes = await File(midasDepthPath).readAsBytes();
depthData = depthBytes.buffer.asUint16List();
depthWidth = 256;
depthHeight = 256;
```

- Reads raw binary file as Uint16List
- Each pixel becomes one uint16 value

### 2. Depth Range Analysis
**Location:** `point_cloud_viewer_screen.dart` (lines 245-253)

```dart
for (int i = 0; i < depthData.length; i++) {
  if (depthData[i] > 0) {
    if (d < minDepth) minDepth = d;
    if (d > maxDepth) maxDepth = d;
  }
}
```

- Finds min/max depth values in the current frame
- Used for normalization to metric scale

### 3. Depth to Z Conversion
**Location:** `point_cloud_viewer_screen.dart` (lines 280-286)

```dart
// Normalize to 0-1 (1 = closest)
final normalizedDepth = (depthValue - minDepth) / (maxDepth - minDepth);
// Convert to metric depth: high value -> small z (close), low value -> large z (far)
z = 3.0 - (normalizedDepth * 2.5); // Maps to 0.5m (close) to 3.0m (far)
```

- **normalizedDepth = 1.0** (high uint16, close object) → **z = 0.5m**
- **normalizedDepth = 0.0** (low uint16, far object) → **z = 3.0m**

---

## Key Consistency Rules

1. **Storage Format Invariant:**
   - Higher uint16 value = Closer object in real world
   - Lower uint16 value = Farther object in real world

2. **Z-Axis Convention:**
   - Smaller z value = Closer to camera (0.5m)
   - Larger z value = Farther from camera (3.0m)

3. **Transformation:**
   - High stored depth → Low z value (inverse relationship)
   - This matches standard 3D graphics convention

---

## Common Issues Fixed

### Double Inversion Bug (RESOLVED)
**Problem:** Previous code inverted depth twice:
1. During save: `(255 - brightness)` → inverted to "high = far"
2. During load: `(maxDepth - depthValue)` → inverted again to "high = close"
   - Result: Canceled out, causing wave patterns

**Solution:** 
- Save: Preserve MiDaS semantics directly (`brightness * 256`)
- Load: Single inversion during Z conversion (`z = 3.0 - normalized`)

### Wave Pattern Cause
- Occurred when depth values didn't match RGB pixel alignment
- Fixed by consistent depth interpretation throughout pipeline

---

## File Locations

- **MiDaS Model:** `assets/models/midas_small.tflite`
- **Saved Depths:** `<app_documents>/captures/<session>/enhanced_depth_<N>.raw`
- **Capture Metadata:** `<app_documents>/captures/<session>/captures.json`
- **Session Aliases:** `<app_documents>/captures/<session>/.session_metadata.json`

---

## Performance Notes

- **MiDaS Resolution:** 256×256 (fixed model input)
- **Storage Resolution:** Matches original RGB image (e.g., 1920×1080)
- **Point Cloud Sampling:** Every 2nd pixel for MiDaS (step=2) to reduce render load
- **File Size:** ~4MB per depth map at 1080p resolution

# AR 3D Scanner - Architecture

## Overview
The app follows a modular architecture where each major feature is an independent module. This allows for parallel development and easy maintenance.

## Module Structure

### 1. AR Capture Module (`lib/modules/ar_capture/`)
**Status:** ✅ Fully Functional
- **Purpose:** Capture RGB images, depth maps, and camera poses using ARCore
- **Key Features:**
  - Place anchor at center of screen
  - Capture frames with depth data
  - Save session data in JSON format
- **Files:**
  - `ar_capture_module.dart` - Module interface
  - `ar_capture_screen.dart` - UI implementation

### 2. Depth Estimation Module (`lib/modules/depth_estimation/`)
**Status:** 🔄 Coming Soon (Week 7)
- **Purpose:** Enhance captured depth maps using ML models
- **Planned Features:**
  - TensorFlow Lite integration
  - MiDaS/ZoeDepth model inference
  - Higher resolution depth maps
- **Files:**
  - `depth_estimation_module.dart` - Module interface with placeholder UI

### 3. 3D Viewer Module (`lib/modules/3d_viewer/`)
**Status:** 🔄 Coming Soon (Week 8)
- **Purpose:** Reconstruct and visualize 3D models from captured data
- **Planned Features:**
  - Point cloud generation
  - Mesh reconstruction (Poisson)
  - Texture mapping
  - Interactive 3D viewer
- **Files:**
  - `3d_viewer_module.dart` - Module interface with placeholder UI

### 4. Gallery Module (`lib/`)
**Status:** ✅ Fully Functional
- **Purpose:** Browse and manage captured sessions
- **Key Features:**
  - List all sessions with metadata
  - View individual captures
  - Export sessions as ZIP files
- **Files:**
  - `gallery_screen.dart` - UI implementation

## Navigation Flow

```
main.dart (HomeScreen)
    ├── AR Capture → ar_capture_screen.dart
    ├── Depth Estimation → Coming Soon placeholder
    ├── 3D Viewer → Coming Soon placeholder
    └── Gallery → gallery_screen.dart
```

## Data Flow

1. **Capture Phase:**
   - User places anchor in AR view
   - Camera pose is tracked relative to anchor
   - On capture: RGB image + Depth map + Pose matrix saved

2. **Storage:**
   - Session folder: `captures/session_<timestamp>/`
   - Files: `captures.json`, `frame_*.jpg`, `depth_*.raw`

3. **Enhancement Phase (Planned):**
   - Load captured RGB images
   - Run TensorFlow Lite inference for enhanced depth
   - Save enhanced depth maps

4. **Reconstruction Phase (Planned):**
   - Load RGB + Enhanced Depth + Poses
   - Generate point clouds
   - Apply Poisson reconstruction for mesh
   - Map textures onto mesh

## Technical Details

### RGB Capture Fix
The MainActivity.kt includes a color channel correction:
```kotlin
// glReadPixels returns RGBA, Android Bitmap expects ARGB
// Swap R and B channels
pixels[i] = (a shl 24) or (b shl 16) or (g shl 8) or r
```

### Depth Format
- Raw binary format: 16-bit unsigned integers
- Units: millimeters
- Resolution: 160×90 (ARCore standard)

### Pose Matrix
4×4 transformation matrix (column-major):
```
[R11, R21, R31, 0]
[R12, R22, R32, 0]
[R13, R23, R33, 0]
[Tx,  Ty,  Ty,  1]
```
Where:
- R = Rotation matrix (3×3)
- T = Translation vector

## Development Timeline

- **Week 6 (Current):** Module architecture ✅
- **Week 7:** TensorFlow Lite integration 🔄
- **Week 8:** 3D reconstruction algorithms 🔄
- **Week 9-10:** UI refinement and testing
- **Week 11-12:** Performance optimization
- **Week 13:** Final documentation

## Adding New Modules

1. Create module directory: `lib/modules/<module_name>/`
2. Create module interface file with:
   - `static const moduleName`
   - `static const moduleDescription`
   - `static const moduleIcon`
   - `static Future<void> launch(BuildContext context)`
   - `static bool isAvailable()`
3. Add module card in `main.dart` HomeScreen
4. Implement module screens

## Dependencies

Current:
- `arcore_flutter_plugin` - AR functionality
- `path_provider` - File storage
- `share_plus` - ZIP export
- `archive` - ZIP compression

Planned:
- `tflite_flutter` - ML inference
- `model_viewer_plus` - 3D visualization

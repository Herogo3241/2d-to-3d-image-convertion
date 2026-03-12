# AR 3D Scanner - Module Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         main.dart                               │
│                      (Home Screen)                              │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │              │  │              │  │              │        │
│  │  AR Capture  │  │    Depth     │  │  3D Viewer   │        │
│  │              │  │  Estimation  │  │              │        │
│  │    [BLUE]    │  │   [ORANGE]   │  │   [GREEN]    │        │
│  │              │  │              │  │              │        │
│  │   Camera     │  │  Filter HDR  │  │  View in AR  │        │
│  │              │  │              │  │              │        │
│  │   ✓ ACTIVE   │  │  ⏳ SOON     │  │  ⏳ SOON     │        │
│  │              │  │              │  │              │        │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │
│         │                 │                  │                 │
│  ┌──────────────┐         │                  │                 │
│  │              │         │                  │                 │
│  │   Gallery    │         │                  │                 │
│  │              │         │                  │                 │
│  │   [PURPLE]   │         │                  │                 │
│  │              │         │                  │                 │
│  │ Photo Library│         │                  │                 │
│  │              │         │                  │                 │
│  │   ✓ ACTIVE   │         │                  │                 │
│  │              │         │                  │                 │
│  └──────┬───────┘         │                  │                 │
│         │                 │                  │                 │
└─────────┼─────────────────┼──────────────────┼─────────────────┘
          │                 │                  │
          │                 │                  │
┌─────────▼─────┐  ┌────────▼────────┐  ┌──────▼───────┐
│               │  │                 │  │              │
│  AR Capture   │  │     Depth       │  │  3D Viewer   │
│    Module     │  │   Estimation    │  │    Module    │
│               │  │     Module      │  │              │
│  ┌─────────┐  │  │  ┌───────────┐ │  │ ┌──────────┐ │
│  │AR Screen│  │  │  │Placeholder│ │  │ │Placeholder│ │
│  │         │  │  │  │  Screen   │ │  │ │  Screen  │ │
│  │ - Place │  │  │  │           │ │  │ │          │ │
│  │   Anchor│  │  │  │ - TFLite  │ │  │ │- Poisson │ │
│  │ - Capture│ │  │  │ - MiDaS   │ │  │ │  Recon   │ │
│  │ - Save  │  │  │  │ - Enhance │ │  │ │- Texture │ │
│  │   Data  │  │  │  │           │ │  │ │  Map     │ │
│  └────┬────┘  │  │  └───────────┘ │  │ └──────────┘ │
│       │       │  │                 │  │              │
└───────┼───────┘  └─────────────────┘  └──────────────┘
        │
        │
        ▼
┌───────────────────────────────────────────────────────┐
│           Native Android (MainActivity.kt)            │
│                                                       │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │             │  │              │  │            │  │
│  │  ARCore     │  │   OpenGL     │  │  Android   │  │
│  │  Session    │  │  Renderer    │  │  Storage   │  │
│  │             │  │              │  │            │  │
│  │ - Tracking  │  │ - Background │  │ - Files    │  │
│  │ - Planes    │  │ - Cube       │  │ - JSON     │  │
│  │ - Anchors   │  │ - Screenshot │  │ - Images   │  │
│  │ - Depth Map │  │ - RGB Fix    │  │ - Depth    │  │
│  │             │  │              │  │            │  │
│  └─────────────┘  └──────────────┘  └────────────┘  │
│                                                       │
└───────────────────────────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────┐
│                 Device Storage                        │
│                                                       │
│  captures/                                            │
│  ├── session_1234567890/                             │
│  │   ├── captures.json                               │
│  │   ├── frame_0.jpg (RGB Fix Applied ✓)            │
│  │   ├── depth_0.raw                                 │
│  │   └── README.txt                                  │
│  └── session_1234567891/                             │
│      └── ...                                          │
│                                                       │
└───────────────────────────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────┐
│                Gallery Module                         │
│                                                       │
│  ┌──────────────┐  ┌──────────────┐                 │
│  │  Session     │  │   Export     │                 │
│  │  Viewer      │  │   to ZIP     │                 │
│  │              │  │              │                 │
│  │ - List all   │  │ - Compress   │                 │
│  │ - Thumbnails │  │ - Share      │                 │
│  │ - Metadata   │  │ - README     │                 │
│  └──────────────┘  └──────────────┘                 │
│                                                       │
└───────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────┐
│                      Data Flow                              │
└─────────────────────────────────────────────────────────────┘

    User Action                    Processing                Output
    
    1. Open App              →   Load Modules           →   Home Screen
                                 Check Availability
    
    2. Start AR Capture      →   Initialize ARCore      →   AR View
                                 Create GL Context
                                 Start Tracking
    
    3. Place Anchor          →   Create Anchor          →   Green Cube
                                 Set Origin Point            Appears
    
    4. Capture Frame         →   glReadPixels (RGBA)    →   RGB Image
                                 ├─ Swap R↔B (Fix)           (Colors OK)
                                 └─ Compress JPEG
                                 
                                 ARCore Depth API       →   Depth Map
                                 ├─ Get 160×90 map           (Binary)
                                 └─ Save Raw Bytes
                                 
                                 Camera.getPose()       →   Pose Matrix
                                 ├─ Get Rotation (3×3)      (4×4 float)
                                 └─ Get Translation
    
    5. Save Session          →   Create Directory       →   File System
                                 Write captures.json
                                 ├─ imagePath
                                 ├─ depthPath
                                 └─ relativePose
    
    6. View Gallery          →   Read captures/         →   Session List
                                 List Directories
                                 Load Metadata
    
    7. Export ZIP            →   Archive.create()       →   Shared File
                                 ├─ Add images
                                 ├─ Add depth
                                 ├─ Add JSON
                                 └─ Add README


┌─────────────────────────────────────────────────────────────┐
│                 Week-by-Week Implementation                 │
└─────────────────────────────────────────────────────────────┘

Week 6 (Current) ✓ DONE
├─ Module architecture created
├─ RGB channel fix implemented
├─ Placeholder screens added
└─ Documentation written

Week 7 (Jan 13-19) ⏳ NEXT
├─ Add tflite_flutter dependency
├─ Download MiDaS Small model
├─ Implement inference pipeline
└─ Test on-device performance

Week 8 (Jan 20-26)
├─ Point cloud generation
├─ Poisson surface reconstruction
├─ Texture mapping
└─ Interactive 3D viewer

Week 9-10
├─ UI refinement
├─ Performance optimization
├─ Multi-session reconstruction
└─ Testing

Week 11-12
├─ Final debugging
├─ Documentation
├─ User guide
└─ Demo preparation

Week 13
├─ Final presentation
├─ Project report
└─ Code submission

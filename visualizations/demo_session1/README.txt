Session Export Data
===================

Files:
- *.jpg: RGB Images
- depth_*.bin: Raw Depth Maps (16-bit unsigned integer, millimeters)
- captures.json: Metadata including timestamps and pose matrices.

Pose Data:
The 'relativePose' in captures.json is a 4x4 transformation matrix (column-major) representing the Camera's position relative to the Anchor (Stick).

Depth Data:
The .bin files contain raw depth values. Each pixel is a 16-bit integer representing distance in millimeters.
Resolution depends on the device (e.g., 160x120 or 640x360).

Python Example to Read Data:
----------------------------
import json
import numpy as np
import os

with open('captures.json', 'r') as f:
    data = json.load(f)

for capture in data:
    # Pose
    pose = np.array(capture['relativePose']).reshape((4,4)).T
    print(f"Timestamp: {capture['timestamp']}")
    print("Pose:\n", pose)
    
    # Depth
    depth_file = f"depth_{capture['timestamp']}.bin"
    if os.path.exists(depth_file):
        depth_data = np.fromfile(depth_file, dtype=np.uint16)
        print(f"Depth pixels: {len(depth_data)}")

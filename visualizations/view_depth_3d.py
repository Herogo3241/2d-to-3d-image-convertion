import numpy as np
import open3d as o3d
import json
import os
import sys
from PIL import Image

def load_depth_map(file_path):
    """Load raw 16-bit binary depth file."""
    if not os.path.exists(file_path):
        return None
        
    with open(file_path, 'rb') as f:
        raw_data = f.read()
    
    # Calculate number of pixels (16-bit = 2 bytes per pixel)
    num_pixels = len(raw_data) // 2
    depth_data = np.frombuffer(raw_data, dtype=np.uint16)
    
    # Common ARCore resolutions
    resolutions = [
        (160, 120),
        (160, 90),
        (640, 360),
        (640, 480),
        (1280, 720),
        (192, 144)
    ]
    
    width, height = 0, 0
    for w, h in resolutions:
        if w * h == num_pixels:
            width, height = w, h
            break
    
    if width == 0:
        print(f"Warning: Could not guess resolution for {num_pixels} pixels.")
        return None
    
    return depth_data.reshape((height, width))

def create_point_cloud(rgb_path, depth_path, fov_degrees=60):
    """Create a colored point cloud from RGB image and depth map."""
    
    # Load RGB image
    rgb_image = Image.open(rgb_path)
    rgb_np = np.array(rgb_image)
    
    # Load depth map
    depth_np = load_depth_map(depth_path)
    if depth_np is None:
        print(f"Failed to load depth map: {depth_path}")
        return None
    
    height, width = depth_np.shape
    
    # Resize RGB to match depth
    rgb_resized = rgb_image.resize((width, height))
    rgb_np = np.array(rgb_resized)
    
    # Estimate camera intrinsics (FOV-based)
    fov_rad = fov_degrees * np.pi / 180
    focal_length = height / (2 * np.tan(fov_rad / 2))
    cx, cy = width / 2, height / 2
    
    # Create point cloud
    points = []
    colors = []
    
    for y in range(height):
        for x in range(width):
            depth = depth_np[y, x]
            
            # Skip invalid depths
            if depth == 0 or depth > 5000:  # 5 meters max
                continue
            
            # Convert depth from mm to meters
            z = depth / 1000.0
            
            # Back-project to 3D
            x_3d = (x - cx) * z / focal_length
            y_3d = (y - cy) * z / focal_length
            
            points.append([x_3d, -y_3d, -z])  # Flip Y and Z for correct orientation
            
            # Get RGB color (normalized to 0-1)
            color = rgb_np[y, x] / 255.0
            colors.append(color)
    
    if len(points) == 0:
        print("No valid points generated!")
        return None
    
    # Create Open3D point cloud
    pcd = o3d.geometry.PointCloud()
    pcd.points = o3d.utility.Vector3dVector(np.array(points))
    pcd.colors = o3d.utility.Vector3dVector(np.array(colors))
    
    return pcd

def visualize_session(session_path, frame_index=0):
    """Visualize a specific frame from a session."""
    
    json_path = os.path.join(session_path, 'captures.json')
    if not os.path.exists(json_path):
        print(f"Error: captures.json not found in {session_path}")
        return
    
    with open(json_path, 'r') as f:
        captures = json.load(f)
    
    if frame_index >= len(captures):
        print(f"Error: Frame {frame_index} not found. Session has {len(captures)} frames.")
        return
    
    capture = captures[frame_index]
    
    # Get filenames from JSON
    img_filename = capture['imagePath'].split('/')[-1]
    depth_filename = capture['depthPath'].split('/')[-1]
    
    img_path = os.path.join(session_path, img_filename)
    depth_path = os.path.join(session_path, depth_filename)
    
    if not os.path.exists(img_path):
        print(f"Missing Image: {img_filename}")
        return
    if not os.path.exists(depth_path):
        print(f"Missing Depth: {depth_filename}")
        return
    
    print(f"Processing frame {frame_index}...")
    print(f"  RGB: {img_filename}")
    print(f"  Depth: {depth_filename}")
    
    # Create point cloud
    pcd = create_point_cloud(img_path, depth_path)
    
    if pcd is None:
        return
    
    print(f"Generated {len(pcd.points)} points")
    
    # Downsample for better visualization
    pcd = pcd.voxel_down_sample(voxel_size=0.005)
    
    print(f"Downsampled to {len(pcd.points)} points")
    
    # Add coordinate frame
    axis = o3d.geometry.TriangleMesh.create_coordinate_frame(size=0.2, origin=[0, 0, 0])
    
    # Visualize
    print("\nVisualization Controls:")
    print("  - Mouse drag: Rotate")
    print("  - Scroll: Zoom")
    print("  - Ctrl + Mouse drag: Pan")
    print("  - Q or ESC: Close")
    
    o3d.visualization.draw_geometries(
        [pcd, axis],
        window_name=f"Depth Visualization - Frame {frame_index}",
        width=1024,
        height=768,
        point_show_normal=False
    )

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python view_depth_3d.py <session_folder> [frame_index]")
        print("Example: python view_depth_3d.py session_pen 0")
        sys.exit(1)
    
    session_path = sys.argv[1]
    frame_index = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    
    visualize_session(session_path, frame_index)
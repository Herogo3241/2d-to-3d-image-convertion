import json
import os
import struct
import numpy as np
import open3d as o3d
from PIL import Image
import sys

def load_session(session_path):
    json_path = os.path.join(session_path, 'captures.json')
    if not os.path.exists(json_path):
        print(f"Error: captures.json not found in {session_path}")
        return []
    
    with open(json_path, 'r') as f:
        return json.load(f)

def load_depth_map(file_path):
    """
    Reads a raw 16-bit binary depth file and returns a numpy array.
    Tries to guess resolution based on file size.
    """
    if not os.path.exists(file_path):
        return None
        
    with open(file_path, 'rb') as f:
        raw_data = f.read()
        
    # Calculate number of pixels (16-bit = 2 bytes per pixel)
    num_pixels = len(raw_data) // 2
    depth_data = np.frombuffer(raw_data, dtype=np.uint16)
    
    # Guess resolution
    # Common ARCore resolutions
    resolutions = [
        (160, 120),
        (160,90),
        (640, 360),
        (640, 480),
        (1280, 720),
        (192, 144) # Sometimes used
    ]
    
    width, height = 0, 0
    for w, h in resolutions:
        if w * h == num_pixels:
            width, height = w, h
            break
            
    if width == 0:
        # Fallback: try to find a common aspect ratio or just square root
        print(f"Warning: Could not guess resolution for {num_pixels} pixels.")
        # Assume 4:3 aspect ratio approximation
        h_est = int(np.sqrt(3 * num_pixels / 4))
        w_est = num_pixels // h_est
        if w_est * h_est == num_pixels:
            width, height = w_est, h_est
        else:
            print("Failed to determine dimensions.")
            return None

    return depth_data.reshape((height, width))

def process_session(session_path):
    captures = load_session(session_path)
    if not captures:
        return

    combined_pcd = o3d.geometry.PointCloud()
    
    print(f"Processing {len(captures)} captures...")

    for i, capture in enumerate(captures):
        # 1. Load Pose
        # Flutter Matrix4 is Column-Major flattened.
        # We need to reshape and transpose to get Row-Major for Numpy
        pose_flat = np.array(capture['relativePose'])
        pose_matrix = pose_flat.reshape((4, 4)).T
        
        # 2. Determine Filenames
        # The JSON contains absolute Android paths (e.g., /data/user/0/.../rgb_123.jpg)
        # We need to extract just the filename and look for it in the session folder.
        
        if 'imagePath' not in capture or 'depthPath' not in capture:
            print(f"Skipping frame {i}: JSON missing 'imagePath' or 'depthPath'")
            continue

        # Split by '/' to handle Android paths correctly on Windows
        img_filename = capture['imagePath'].split('/')[-1]
        depth_filename = capture['depthPath'].split('/')[-1]
        
        img_path = os.path.join(session_path, img_filename)
        depth_path = os.path.join(session_path, depth_filename)
        
        if not os.path.exists(img_path):
            print(f"Missing Image: {img_filename}")
            continue
        if not os.path.exists(depth_path):
            print(f"Missing Depth: {depth_filename}")
            continue
            
        # Load RGB
        color_pil = Image.open(img_path)
        
        # Load Depth
        depth_np = load_depth_map(depth_path)
        if depth_np is None:
            continue
            
        height, width = depth_np.shape
        
        # Resize Color to match Depth
        color_pil_resized = color_pil.resize((width, height))
        
        # Create Open3D Images
        color_o3d = o3d.geometry.Image(np.array(color_pil_resized))
        depth_o3d = o3d.geometry.Image(depth_np)
        
        # Create RGBD Image
        # depth_scale=1000.0 because data is in mm, we want meters
        # depth_trunc=5.0 truncates depth > 5 meters
        rgbd_image = o3d.geometry.RGBDImage.create_from_color_and_depth(
            color_o3d, 
            depth_o3d, 
            depth_scale=1000.0, 
            depth_trunc=5.0, 
            convert_rgb_to_intensity=False
        )
        
        # Create Point Cloud
        # Intrinsic parameters (PinholeCameraIntrinsic)
        # Since we don't have them, we estimate.
        # ARCore usually has FOV around 60-70 degrees vertical.
        # Focal length ~ width / (2 * tan(FOV/2))
        # Let's assume vertical FOV of 60 degrees.
        fov_rad = 60 * np.pi / 180
        focal_length = height / (2 * np.tan(fov_rad / 2))
        
        intrinsics = o3d.camera.PinholeCameraIntrinsic(
            width, height, 
            focal_length, focal_length, # fx, fy
            width / 2, height / 2       # cx, cy
        )
        
        pcd = o3d.geometry.PointCloud.create_from_rgbd_image(
            rgbd_image, intrinsics
        )
        
        # Transform Point Cloud to Anchor Frame
        pcd.transform(pose_matrix)
        
        # Add to combined
        combined_pcd += pcd
        print(f"Processed frame {i+1}/{len(captures)}")

        # Visualization for individual frame
        print(f"Visualizing frame {i+1}...")
        
        # Add a coordinate frame for the Anchor (Origin)
        axis = o3d.geometry.TriangleMesh.create_coordinate_frame(size=0.2, origin=[0, 0, 0])
        
        # Visualize individual frame
        o3d.visualization.draw_geometries_with_editing([pcd, axis], 
                                          window_name=f"Frame {i+1} - Shift+Click to pick points",
                                          width=1024, height=768)

    print("Finished processing all frames.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python visualize_session.py <path_to_extracted_session_folder>")
        print("Example: python visualize_session.py ./session_12345")
    else:
        process_session(sys.argv[1])
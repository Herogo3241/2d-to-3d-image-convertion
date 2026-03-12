import numpy as np
import matplotlib.pyplot as plt
import json
import os
import sys
from mpl_toolkits.mplot3d import Axes3D
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

def visualize_depth_map(session_path, frame_index=0):
    """Visualize depth map as 2D heatmap and 3D surface with RGB comparison."""
    
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
    
    # Load RGB image
    rgb_image = Image.open(img_path)
    rgb_np = np.array(rgb_image)
    
    # Load depth map
    depth_np = load_depth_map(depth_path)
    
    if depth_np is None:
        print("Failed to load depth map!")
        return
    
    height, width = depth_np.shape
    print(f"  RGB Resolution: {rgb_image.width}x{rgb_image.height}")
    print(f"  Depth Resolution: {width}x{height}")
    
    # Resize depth map to match RGB for comparison
    depth_resized = Image.fromarray(depth_np).resize((rgb_image.width, rgb_image.height), Image.NEAREST)
    depth_resized_np = np.array(depth_resized)
    
    # Convert to meters and filter invalid depths
    depth_meters = depth_np.astype(float) / 1000.0
    depth_meters[depth_meters == 0] = np.nan  # Invalid depths
    depth_meters[depth_meters > 5.0] = np.nan  # Beyond 5 meters
    
    depth_resized_meters = depth_resized_np.astype(float) / 1000.0
    depth_resized_meters[depth_resized_meters == 0] = np.nan
    depth_resized_meters[depth_resized_meters > 5.0] = np.nan
    
    # Statistics
    valid_depths = depth_meters[~np.isnan(depth_meters)]
    print(f"  Valid pixels: {len(valid_depths)}/{width*height}")
    print(f"  Depth range: {np.min(valid_depths):.2f}m - {np.max(valid_depths):.2f}m")
    print(f"  Mean depth: {np.mean(valid_depths):.2f}m")
    
    # Create figure with multiple views
    fig = plt.figure(figsize=(18, 12))
    
    # 1. RGB Image
    ax1 = fig.add_subplot(3, 3, 1)
    ax1.imshow(rgb_np)
    ax1.set_title(f'RGB Image - Frame {frame_index}')
    ax1.set_xlabel('Width (pixels)')
    ax1.set_ylabel('Height (pixels)')
    ax1.axis('on')
    
    # 2. Depth map overlaid on RGB
    ax2 = fig.add_subplot(3, 3, 2)
    ax2.imshow(rgb_np)
    im2 = ax2.imshow(depth_resized_meters, cmap='viridis', alpha=0.6, interpolation='nearest')
    ax2.set_title('RGB + Depth Overlay')
    ax2.set_xlabel('Width (pixels)')
    ax2.set_ylabel('Height (pixels)')
    plt.colorbar(im2, ax=ax2, label='Depth (meters)')
    
    # 3. Depth heatmap (original resolution)
    ax3 = fig.add_subplot(3, 3, 3)
    im3 = ax3.imshow(depth_meters, cmap='viridis', interpolation='nearest')
    ax3.set_title(f'Depth Map - Original ({width}x{height})')
    ax3.set_xlabel('Width (pixels)')
    ax3.set_ylabel('Height (pixels)')
    plt.colorbar(im3, ax=ax3, label='Depth (meters)')
    
    # 4. Inverted depth (closer = brighter)
    ax4 = fig.add_subplot(3, 3, 4)
    im4 = ax4.imshow(depth_meters, cmap='viridis_r', interpolation='nearest')
    ax4.set_title('Depth (Inverted - Closer = Brighter)')
    ax4.set_xlabel('Width (pixels)')
    ax4.set_ylabel('Height (pixels)')
    plt.colorbar(im4, ax=ax4, label='Depth (meters)')
    
    # 5. Edge detection on depth
    ax5 = fig.add_subplot(3, 3, 5)
    from scipy.ndimage import sobel
    depth_clean = np.nan_to_num(depth_meters, nan=0.0)
    edges = np.hypot(sobel(depth_clean, axis=0), sobel(depth_clean, axis=1))
    im5 = ax5.imshow(edges, cmap='hot', interpolation='nearest')
    ax5.set_title('Depth Edges (Discontinuities)')
    ax5.set_xlabel('Width (pixels)')
    ax5.set_ylabel('Height (pixels)')
    plt.colorbar(im5, ax=ax5, label='Edge Magnitude')
    
    # 6. Side-by-side comparison (resized)
    ax6 = fig.add_subplot(3, 3, 6)
    comparison = np.hstack([
        rgb_np[:, :rgb_np.shape[1]//2, :],
        np.repeat(depth_resized_meters[:, depth_resized_meters.shape[1]//2:, np.newaxis], 3, axis=2)
    ])
    ax6.imshow(comparison, cmap='viridis')
    ax6.set_title('Left: RGB | Right: Depth')
    ax6.axis('off')
    
    # 7. 3D Surface plot
    ax7 = fig.add_subplot(3, 3, 7, projection='3d')
    X, Y = np.meshgrid(np.arange(width), np.arange(height))
    surf = ax7.plot_surface(X, Y, depth_meters, cmap='viridis', 
                            linewidth=0, antialiased=True, alpha=0.8)
    ax7.set_title('3D Surface View')
    ax7.set_xlabel('Width')
    ax7.set_ylabel('Height')
    ax7.set_zlabel('Depth (m)')
    ax7.invert_zaxis()  # Invert Z so closer objects are "up"
    plt.colorbar(surf, ax=ax7, shrink=0.5, label='Depth (m)')
    
    # 8. Depth histogram
    ax8 = fig.add_subplot(3, 3, 8)
    ax8.hist(valid_depths, bins=50, color='skyblue', edgecolor='black')
    ax8.set_title('Depth Distribution')
    ax8.set_xlabel('Depth (meters)')
    ax8.set_ylabel('Pixel Count')
    ax8.grid(True, alpha=0.3)
    ax8.axvline(np.mean(valid_depths), color='red', linestyle='--', label=f'Mean: {np.mean(valid_depths):.2f}m')
    ax8.legend()
    
    # 9. Depth statistics text
    ax9 = fig.add_subplot(3, 3, 9)
    ax9.axis('off')
    stats_text = f"""
    Frame {frame_index} Statistics:
    
    RGB Resolution: {rgb_image.width} × {rgb_image.height}
    Depth Resolution: {width} × {height}
    
    Valid Pixels: {len(valid_depths):,} / {width*height:,}
    Coverage: {100*len(valid_depths)/(width*height):.1f}%
    
    Depth Range:
      Min: {np.min(valid_depths):.3f} m
      Max: {np.max(valid_depths):.3f} m
      Mean: {np.mean(valid_depths):.3f} m
      Median: {np.median(valid_depths):.3f} m
      Std Dev: {np.std(valid_depths):.3f} m
    """
    ax9.text(0.1, 0.5, stats_text, fontsize=11, family='monospace',
             verticalalignment='center', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python view_depth_map.py <session_folder> [frame_index]")
        print("Example: python view_depth_map.py session_pen 0")
        sys.exit(1)
    
    session_path = sys.argv[1]
    frame_index = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    
    visualize_depth_map(session_path, frame_index)
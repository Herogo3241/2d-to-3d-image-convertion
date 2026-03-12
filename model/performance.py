import cv2
import torch
import numpy as np
import tensorflow as tf
import time
import requests
from io import BytesIO
import matplotlib.pyplot as plt
# --- Configuration ---
NUM_IMAGES = 25  # Number of images to test
TFLITE_MODEL_PATH = "MiDaS.tflite"
TARGET_HW = (256, 256)

# --- Initialize Models (CPU Only) ---
print("Initializing models...")
# 1. PyTorch
midas = torch.hub.load("intel-isl/MiDaS", "MiDaS_small")
midas.to(torch.device("cpu"))
midas.eval()
midas_transforms = torch.hub.load("intel-isl/MiDaS", "transforms").small_transform

# 2. TFLite
interpreter = tf.lite.Interpreter(model_path=TFLITE_MODEL_PATH)
interpreter.allocate_tensors()
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

def get_lorem_picsum(n):
    images = []
    print(f"Downloading {n} images from Lorem Picsum...")
    for i in range(n):
        # Using a random seed to get different images
        response = requests.get(f"https://picsum.photos/seed/{i+42}/640/480")
        img = cv2.imdecode(np.frombuffer(response.content, np.uint8), cv2.IMREAD_COLOR)
        images.append(img)
    return images

def run_pytorch(img):
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    input_batch = midas_transforms(img_rgb).to("cpu")
    
    start = time.time()
    with torch.no_grad():
        prediction = midas(input_batch)
    end = time.time()
    return end - start

def run_tflite(img):
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    img_resized = cv2.resize(img_rgb, (TARGET_HW[1], TARGET_HW[0]), interpolation=cv2.INTER_CUBIC)
    img_resized = img_resized.astype(np.float32) / 255.0
    
    # Normalize
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std  = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    img_norm = (img_resized - mean) / std
    
    # Prepare input (assuming channels-last for TFLite)
    input_data = np.expand_dims(img_norm, axis=0)
    interpreter.set_tensor(input_details[0]['index'], input_data)
    
    start = time.time()
    interpreter.invoke()
    end = time.time()
    return end - start

# --- Main Performance Loop ---
test_images = get_lorem_picsum(NUM_IMAGES)
pt_times = []
tf_times = []

print(f"\n{'Image':<10} | {'PyTorch (s)':<15} | {'TFLite (s)':<15}")
print("-" * 45)

for i, img in enumerate(test_images):
    # Warmup for the first image
    pt_t = run_pytorch(img)
    tf_t = run_tflite(img)
    
    pt_times.append(pt_t)
    tf_times.append(tf_t)
    print(f"{i+1:<10} | {pt_t:<15.4f} | {tf_t:<15.4f}")

print("-" * 45)
print(f"{'AVERAGE':<10} | {np.mean(pt_times):<15.4f} | {np.mean(tf_times):<15.4f}")



# --- Plotting Section (Line Graph) ---
print("\nGenerating performance line graph...")
indices = np.arange(1, NUM_IMAGES + 1)  # Use 1-based indexing for the x-axis labels

plt.figure(figsize=(10, 6))

# Plot PyTorch times
plt.plot(indices, pt_times, marker='o', linestyle='-', color='skyblue', 
         label='PyTorch', linewidth=2, markersize=4)

# Plot TFLite times
plt.plot(indices, tf_times, marker='o', linestyle='-', color='orange', 
         label='TFLite', linewidth=2, markersize=4)

plt.xlabel('Image Index')
plt.ylabel('Execution Time (seconds)')
plt.title('MiDaS Depth Estimation: PyTorch vs TFLite Performance')
plt.xticks(indices)  # Ensure only whole numbers for image indices are shown
plt.legend()
plt.grid(True, linestyle='--', alpha=0.6)

# Save the plot
plt.tight_layout()
plt.savefig('performance_comparison_line.png')
print("Graph saved as 'performance_comparison_line.png'")
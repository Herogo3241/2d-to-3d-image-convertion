import torch
from torch.utils.mobile_optimizer import optimize_for_mobile
import warnings

# Suppress some noisy tracing warnings
warnings.filterwarnings("ignore")

print("1. Loading MiDaS Small architecture...")
# Load the architecture without downloading the default weights
model = torch.hub.load("intel-isl/MiDaS", "MiDaS_small", pretrained=False)

print("2. Loading local weights...")
# Load your local state dictionary
state_dict = torch.load('source\\midas_v21_small_256.pt', map_location=torch.device('cpu'))
model.load_state_dict(state_dict)

# Set the model to evaluation mode (crucial before tracing)
model.eval()

print("3. Tracing the model...")
# Create a dummy input tensor that matches the expected input shape (Batch, Channels, Height, Width)
example_input = torch.rand(1, 3, 256, 256)

# Trace the model with strict=False to bypass the dynamic padding check
traced_script_module = torch.jit.trace(model, example_input, check_trace=False)

print("4. Optimizing for mobile...")
# Optimize the TorchScript model for mobile execution
optimized_traced_model = optimize_for_mobile(traced_script_module)

# Save the optimized model
output_filename = "midas_small.ptl"
optimized_traced_model._save_for_lite_interpreter(output_filename)

print(f"Success! Exported to {output_filename}")
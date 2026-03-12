import 'dart:typed_data';
import 'dart:math';

/// Utility class for filtering point clouds based on depth and spatial criteria
class PointCloudFilter {
  /// Create a binary mask that isolates the main object based on depth
  /// Returns a mask where 255 = include point, 0 = exclude point
  static Uint8List depthBasedMask(
    Uint16List depthData,
    int width,
    int height, {
    FilterMode mode = FilterMode.autoForeground,
    double? customThreshold,
  }) {
    final mask = Uint8List(depthData.length);

    switch (mode) {
      case FilterMode.autoForeground:
        return _autoForegroundMask(depthData, width, height);
      case FilterMode.centerObject:
        return _centerObjectMask(depthData, width, height);
      case FilterMode.depthRange:
        return _depthRangeMask(depthData, customThreshold ?? 2000);
      case FilterMode.none:
        mask.fillRange(0, mask.length, 255);
        return mask;
    }
  }

  /// Automatically detect foreground based on depth histogram
  static Uint8List _autoForegroundMask(
    Uint16List depthData,
    int width,
    int height,
  ) {
    final mask = Uint8List(depthData.length);

    // Filter valid depths
    final validDepths = depthData.where((d) => d > 100 && d < 10000).toList();
    if (validDepths.isEmpty) {
      mask.fillRange(0, mask.length, 255);
      return mask;
    }

    // Calculate depth statistics
    validDepths.sort();
    // final percentile25 = validDepths[(validDepths.length * 0.25).toInt()];
    // final median = validDepths[validDepths.length ~/ 2];
    final percentile75 = validDepths[(validDepths.length * 0.75).toInt()];

    // Foreground is anything closer than 75th percentile
    // This captures the main object while excluding far background
    final threshold = percentile75;

    for (int i = 0; i < depthData.length; i++) {
      final depth = depthData[i];
      if (depth > 100 && depth < threshold) {
        mask[i] = 255;
      }
    }

    // Apply morphological operations to clean up mask
    return _morphologicalClose(mask, width, height, kernelSize: 5);
  }

  /// Focus on object in center of frame
  static Uint8List _centerObjectMask(
    Uint16List depthData,
    int width,
    int height,
  ) {
    final mask = Uint8List(depthData.length);
    final centerX = width / 2;
    final centerY = height / 2;

    // Define region of interest (center 60% of image)
    final roiRadius = min(width, height) * 0.3;

    // Find average depth in center region
    double sumDepth = 0;
    int count = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final dx = x - centerX;
        final dy = y - centerY;
        final dist = sqrt(dx * dx + dy * dy);

        if (dist < roiRadius) {
          final idx = y * width + x;
          final depth = depthData[idx];
          if (depth > 100 && depth < 10000) {
            sumDepth += depth;
            count++;
          }
        }
      }
    }

    if (count == 0) {
      mask.fillRange(0, mask.length, 255);
      return mask;
    }

    final avgCenterDepth = sumDepth / count;
    final tolerance = avgCenterDepth * 0.3; // ±30% of center depth

    // Include points within depth range of center object
    for (int i = 0; i < depthData.length; i++) {
      final depth = depthData[i];
      if ((depth - avgCenterDepth).abs() < tolerance) {
        mask[i] = 255;
      }
    }

    return _morphologicalClose(mask, width, height, kernelSize: 3);
  }

  /// Simple depth range filter
  static Uint8List _depthRangeMask(Uint16List depthData, double maxDepth) {
    final mask = Uint8List(depthData.length);

    for (int i = 0; i < depthData.length; i++) {
      final depth = depthData[i];
      if (depth > 100 && depth < maxDepth) {
        mask[i] = 255;
      }
    }

    return mask;
  }

  /// Apply morphological closing (dilation followed by erosion)
  /// Helps fill holes and smooth the mask
  static Uint8List _morphologicalClose(
    Uint8List mask,
    int width,
    int height, {
    int kernelSize = 5,
  }) {
    // Dilation
    final dilated = _dilate(mask, width, height, kernelSize);
    // Erosion
    final closed = _erode(dilated, width, height, kernelSize);
    return closed;
  }

  /// Morphological dilation
  static Uint8List _dilate(
    Uint8List mask,
    int width,
    int height,
    int kernelSize,
  ) {
    final result = Uint8List(mask.length);
    final radius = kernelSize ~/ 2;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int maxVal = 0;

        for (int ky = -radius; ky <= radius; ky++) {
          for (int kx = -radius; kx <= radius; kx++) {
            final ny = y + ky;
            final nx = x + kx;

            if (ny >= 0 && ny < height && nx >= 0 && nx < width) {
              final val = mask[ny * width + nx];
              if (val > maxVal) maxVal = val;
            }
          }
        }

        result[y * width + x] = maxVal;
      }
    }

    return result;
  }

  /// Morphological erosion
  static Uint8List _erode(
    Uint8List mask,
    int width,
    int height,
    int kernelSize,
  ) {
    final result = Uint8List(mask.length);
    final radius = kernelSize ~/ 2;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int minVal = 255;

        for (int ky = -radius; ky <= radius; ky++) {
          for (int kx = -radius; kx <= radius; kx++) {
            final ny = y + ky;
            final nx = x + kx;

            if (ny >= 0 && ny < height && nx >= 0 && nx < width) {
              final val = mask[ny * width + nx];
              if (val < minVal) minVal = val;
            }
          }
        }

        result[y * width + x] = minVal;
      }
    }

    return result;
  }

  /// Create a circular mask centered on the image
  static Uint8List circularMask(int width, int height, {double radiusFactor = 0.4}) {
    final mask = Uint8List(width * height);
    final centerX = width / 2;
    final centerY = height / 2;
    final radius = min(width, height) * radiusFactor;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final dx = x - centerX;
        final dy = y - centerY;
        final dist = sqrt(dx * dx + dy * dy);

        mask[y * width + x] = dist < radius ? 255 : 0;
      }
    }

    return mask;
  }

  /// Combine multiple masks using AND operation
  static Uint8List combineMasks(List<Uint8List> masks) {
    if (masks.isEmpty) return Uint8List(0);
    if (masks.length == 1) return masks[0];

    final result = Uint8List(masks[0].length);

    for (int i = 0; i < result.length; i++) {
      result[i] = masks.every((mask) => mask[i] > 0) ? 255 : 0;
    }

    return result;
  }
}

enum FilterMode {
  /// Automatically detect foreground based on depth histogram
  autoForeground,

  /// Focus on object in center of frame
  centerObject,

  /// Simple depth range threshold
  depthRange,

  /// No filtering (include all points)
  none,
}

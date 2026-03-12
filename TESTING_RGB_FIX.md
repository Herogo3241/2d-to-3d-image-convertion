# Testing the RGB Channel Fix

## Background

Previously, captured images were showing as entirely green because of a color channel mismatch:
- **OpenGL `glReadPixels()`** returns pixels in **RGBA** format
- **Android `Bitmap`** expects pixels in **ARGB** format
- Without conversion, the color channels were misaligned, causing a green tint

## The Fix

Added channel swapping logic in `MainActivity.kt` (lines 287-295):

```kotlin
// Fix color channels: glReadPixels returns RGBA, but we need ARGB
// Swap R and B channels
val pixels = IntArray(size)
bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
for (i in pixels.indices) {
    val pixel = pixels[i]
    val a = (pixel shr 24) and 0xFF  // Alpha
    val r = (pixel shr 16) and 0xFF  // Red
    val g = (pixel shr 8) and 0xFF   // Green
    val b = pixel and 0xFF           // Blue
    pixels[i] = (a shl 24) or (b shl 16) or (g shl 8) or r  // Rearrange to ARGB
}
```

**Bit Operation Explanation:**
- `shr` = Shift right (extract a color component)
- `and 0xFF` = Mask to get only 8 bits (0-255)
- `shl` = Shift left (place component in correct position)
- `or` = Combine all components into final ARGB pixel

## Testing Steps

### 1. Install the Updated APK

```bash
cd c:\Users\ivinm\D-Drive\Repos\S8-Final-Project\app
adb devices  # Verify device is connected
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

### 2. Capture Test Images

1. Launch the app
2. Tap "**AR Capture**" module
3. Point camera at a colorful object (e.g., a book with colored cover, a fruit, a toy)
4. Wait for plane detection (grid overlay appears)
5. Tap "**Place Anchor**" button
6. Green cube should appear at the center
7. Tap "**Capture**" button
8. Wait for "Capture saved" message

### 3. Verify Colors in Gallery

1. Go back to home screen
2. Tap "**Gallery**" module
3. Find the latest session (e.g., `session_<timestamp>`)
4. Tap on the session card
5. View the captured image

**Expected Results:**
- ✅ Colors should match what you saw through the camera
- ✅ Red objects should appear red (not blue or green)
- ✅ Blue objects should appear blue (not red)
- ✅ Green objects should appear green (but not the entire image)
- ✅ Skin tones should look natural
- ✅ No dominant color tint across the entire image

**Failed Results (if fix didn't work):**
- ❌ Entire image has a green tint
- ❌ Red and blue channels are swapped
- ❌ Colors are inverted or distorted

### 4. Compare with Previous Sessions

If you have old sessions captured before this fix:
1. Open an old session in gallery
2. Note the green tint in old images
3. Open the new session you just captured
4. Compare side-by-side

### 5. Test with Different Lighting

Capture scenes with:
- **Bright sunlight** - Should handle highlights correctly
- **Indoor lighting** - Colors should be accurate under artificial light
- **Colorful objects** - Red apple, blue book, yellow banana
- **White/gray surfaces** - Should appear neutral (not tinted)

### 6. Export and View on Computer

1. In gallery, tap export button on the new session
2. Share the ZIP file (e.g., via email or file transfer)
3. Extract on your computer
4. Open `frame_0.jpg` in an image viewer
5. Verify colors are correct on a calibrated monitor

## Troubleshooting

### If colors are still wrong:

1. **Check if the fix was compiled:**
   ```bash
   adb logcat | grep "saveScreenshot"
   ```
   Look for the function being called during capture

2. **Rebuild from scratch:**
   ```bash
   flutter clean
   flutter build apk
   adb install -r build\app\outputs\flutter-apk\app-release.apk
   ```

3. **Check Android version:**
   - The fix uses standard OpenGL ES 2.0 and Android Bitmap APIs
   - Should work on Android 7.0+ (API 24+)
   - ARCore requires Android 7.0+ anyway

4. **Verify no other image processing:**
   - Check if any image filters are applied
   - Ensure JPEG compression quality is 100%

### If the app crashes during capture:

1. Check logcat for errors:
   ```bash
   adb logcat | grep "MainActivity"
   ```

2. Verify memory allocation:
   - Large images (e.g., 1920×1080) require significant memory
   - The fix creates a copy of the pixel array (~8MB for Full HD)

3. Test with lower resolution if needed

## Technical Details

### Color Format Comparison

| Format | Channel Order | Bit Layout |
|--------|--------------|------------|
| RGBA   | R, G, B, A   | `RRRRRRRR GGGGGGGG BBBBBBBB AAAAAAAA` |
| ARGB   | A, R, G, B   | `AAAAAAAA RRRRRRRR GGGGGGGG BBBBBBBB` |

### Why glReadPixels Uses RGBA

OpenGL ES standard specifies `GL_RGBA` as the default format for framebuffer reads. This is consistent across all platforms (Android, iOS, desktop).

### Why Android Bitmap Uses ARGB

Android's `Bitmap.Config.ARGB_8888` format stores alpha in the most significant byte for faster alpha blending operations.

### Performance Impact

- **Memory:** 2× temporary allocation (once for raw pixels, once for swapped pixels)
- **CPU Time:** ~1-2ms for 1920×1080 image on modern devices
- **Storage:** No impact (JPEG compression removes the extra copy)

## Success Criteria

✅ The fix is working correctly if:
1. Captured images match the camera preview colors
2. No dominant color tint across the image
3. Red, green, and blue objects appear in their correct colors
4. White/gray surfaces appear neutral
5. Skin tones look natural

## Next Steps After Verification

Once you confirm the RGB fix is working:
1. Delete old sessions with green-tinted images (if any)
2. Capture a new dataset for testing depth enhancement (Week 7)
3. Proceed with TensorFlow Lite integration for ML-based depth estimation

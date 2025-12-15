#include <jni.h>
#include <vector>
#include <cmath>

extern "C"
JNIEXPORT jobject JNICALL
Java_com_example_image3d_1converter_NativeMesh_generateMesh(
        JNIEnv* env,
        jobject /* this */,
        jobject depthBuffer,
        jobject imageBuffer,
        jint width,
        jint height
) {
    // -----------------------------
    // Access direct buffers
    // -----------------------------
    float* depth = static_cast<float*>(env->GetDirectBufferAddress(depthBuffer));
    unsigned char* rgb = static_cast<unsigned char*>(env->GetDirectBufferAddress(imageBuffer));

    if (!depth || !rgb) {
        return nullptr;
    }

    // -----------------------------
    // Mesh storage
    // -----------------------------
    std::vector<float> vertices;
    std::vector<float> colors;
    std::vector<int> indices;

    vertices.reserve(width * height * 3);
    colors.reserve(width * height * 3);
    indices.reserve(width * height * 6);

    // -----------------------------
    // Background threshold
    // -----------------------------
    constexpr float DEPTH_BG_THRESHOLD = 0.05f;

    // -----------------------------
    // Generate mesh
    // -----------------------------
    for (int y = 0; y < height - 1; y++) {
        for (int x = 0; x < width - 1; x++) {

            int i0 = y * width + x;
            int i1 = y * width + (x + 1);
            int i2 = (y + 1) * width + x;
            int i3 = (y + 1) * width + (x + 1);

            float z0 = depth[i0];
            float z1 = depth[i1];
            float z2 = depth[i2];
            float z3 = depth[i3];

            // ❌ Skip background quads
            if (z0 < DEPTH_BG_THRESHOLD ||
                z1 < DEPTH_BG_THRESHOLD ||
                z2 < DEPTH_BG_THRESHOLD ||
                z3 < DEPTH_BG_THRESHOLD) {
                continue;
            }

            auto addVertex = [&](int idx, float z) -> int {
                float X = (idx % width) - width * 0.5f;
                float Y = (idx / width) - height * 0.5f;
                float Z = z;

                int rgbIndex = idx * 4; // RGBA

                vertices.push_back(X);
                vertices.push_back(-Y);
                vertices.push_back(-Z);

                colors.push_back(rgb[rgbIndex]     / 255.0f);
                colors.push_back(rgb[rgbIndex + 1] / 255.0f);
                colors.push_back(rgb[rgbIndex + 2] / 255.0f);

                return static_cast<int>(vertices.size() / 3 - 1);
            };

            int v0 = addVertex(i0, z0);
            int v1 = addVertex(i1, z1);
            int v2 = addVertex(i2, z2);
            int v3 = addVertex(i3, z3);

            // Triangle 1
            indices.push_back(v0);
            indices.push_back(v1);
            indices.push_back(v2);

            // Triangle 2
            indices.push_back(v1);
            indices.push_back(v3);
            indices.push_back(v2);
        }
    }

    // -----------------------------
    // Create Java MeshResult object
    // -----------------------------
    jclass resultClass = env->FindClass("com/example/image3d_converter/MeshResult");
    if (!resultClass) return nullptr;

    jmethodID ctor = env->GetMethodID(resultClass, "<init>", "([F[F[I)V");
    if (!ctor) return nullptr;

    jfloatArray vertexArray = env->NewFloatArray(vertices.size());
    env->SetFloatArrayRegion(vertexArray, 0, vertices.size(), vertices.data());

    jfloatArray colorArray = env->NewFloatArray(colors.size());
    env->SetFloatArrayRegion(colorArray, 0, colors.size(), colors.data());

    jintArray indexArray = env->NewIntArray(indices.size());
    env->SetIntArrayRegion(indexArray, 0, indices.size(), indices.data());

    return env->NewObject(resultClass, ctor, vertexArray, colorArray, indexArray);
}

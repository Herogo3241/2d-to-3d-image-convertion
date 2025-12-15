package com.example.image3d_converter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {

    private val CHANNEL = "native_mesh_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "generateMesh") {

                val depthBuffer = call.argument<ByteArray>("depth")!!
                val imageBuffer = call.argument<ByteArray>("image")!!
                val width = call.argument<Int>("width")!!
                val height = call.argument<Int>("height")!!

                // 1. Allocate Direct Memory (Off-Heap)
                val depthBB = ByteBuffer.allocateDirect(depthBuffer.size)
                // 2. Set Endianness (Critical for float conversion in C++)
                depthBB.order(ByteOrder.nativeOrder()) 
                // 3. Copy data from Java Heap to Direct Memory
                depthBB.put(depthBuffer)
                // 4. Rewind buffer position to 0 so C++ reads from the start
                depthBB.position(0)

                // Do the same for the image buffer
                val imageBB = ByteBuffer.allocateDirect(imageBuffer.size)
                imageBB.order(ByteOrder.nativeOrder())
                imageBB.put(imageBuffer)
                imageBB.position(0)

                val mesh = NativeMesh.generateMesh(
                    depthBB,
                    imageBB,
                    width,
                    height
                )

                val meshMap = mapOf(
                    "vertices" to mesh.vertices,
                    "colors" to mesh.colors,
                    "indices" to mesh.indices
                )

                result.success(meshMap)

            } else {
                result.notImplemented()
            }
        }
    }

    companion object {
        init {
            System.loadLibrary("native_mesh")
        }
    }
}

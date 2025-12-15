package com.example.image3d_converter

object NativeMesh {

    init {
        System.loadLibrary("native_mesh")
    }

    external fun generateMesh(
        depth: java.nio.ByteBuffer,
        image: java.nio.ByteBuffer,
        width: Int,
        height: Int
    ): MeshResult
}

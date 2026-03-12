package com.example.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.display.DisplayManager
import android.media.Image
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Bundle
import android.util.Log
import android.view.Display
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory("ar_view", NativeArViewFactory(flutterEngine, this))
    }
}

class NativeArViewFactory(private val flutterEngine: FlutterEngine, private val activity: android.app.Activity) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NativeArView(context, flutterEngine, activity)
    }
}

class NativeArView(private val context: Context, private val flutterEngine: FlutterEngine, private val activity: android.app.Activity) : PlatformView, GLSurfaceView.Renderer, MethodChannel.MethodCallHandler {
    private val surfaceView: GLSurfaceView = GLSurfaceView(context)
    private var session: Session? = null
    private val backgroundRenderer = BackgroundRenderer()
    private val objectRenderer = SimpleObjectRenderer()
    private var displayRotationHelper: DisplayRotationHelper? = null
    private var currentAnchor: Anchor? = null
    private var shouldCapture = false
    private var captureDir: String? = null
    private var captureResult: MethodChannel.Result? = null
    private var hideAnchor = false
    private val methodChannel: MethodChannel

    init {
        surfaceView.preserveEGLContextOnPause = true
        surfaceView.setEGLContextClientVersion(2)
        surfaceView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        surfaceView.setRenderer(this)
        surfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        surfaceView.setWillNotDraw(false)

        displayRotationHelper = DisplayRotationHelper(context)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.app/ar")
        methodChannel.setMethodCallHandler(this)
    }

    override fun getView(): View {
        return surfaceView
    }

    override fun dispose() {
        session?.close()
        methodChannel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "placeAnchor" -> {
                placeAnchorAtCenter(result)
            }
            "captureFrame" -> {
                shouldCapture = true
                captureResult = result
                val args = call.arguments as? Map<String, Any>
                captureDir = args?.get("dirPath") as? String
            }
            else -> result.notImplemented()
        }
    }

    private var pendingAnchorResult: MethodChannel.Result? = null
    private var shouldPlaceAnchor = false

    private fun placeAnchorAtCenter(result: MethodChannel.Result) {
        shouldPlaceAnchor = true
        pendingAnchorResult = result
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.1f, 0.1f, 0.1f, 1.0f)
        backgroundRenderer.createOnGlThread(context)
        objectRenderer.createOnGlThread()
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        displayRotationHelper?.onSurfaceChanged(width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        if (session == null) {
            try {
                if (ArCoreApk.getInstance().requestInstall(activity, true) == ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
                    return
                }
                session = Session(context)
                val config = Config(session)
                if (session!!.isDepthModeSupported(Config.DepthMode.RAW_DEPTH_ONLY)) {
                    config.depthMode = Config.DepthMode.RAW_DEPTH_ONLY
                } else {
                    config.depthMode = Config.DepthMode.DISABLED
                }
                config.focusMode = Config.FocusMode.AUTO
                session?.configure(config)
                session?.resume()
            } catch (e: Exception) {
                Log.e("NativeArView", "Exception creating session", e)
                return
            }
        }

        try {
            displayRotationHelper?.updateSessionIfNeeded(session!!)
            session?.setCameraTextureName(backgroundRenderer.textureId)
            val frame = session?.update() ?: return
            backgroundRenderer.draw(frame)

            val camera = frame.camera
            val projectionMatrix = FloatArray(16)
            camera.getProjectionMatrix(projectionMatrix, 0, 0.1f, 100.0f)
            val viewMatrix = FloatArray(16)
            camera.getViewMatrix(viewMatrix, 0)

            if (currentAnchor != null && !hideAnchor) {
                val anchorMatrix = FloatArray(16)
                currentAnchor!!.pose.toMatrix(anchorMatrix, 0)
                objectRenderer.draw(viewMatrix, projectionMatrix, anchorMatrix)
            }

            if (shouldPlaceAnchor) {
                handlePlaceAnchor(frame)
            }

            if (shouldCapture) {
                handleCapture(frame)
            }

        } catch (t: Throwable) {
            Log.e("NativeArView", "Exception on draw frame", t)
        }
    }

    private fun handlePlaceAnchor(frame: Frame) {
        shouldPlaceAnchor = false
        val hitResult = frame.hitTest(surfaceView.width / 2f, surfaceView.height / 2f).firstOrNull {
            val trackable = it.trackable
            trackable is Plane && trackable.isPoseInPolygon(it.hitPose)
        }

        if (hitResult != null) {
            currentAnchor?.detach()
            currentAnchor = hitResult.createAnchor()
            activity.runOnUiThread {
                pendingAnchorResult?.success(true)
                pendingAnchorResult = null
            }
        } else {
            activity.runOnUiThread {
                pendingAnchorResult?.success(false)
                pendingAnchorResult = null
            }
        }
    }

    private fun handleCapture(frame: Frame) {
        shouldCapture = false
        hideAnchor = true // Hide anchor before screenshot
        
        val result = captureResult ?: return
        captureResult = null
        val dir = captureDir

        try {
            // Force a re-render without the anchor
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
            backgroundRenderer.draw(frame)
            
            // 1. Capture Screen (RGB)
            val width = surfaceView.width
            val height = surfaceView.height
            val screenshotPath = saveScreenshot(width, height, "rgb_${System.currentTimeMillis()}.jpg", dir)

            // 2. Capture Depth
            val depthImage = frame.acquireRawDepthImage16Bits()
            val depthPath = saveDepthImage(depthImage, "depth_${System.currentTimeMillis()}.bin", dir)
            depthImage.close()

            // 3. Calculate Pose
            val poseList = ArrayList<Double>()
            if (currentAnchor != null) {
                val cameraPose = frame.camera.pose
                val anchorPose = currentAnchor!!.pose
                val relativePose = anchorPose.inverse().compose(cameraPose)
                val rawPose = FloatArray(16)
                relativePose.toMatrix(rawPose, 0)
                for (f in rawPose) poseList.add(f.toDouble())
            } else {
                for (i in 0..15) poseList.add(0.0)
            }

            val resultMap = mapOf(
                "imagePath" to screenshotPath,
                "depthPath" to depthPath,
                "relativePose" to poseList
            )

            activity.runOnUiThread {
                result.success(resultMap)
            }

        } catch (e: Exception) {
            Log.e("NativeArView", "Capture failed", e)
            activity.runOnUiThread {
                result.error("CAPTURE_FAILED", e.message, null)
            }
        } finally {
            hideAnchor = false // Show anchor again after capture
        }
    }

    private fun saveScreenshot(width: Int, height: Int, filename: String, dirPath: String?): String {
        val dir = if (dirPath != null) File(dirPath) else context.filesDir
        if (!dir.exists()) {
            dir.mkdirs()
        }
        val file = File(dir, filename)

        val size = width * height
        val buf = ByteBuffer.allocateDirect(size * 4)
        buf.order(ByteOrder.nativeOrder())
        GLES20.glReadPixels(0, 0, width, height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buf)

        val data = IntArray(size)
        buf.asIntBuffer().get(data)
        
        // Flip image vertically (OpenGL origin is bottom-left)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val tmp = IntArray(width)
        for (i in 0 until height / 2) {
            System.arraycopy(data, i * width, tmp, 0, width)
            System.arraycopy(data, (height - i - 1) * width, data, i * width, width)
            System.arraycopy(tmp, 0, data, (height - i - 1) * width, width)
        }
        bitmap.setPixels(data, 0, width, 0, 0, width, height)

        // Fix color channels: glReadPixels returns RGBA, but we need ARGB
        // Swap R and B channels
        val pixels = IntArray(size)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        for (i in pixels.indices) {
            val pixel = pixels[i]
            // RGBA to ARGB: swap red and blue
            val a = (pixel shr 24) and 0xFF
            val r = (pixel shr 16) and 0xFF
            val g = (pixel shr 8) and 0xFF
            val b = pixel and 0xFF
            pixels[i] = (a shl 24) or (b shl 16) or (g shl 8) or r
        }
        val correctedBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        correctedBitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        
        val out = FileOutputStream(file)
        correctedBitmap.compress(Bitmap.CompressFormat.JPEG, 100, out)
        out.flush()
        out.close()
        
        return file.absolutePath
    }

    private fun saveDepthImage(image: Image, filename: String, dirPath: String?): String {
        val buffer = image.planes[0].buffer
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        val dir = if (dirPath != null) File(dirPath) else context.cacheDir
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, filename)
        FileOutputStream(file).use { it.write(bytes) }
        return file.absolutePath
    }

    private fun YUV_420_888toNV21(image: Image): ByteArray {
        val width = image.width
        val height = image.height
        val ySize = width * height
        val uvSize = width * height / 4
        val nv21 = ByteArray(ySize + uvSize * 2)
        val yBuffer = image.planes[0].buffer
        val uBuffer = image.planes[1].buffer
        val vBuffer = image.planes[2].buffer
        
        yBuffer.get(nv21, 0, ySize)
        
        val vOffset = vBuffer.position()
        val uOffset = uBuffer.position()
        val vRowStride = image.planes[2].rowStride
        val vPixelStride = image.planes[2].pixelStride
        val uRowStride = image.planes[1].rowStride
        val uPixelStride = image.planes[1].pixelStride

        var pos = ySize
        for (row in 0 until height / 2) {
            for (col in 0 until width / 2) {
                nv21[pos++] = vBuffer.get(vOffset + row * vRowStride + col * vPixelStride)
                nv21[pos++] = uBuffer.get(uOffset + row * uRowStride + col * uPixelStride)
            }
        }
        return nv21
    }
}

class BackgroundRenderer {
    var textureId: Int = -1
        private set
    private var quadProgram: Int = 0
    private var quadPositionParam: Int = 0
    private var quadTexCoordParam: Int = 0
    private val quadVertices: FloatBuffer

    init {
        val QUAD_COORDS = floatArrayOf(
            -1.0f, -1.0f, 0.0f,
            -1.0f, +1.0f, 0.0f,
            +1.0f, -1.0f, 0.0f,
            +1.0f, +1.0f, 0.0f
        )
        val bb = ByteBuffer.allocateDirect(QUAD_COORDS.size * 4)
        bb.order(ByteOrder.nativeOrder())
        quadVertices = bb.asFloatBuffer()
        quadVertices.put(QUAD_COORDS)
        quadVertices.position(0)
    }

    fun createOnGlThread(context: Context) {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        textureId = textures[0]
        GLES20.glBindTexture(36197, textureId)
        GLES20.glTexParameteri(36197, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(36197, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(36197, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_NEAREST)
        GLES20.glTexParameteri(36197, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST)

        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER)
        quadProgram = GLES20.glCreateProgram()
        GLES20.glAttachShader(quadProgram, vertexShader)
        GLES20.glAttachShader(quadProgram, fragmentShader)
        GLES20.glLinkProgram(quadProgram)
        GLES20.glUseProgram(quadProgram)
        quadPositionParam = GLES20.glGetAttribLocation(quadProgram, "a_Position")
        quadTexCoordParam = GLES20.glGetAttribLocation(quadProgram, "a_TexCoord")
    }

    fun draw(frame: Frame) {
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(false)
        GLES20.glBindTexture(36197, textureId)
        GLES20.glUseProgram(quadProgram)
        
        val QUAD_COORDS = floatArrayOf(-1f, -1f, 0f, -1f, 1f, 0f, 1f, -1f, 0f, 1f, 1f, 0f)
        quadVertices.put(QUAD_COORDS).position(0)
        GLES20.glVertexAttribPointer(quadPositionParam, 3, GLES20.GL_FLOAT, false, 0, quadVertices)
        GLES20.glEnableVertexAttribArray(quadPositionParam)

        val QUAD_TEXCOORDS = floatArrayOf(0f, 1f, 0f, 0f, 1f, 1f, 1f, 0f)
        val uvBuffer = ByteBuffer.allocateDirect(32).order(ByteOrder.nativeOrder()).asFloatBuffer()
        uvBuffer.put(QUAD_TEXCOORDS).position(0)
        frame.transformDisplayUvCoords(uvBuffer, uvBuffer)
        GLES20.glVertexAttribPointer(quadTexCoordParam, 2, GLES20.GL_FLOAT, false, 0, uvBuffer)
        GLES20.glEnableVertexAttribArray(quadTexCoordParam)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDepthMask(true)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
    }

    private fun loadShader(type: Int, shaderCode: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, shaderCode)
        GLES20.glCompileShader(shader)
        return shader
    }

    companion object {
        private const val VERTEX_SHADER =
            "attribute vec4 a_Position;\n" +
            "attribute vec2 a_TexCoord;\n" +
            "varying vec2 v_TexCoord;\n" +
            "void main() {\n" +
            "   gl_Position = a_Position;\n" +
            "   v_TexCoord = a_TexCoord;\n" +
            "}"
        private const val FRAGMENT_SHADER =
            "#extension GL_OES_EGL_image_external : require\n" +
            "precision mediump float;\n" +
            "varying vec2 v_TexCoord;\n" +
            "uniform samplerExternalOES s_Texture;\n" +
            "void main() {\n" +
            "    gl_FragColor = texture2D(s_Texture, v_TexCoord);\n" +
            "}"
    }
}

class DisplayRotationHelper(private val context: Context) : DisplayManager.DisplayListener {
    private val displayManager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var viewportWidth = 0
    private var viewportHeight = 0
    private var viewportChanged = false

    init {
        displayManager.registerDisplayListener(this, null)
    }

    fun onSurfaceChanged(width: Int, height: Int) {
        viewportWidth = width
        viewportHeight = height
        viewportChanged = true
    }

    fun updateSessionIfNeeded(session: Session) {
        if (viewportChanged) {
            val display = windowManager.defaultDisplay
            val rotation = display.rotation
            session.setDisplayGeometry(rotation, viewportWidth, viewportHeight)
            viewportChanged = false
        }
    }

    val rotation: Int
        get() = windowManager.defaultDisplay.rotation

    override fun onDisplayAdded(displayId: Int) {}
    override fun onDisplayRemoved(displayId: Int) {}
    override fun onDisplayChanged(displayId: Int) {
        viewportChanged = true
    }
}

class SimpleObjectRenderer {
    private var program: Int = 0
    private var positionParam: Int = 0
    private var mvpMatrixParam: Int = 0
    private var colorParam: Int = 0
    private val vertexBuffer: FloatBuffer
    private val indexBuffer: ByteBuffer

    // Simple box vertices (x, y, z)
    // 1cm x 20cm x 1cm stick standing on the anchor
    private val VERTICES = floatArrayOf(
        // Bottom vertices
        -0.005f, 0.0f, -0.005f,
         0.005f, 0.0f, -0.005f,
         0.005f, 0.0f,  0.005f,
        -0.005f, 0.0f,  0.005f,
        // Top vertices
        -0.005f, 0.2f, -0.005f,
         0.005f, 0.2f, -0.005f,
         0.005f, 0.2f,  0.005f,
        -0.005f, 0.2f,  0.005f
    )

    private val INDICES = byteArrayOf(
        0, 1, 2, 0, 2, 3, // Bottom
        4, 5, 6, 4, 6, 7, // Top
        0, 1, 5, 0, 5, 4, // Front
        1, 2, 6, 1, 6, 5, // Right
        2, 3, 7, 2, 7, 6, // Back
        3, 0, 4, 3, 4, 7  // Left
    )

    init {
        val vbb = ByteBuffer.allocateDirect(VERTICES.size * 4)
        vbb.order(ByteOrder.nativeOrder())
        vertexBuffer = vbb.asFloatBuffer()
        vertexBuffer.put(VERTICES)
        vertexBuffer.position(0)

        indexBuffer = ByteBuffer.allocateDirect(INDICES.size)
        indexBuffer.put(INDICES)
        indexBuffer.position(0)
    }

    fun createOnGlThread() {
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER)
        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)
        
        positionParam = GLES20.glGetAttribLocation(program, "a_Position")
        mvpMatrixParam = GLES20.glGetUniformLocation(program, "u_MVP")
        colorParam = GLES20.glGetUniformLocation(program, "u_Color")
    }

    fun draw(viewMatrix: FloatArray, projectionMatrix: FloatArray, modelMatrix: FloatArray) {
        GLES20.glUseProgram(program)

        val mvpMatrix = FloatArray(16)
        val vpMatrix = FloatArray(16)
        android.opengl.Matrix.multiplyMM(vpMatrix, 0, projectionMatrix, 0, viewMatrix, 0)
        android.opengl.Matrix.multiplyMM(mvpMatrix, 0, vpMatrix, 0, modelMatrix, 0)

        GLES20.glUniformMatrix4fv(mvpMatrixParam, 1, false, mvpMatrix, 0)
        
        // Green color
        GLES20.glUniform4f(colorParam, 0.0f, 1.0f, 0.0f, 1.0f)

        GLES20.glVertexAttribPointer(positionParam, 3, GLES20.GL_FLOAT, false, 0, vertexBuffer)
        GLES20.glEnableVertexAttribArray(positionParam)

        GLES20.glDrawElements(GLES20.GL_TRIANGLES, INDICES.size, GLES20.GL_UNSIGNED_BYTE, indexBuffer)
        
        GLES20.glDisableVertexAttribArray(positionParam)
    }

    private fun loadShader(type: Int, shaderCode: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, shaderCode)
        GLES20.glCompileShader(shader)
        return shader
    }

    companion object {
        private const val VERTEX_SHADER =
            "uniform mat4 u_MVP;" +
            "attribute vec4 a_Position;" +
            "void main() {" +
            "  gl_Position = u_MVP * a_Position;" +
            "}"
        private const val FRAGMENT_SHADER =
            "precision mediump float;" +
            "uniform vec4 u_Color;" +
            "void main() {" +
            "  gl_FragColor = u_Color;" +
            "}"
    }
}

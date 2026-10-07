package com.noaisu.loliSnatcher

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import `is`.xyz.mpv.MPVLib
import `is`.xyz.mpv.MPVNode

/**
 * One mpvlib player for the process. A newer open replaces the older one.
 * Options are set before init. Volume is mpv's 0–100 property, not the
 * device stream.
 */
class MpvlibSession(
    private val activity: Activity,
    private val engine: FlutterEngine,
    override val requestId: Int,
    private val url: String,
    private val headers: Map<String, String>,
    private val gpuApi: String,
) : VideoEngineBridge.Session, MPVLib.EventObserver {
    private val main = Handler(Looper.getMainLooper())
    private var entry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var openResult: MethodChannel.Result? = null
    private var released = false
    private var loaded = false
    override var textureId: Long = -1
    private var width = 0
    private var height = 0
    private var ended = false

    private val tick = object : Runnable {
        override fun run() {
            if (released || !loaded) return
            readSize()
            publish(null)
            main.postDelayed(this, 200)
        }
    }

    fun start(result: MethodChannel.Result) {
        VideoEngineBridge.sessionsSnapshot().filterIsInstance<MpvlibSession>().forEach { it.release() }
        openResult = result
        try {
            val created = engine.renderer.createSurfaceTexture()
            entry = created
            textureId = created.id()
            val texture = created.surfaceTexture()
            texture.setDefaultBufferSize(16, 16)
            val videoSurface = Surface(texture)
            surface = videoSurface
            VideoEngineBridge.add(this)
            MPVLib.addObserver(this)
            MPVLib.create(activity.applicationContext)
            MPVLib.setOptionString("vo", "gpu")
            MPVLib.setOptionString("gpu-api", gpuApi)
            MPVLib.setOptionString("hwdec", "auto-safe")
            MPVLib.setOptionString("pause", "yes")
            MPVLib.setOptionString("keep-open", "yes")
            MPVLib.setOptionString("force-window", "yes")
            val headerList = headers.entries.joinToString(",") { (key, value) ->
                "$key: ${value.replace(",", " ")}"
            }
            if (headerList.isNotEmpty()) {
                MPVLib.setOptionString("http-header-fields", headerList)
            }
            MPVLib.init()
            MPVLib.attachSurface(videoSurface)
            MPVLib.command("loadfile", url, "replace")
            Log.i(TAG, "video-engine: mpv loadfile gpu-api=$gpuApi")
        } catch (error: Throwable) {
            Log.e(TAG, "video-engine: mpv open failed", error)
            val pending = openResult
            openResult = null
            pending?.error("video-engine", error.message ?: "mpv open failed", null)
            release()
        }
    }

    override fun eventProperty(property: String) {}

    override fun eventProperty(property: String, value: Long) {}

    override fun eventProperty(property: String, value: Boolean) {}

    override fun eventProperty(property: String, value: String) {}

    override fun eventProperty(property: String, value: Double) {}

    override fun eventProperty(property: String, value: MPVNode) {}

    override fun event(eventId: Int, data: MPVNode) {
        main.post {
            if (released) return@post
            when (eventId) {
                MPVLib.MpvEvent.MPV_EVENT_FILE_LOADED -> onFileLoaded()
                MPVLib.MpvEvent.MPV_EVENT_END_FILE -> {
                    ended = true
                    publish(null)
                }
            }
        }
    }

    private fun onFileLoaded() {
        if (loaded || released) return
        loaded = true
        ended = false
        readSize()
        val pending = openResult
        openResult = null
        pending?.success(snapshot(null) + mapOf("textureId" to textureId.toInt()))
        main.post(tick)
        Log.i(TAG, "video-engine: mpv file loaded ${width}x$height")
    }

    private fun readSize() {
        val nextWidth = MPVLib.getPropertyInt("dwidth") ?: MPVLib.getPropertyInt("width") ?: 0
        val nextHeight = MPVLib.getPropertyInt("dheight") ?: MPVLib.getPropertyInt("height") ?: 0
        if (nextWidth > 0 && nextHeight > 0 && (nextWidth != width || nextHeight != height)) {
            width = nextWidth
            height = nextHeight
            entry?.surfaceTexture()?.setDefaultBufferSize(nextWidth, nextHeight)
        }
    }

    private fun publish(error: String?) {
        if (released || textureId < 0 || openResult != null) return
        VideoEngineBridge.emit(textureId, snapshot(error))
    }

    private fun snapshot(error: String?): Map<String, Any?> {
        val durationSec = MPVLib.getPropertyDouble("duration") ?: 0.0
        val positionSec = MPVLib.getPropertyDouble("time-pos") ?: 0.0
        val cacheSec = MPVLib.getPropertyDouble("demuxer-cache-time") ?: 0.0
        val paused = MPVLib.getPropertyBoolean("pause") ?: true
        val fields = hashMapOf<String, Any?>(
            "durationMs" to (durationSec * 1000.0).toLong().coerceAtLeast(0L),
            "positionMs" to (positionSec * 1000.0).toLong().coerceAtLeast(0L),
            "bufferedMs" to ((positionSec + cacheSec) * 1000.0).toLong().coerceAtLeast(0L),
            "width" to width,
            "height" to height,
            "buffering" to !loaded,
            "playing" to (loaded && !paused && !ended),
            "ended" to ended,
        )
        if (!error.isNullOrEmpty()) fields["error"] = error
        return fields
    }

    override fun play() {
        ended = false
        MPVLib.setPropertyBoolean("pause", false)
    }

    override fun pause() {
        MPVLib.setPropertyBoolean("pause", true)
    }

    override fun seek(positionMs: Long) {
        ended = false
        val seconds = positionMs.coerceAtLeast(0L) / 1000.0
        MPVLib.command("seek", seconds.toString(), "absolute")
    }

    override fun setVolume(volume: Double) {
        MPVLib.setPropertyDouble("volume", (volume * 100.0).coerceIn(0.0, 100.0))
    }

    override fun setSpeed(speed: Double) {
        if (speed > 0) MPVLib.setPropertyDouble("speed", speed)
    }

    override fun setLooping(loop: Boolean) {
        MPVLib.setPropertyString("loop-file", if (loop) "inf" else "no")
    }

    override fun release() {
        if (released) return
        released = true
        main.removeCallbacks(tick)
        val pending = openResult
        openResult = null
        pending?.error("video-engine", "disposed", null)
        try {
            MPVLib.removeObserver(this)
        } catch (_: Throwable) {
        }
        try {
            MPVLib.command("stop")
        } catch (_: Throwable) {
        }
        try {
            MPVLib.detachSurface()
        } catch (_: Throwable) {
        }
        try {
            MPVLib.destroy()
        } catch (_: Throwable) {
        }
        surface?.release()
        surface = null
        entry?.release()
        entry = null
        VideoEngineBridge.remove(this)
    }

    companion object {
        private const val TAG = "video-engine"
    }
}

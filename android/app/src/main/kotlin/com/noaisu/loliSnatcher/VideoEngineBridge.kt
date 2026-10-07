package com.noaisu.loliSnatcher

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Media3 and mpvlib behind the same method channel. The picture is a Flutter
 * texture, so the viewer's pinch zoom still transforms it. Device volume is
 * not touched; player volume stays the 0–1 value the buttons already send.
 */
object VideoEngineBridge {
    private const val TAG = "video-engine"
    private const val CHANNEL = "com.noaisu.loliSnatcher/video_engine"
    private const val EVENTS = "com.noaisu.loliSnatcher/video_engine_events"

    private val main = Handler(Looper.getMainLooper())
    private val sessions = LinkedHashMap<Int, Session>()
    private var sink: EventChannel.EventSink? = null

    interface Session {
        val requestId: Int
        val textureId: Long
        fun play()
        fun pause()
        fun seek(positionMs: Long)
        fun setVolume(volume: Double)
        fun setSpeed(speed: Double)
        fun setLooping(loop: Boolean)
        fun release()
    }

    fun install(activity: Activity, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "setMpvlibVariant" -> {
                        MpvlibPreloadProvider.writeVariant(
                            activity.applicationContext,
                            call.argument<String>("variant") ?: "off",
                        )
                        result.success(null)
                    }
                    "loadedVariant" -> result.success(MpvlibPreloadProvider.loadedVariant)
                    "open" -> open(activity, engine, call, result)
                    "play" -> {
                        find(call)?.play()
                        result.success(null)
                    }
                    "pause" -> {
                        find(call)?.pause()
                        result.success(null)
                    }
                    "seek" -> {
                        find(call)?.seek(number(call, "positionMs")?.toLong() ?: 0L)
                        result.success(null)
                    }
                    "setVolume" -> {
                        find(call)?.setVolume(number(call, "volume")?.toDouble() ?: 0.0)
                        result.success(null)
                    }
                    "setSpeed" -> {
                        find(call)?.setSpeed(number(call, "speed")?.toDouble() ?: 1.0)
                        result.success(null)
                    }
                    "setLooping" -> {
                        find(call)?.setLooping(call.argument<Boolean>("loop") ?: false)
                        result.success(null)
                    }
                    "dispose" -> {
                        find(call)?.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                Log.e(TAG, "video-engine: ${call.method} failed", error)
                result.error("video-engine", error.message, null)
            }
        }
        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
    }

    fun add(session: Session) {
        sessions[session.requestId] = session
    }

    fun sessionsSnapshot(): List<Session> = sessions.values.toList()

    fun remove(session: Session) {
        if (sessions[session.requestId] === session) {
            sessions.remove(session.requestId)
        }
    }

    fun emit(textureId: Long, fields: Map<String, Any?>) {
        val target = sink ?: return
        val payload = HashMap<String, Any?>(fields)
        payload["textureId"] = textureId.toInt()
        main.post { sink?.success(payload) }
    }

    private fun open(activity: Activity, engine: FlutterEngine, call: MethodCall, result: MethodChannel.Result) {
        val requestId = number(call, "requestId")?.toInt()
        val url = call.argument<String>("url")
        val engineName = call.argument<String>("engine") ?: ""
        if (requestId == null || url.isNullOrBlank()) {
            result.error("video-engine", "missing url or requestId", null)
            return
        }
        Log.i(TAG, "video-engine: open $engineName $url")
        when (engineName) {
            "media3" -> Media3Session(activity, engine, requestId, url, stringMap(call, "headers")).start(result)
            "mpvlibVulkan", "mpvlibOpengl" -> openMpv(activity, engine, requestId, url, stringMap(call, "headers"), result)
            else -> result.error("video-engine", "unknown engine $engineName", null)
        }
    }

    private fun openMpv(
        activity: Activity,
        engine: FlutterEngine,
        requestId: Int,
        url: String,
        headers: Map<String, String>,
        result: MethodChannel.Result,
    ) {
        val loaded = MpvlibPreloadProvider.loadedVariant
        if (loaded != "vulkan" && loaded != "opengl") {
            result.error("video-engine", "Restart the app to switch the mpvlib build", null)
            return
        }
        MpvlibSession(activity, engine, requestId, url, headers, loaded).start(result)
    }

    private fun find(call: MethodCall): Session? {
        val texture = number(call, "textureId")?.toLong()
        val request = number(call, "requestId")?.toInt()
        if (texture != null) {
            sessions.values.firstOrNull { it.textureId == texture }?.let { return it }
        }
        if (request != null) return sessions[request]
        return null
    }

    private fun number(call: MethodCall, name: String): Number? = call.argument<Any>(name) as? Number

    private fun stringMap(call: MethodCall, name: String): Map<String, String> {
        val raw = call.argument<Any>(name) as? Map<*, *> ?: return emptyMap()
        val out = LinkedHashMap<String, String>()
        for ((key, value) in raw) {
            if (key is String && value is String && key.isNotBlank()) out[key] = value
        }
        return out
    }
}

private class Media3Session(
    private val activity: Activity,
    private val engine: FlutterEngine,
    override val requestId: Int,
    private val url: String,
    private val headers: Map<String, String>,
) : VideoEngineBridge.Session {
    private val main = Handler(Looper.getMainLooper())
    private var player: ExoPlayer? = null
    private var entry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var openResult: MethodChannel.Result? = null
    private var released = false
    override var textureId: Long = -1
    private var width = 0
    private var height = 0

    private val tick = object : Runnable {
        override fun run() {
            if (released) return
            publish(null)
            main.postDelayed(this, 200)
        }
    }

    fun start(result: MethodChannel.Result) {
        openResult = result
        try {
            startPlayer()
        } catch (error: Throwable) {
            Log.e("video-engine", "video-engine: media3 open failed", error)
            val pending = openResult
            openResult = null
            pending?.error("video-engine", error.message ?: "media3 open failed", null)
            release()
        }
    }

    private fun startPlayer() {
        val created = engine.renderer.createSurfaceTexture()
        entry = created
        textureId = created.id()
        val texture = created.surfaceTexture()
        texture.setDefaultBufferSize(16, 16)
        val videoSurface = Surface(texture)
        surface = videoSurface
        VideoEngineBridge.add(this)

        val userAgent = headers.entries.firstOrNull { it.key.equals("User-Agent", true) }?.value
            ?: "LoliSnatcher_Droid/1.0.0"
        val requestHeaders = headers.filterKeys { !it.equals("User-Agent", true) }
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setDefaultRequestProperties(requestHeaders)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(20_000)
            .setReadTimeoutMs(20_000)
        val dataSource = DefaultDataSource.Factory(activity.applicationContext, http)
        val exo = ExoPlayer.Builder(activity.applicationContext)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSource))
            .setLooper(Looper.getMainLooper())
            .build()
        player = exo
        exo.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            false,
        )
        exo.setVideoSurface(videoSurface)
        exo.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY) succeed()
                publish(null)
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e("video-engine", "video-engine: media3 ${error.errorCodeName} ${error.message}")
                val pending = openResult
                if (pending != null) {
                    openResult = null
                    pending.error("video-engine", error.message ?: error.errorCodeName, null)
                    release()
                } else {
                    publish(error.message ?: error.errorCodeName)
                }
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    width = videoSize.width
                    height = videoSize.height
                    texture.setDefaultBufferSize(videoSize.width, videoSize.height)
                }
                publish(null)
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                publish(null)
            }
        })
        exo.setMediaItem(MediaItem.fromUri(url))
        exo.prepare()
    }

    private fun succeed() {
        val pending = openResult ?: return
        openResult = null
        pending.success(snapshot(null) + mapOf("textureId" to textureId.toInt()))
        main.post(tick)
    }

    private fun publish(error: String?) {
        if (released || textureId < 0 || openResult != null) return
        VideoEngineBridge.emit(textureId, snapshot(error))
    }

    private fun snapshot(error: String?): Map<String, Any?> {
        val exo = player
        val duration = exo?.duration ?: 0L
        val fields = hashMapOf<String, Any?>(
            "durationMs" to if (duration < 0) 0 else duration,
            "positionMs" to (exo?.currentPosition ?: 0L).coerceAtLeast(0L),
            "bufferedMs" to (exo?.bufferedPosition ?: 0L).coerceAtLeast(0L),
            "width" to width,
            "height" to height,
            "buffering" to (exo?.playbackState == Player.STATE_BUFFERING),
            "playing" to (exo?.isPlaying == true),
            "ended" to (exo?.playbackState == Player.STATE_ENDED),
        )
        if (!error.isNullOrEmpty()) fields["error"] = error
        return fields
    }

    override fun play() {
        player?.play()
    }

    override fun pause() {
        player?.pause()
    }

    override fun seek(positionMs: Long) {
        player?.seekTo(positionMs.coerceAtLeast(0L))
    }

    override fun setVolume(volume: Double) {
        player?.volume = volume.toFloat().coerceIn(0f, 1f)
    }

    override fun setSpeed(speed: Double) {
        if (speed > 0) player?.setPlaybackSpeed(speed.toFloat())
    }

    override fun setLooping(loop: Boolean) {
        player?.repeatMode = if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
    }

    override fun release() {
        if (released) return
        released = true
        main.removeCallbacks(tick)
        val pending = openResult
        openResult = null
        pending?.error("video-engine", "disposed", null)
        player?.setVideoSurface(null)
        player?.release()
        player = null
        surface?.release()
        surface = null
        entry?.release()
        entry = null
        VideoEngineBridge.remove(this)
    }
}

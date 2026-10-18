package com.example.nontontv_flutter.player

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.View
import android.view.ViewGroup
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.DrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.drm.MediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultAllocator
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.UUID
import kotlin.math.max
import kotlin.random.Random

@OptIn(UnstableApi::class)
class NontonTvPlayerView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int
) : PlatformView, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        // Mirrors NontonTV v2.4 custom prebuffer values.
        private const val MIN_BUFFER_MS = 32 * 1024
        private const val MAX_BUFFER_MS = 64 * 1024
        private const val BUFFER_FOR_PLAYBACK_MS = 1024
        private const val BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS = 1024
        private const val RETRY_DELAY_MS = 3000L

        private val RANDOM_USER_AGENTS = listOf(
            "Mozilla/5.0 (Linux; Android 13; Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Linux; Android 12; TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Linux; Android 11; AFTSSS) AppleWebKit/537.36 (KHTML, like Gecko) Silk/112.3.1 like Chrome/112.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
            "VLC/3.0.21 LibVLC/3.0.21",
            "ExoPlayerLib/2.19.1"
        )
    }

    private data class OpenRequest(
        val url: String,
        val headers: Map<String, String>,
        val optimizePrebuffer: Boolean,
        val randomUserAgent: Boolean,
        val drmType: String?,
        val drmKey: String?
    )

    private val methodChannel = MethodChannel(messenger, "nontontv/player/$viewId/methods")
    private val eventChannel = EventChannel(messenger, "nontontv/player/$viewId/events")
    private val handler = Handler(Looper.getMainLooper())

    private val playerView = PlayerView(context).apply {
        useController = false
        setKeepContentOnPlayerReset(true)
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        isFocusable = false
        isFocusableInTouchMode = false
        descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
        keepScreenOn = true
        setShutterBackgroundColor(android.graphics.Color.BLACK)
    }

    private var eventSink: EventChannel.EventSink? = null
    private var player: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null
    private var optimizePrebuffer: Boolean? = null
    private var lastRequest: OpenRequest? = null
    private var currentError: String? = null
    private var currentWarning: String? = null
    private var generation = 0L

    private val retryRunnable = Runnable {
        val request = lastRequest ?: return@Runnable
        openInternal(request, isRetry = true)
    }

    private val progressRunnable = object : Runnable {
        override fun run() {
            emitState()
            handler.postDelayed(this, 1000L)
        }
    }

    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            when (playbackState) {
                Player.STATE_READY -> currentError = null
                Player.STATE_ENDED -> scheduleRetry()
            }
            emitState()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            emitState()
        }

        override fun onPlayerError(error: PlaybackException) {
            currentError = "${error.errorCodeName}: ${error.message ?: "Playback error"}"
            emit(mapOf("event" to "error", "message" to currentError))
            emitState()
            scheduleRetry()
        }

        override fun onTracksChanged(tracks: Tracks) {
            currentWarning = audioSupportWarning(tracks)
            if (currentWarning != null) {
                emit(mapOf("event" to "warning", "message" to currentWarning))
            }
            emit(mapOf("event" to "tracks", "tracks" to serializeTracks(tracks)))
            emitState()
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        handler.post(progressRunnable)
    }

    override fun getView(): View = playerView

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emitState()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "open" -> {
                    val url = call.argument<String>("url")?.trim().orEmpty()
                    if (url.isEmpty()) {
                        result.error("bad_url", "URL stream kosong.", null)
                        return
                    }
                    @Suppress("UNCHECKED_CAST")
                    val rawHeaders = call.argument<Map<String, Any?>>("headers") ?: emptyMap()
                    val headers = rawHeaders.mapValues { (_, value) -> value?.toString().orEmpty() }
                        .filterValues { it.isNotEmpty() }
                    val request = OpenRequest(
                        url = url,
                        headers = headers,
                        optimizePrebuffer = call.argument<Boolean>("optimizePrebuffer") ?: true,
                        randomUserAgent = call.argument<Boolean>("randomUserAgent") ?: true,
                        drmType = call.argument<String>("drmType")?.trim()?.takeIf { it.isNotEmpty() },
                        drmKey = call.argument<String>("drmKey")?.trim()?.takeIf { it.isNotEmpty() }
                    )
                    generation++
                    lastRequest = request
                    openInternal(request, isRetry = false)
                    result.success(null)
                }

                "play" -> {
                    player?.play()
                    result.success(null)
                }

                "pause" -> {
                    player?.pause()
                    result.success(null)
                }

                "playOrPause" -> {
                    player?.let { if (it.isPlaying) it.pause() else it.play() }
                    result.success(null)
                }

                "seek" -> {
                    val target = call.argument<Number>("positionMs")?.toLong() ?: 0L
                    player?.seekTo(max(0L, target))
                    result.success(null)
                }

                "setResizeMode" -> {
                    setResizeMode(call.argument<String>("mode") ?: "fit")
                    result.success(null)
                }

                "selectTrack" -> {
                    selectTrack(
                        typeName = call.argument<String>("type") ?: "video",
                        groupIndex = call.argument<Number>("groupIndex")?.toInt() ?: -1,
                        trackIndex = call.argument<Number>("trackIndex")?.toInt() ?: -1
                    )
                    result.success(null)
                }

                "selectAuto" -> {
                    selectAuto(call.argument<String>("type") ?: "video")
                    result.success(null)
                }

                "disableTrack" -> {
                    disableTrack(call.argument<String>("type") ?: "text")
                    result.success(null)
                }

                "getState" -> result.success(stateMap())

                "release" -> {
                    releasePlayer()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("player_error", error.message, error.stackTraceToString())
        }
    }

    private fun ensurePlayer(useOptimizedPrebuffer: Boolean): ExoPlayer {
        val current = player
        if (current != null && optimizePrebuffer == useOptimizedPrebuffer) return current

        releasePlayer(keepRequest = true)
        optimizePrebuffer = useOptimizedPrebuffer

        // NontonTV patch: enable extension renderers. Media3 will discover FFmpeg when its
        // decoder AAR is packaged. EXTENSION_RENDERER_MODE_ON keeps platform decoders preferred.
        val renderersFactory = DefaultRenderersFactory(context)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)

        val selector = DefaultTrackSelector(context)
        val builder = ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(selector)

        if (useOptimizedPrebuffer) {
            // Direct port of NontonTV's custom LoadControl values.
            val loadControl = DefaultLoadControl.Builder()
                .setAllocator(DefaultAllocator(true, 16))
                .setBufferDurationsMs(
                    MIN_BUFFER_MS,
                    MAX_BUFFER_MS,
                    BUFFER_FOR_PLAYBACK_MS,
                    BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS
                )
                .setTargetBufferBytes(C.LENGTH_UNSET)
                .setPrioritizeTimeOverSizeThresholds(true)
                .build()
            builder.setLoadControl(loadControl)
        }

        val built = builder.build()
        built.addListener(listener)
        built.playWhenReady = true
        player = built
        trackSelector = selector
        playerView.player = built
        return built
    }

    private fun openInternal(request: OpenRequest, isRetry: Boolean) {
        handler.removeCallbacks(retryRunnable)
        currentError = null
        currentWarning = null
        val exoPlayer = ensurePlayer(request.optimizePrebuffer)

        val headers = LinkedHashMap(request.headers)
        if (headers.keys.none { it.equals("User-Agent", ignoreCase = true) } && request.randomUserAgent) {
            headers["User-Agent"] = RANDOM_USER_AGENTS[Random.nextInt(RANDOM_USER_AGENTS.size)]
        }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)
            .setDefaultRequestProperties(headers)

        val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
        val drmSessionManager = buildDrmSessionManager(request, httpFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory).apply {
            if (drmSessionManager != null) {
                // Media3 replacement for legacy NontonTV setDrmSessionManager(...).
                setDrmSessionManagerProvider { drmSessionManager }
            }
        }
        val mediaItem = MediaItem.fromUri(request.url)
        val mediaSource = mediaSourceFactory.createMediaSource(mediaItem)

        exoPlayer.stop()
        exoPlayer.clearMediaItems()
        exoPlayer.setMediaSource(mediaSource)
        exoPlayer.prepare()
        exoPlayer.play()
        if (!isRetry) emitState()
    }

    private fun buildDrmSessionManager(
        request: OpenRequest,
        httpFactory: DefaultHttpDataSource.Factory
    ): DrmSessionManager? {
        val type = request.drmType ?: return null
        val key = request.drmKey ?: return null
        val uuid = drmUuid(type)
            ?: throw IllegalArgumentException("Tipe DRM tidak didukung: $type")

        if (!FrameworkMediaDrm.isCryptoSchemeSupported(uuid)) {
            throw IllegalStateException("Perangkat ini tidak mendukung DRM ${type.uppercase()}.")
        }

        // Same behavior as original NontonTV:
        // - URL key => online license request (Widevine/PlayReady/ClearKey server)
        // - non-URL key => local ClearKey in KID:KEY hex form.
        val callback: MediaDrmCallback = if (isHttpUrl(key)) {
            HttpMediaDrmCallback(key, httpFactory)
        } else {
            if (uuid != C.CLEARKEY_UUID) {
                throw IllegalArgumentException(
                    "DRM ${type.uppercase()} membutuhkan URL license server. " +
                        "Key lokal KID:KEY hanya didukung untuk ClearKey."
                )
            }
            LocalMediaDrmCallback(clearKeyResponse(key))
        }

        return DefaultDrmSessionManager.Builder()
            .setUuidAndExoMediaDrmProvider(uuid, FrameworkMediaDrm.DEFAULT_PROVIDER)
            // Preserve NontonTV behavior: multi-session for Widevine/PlayReady,
            // single session for ClearKey.
            .setMultiSession(uuid != C.CLEARKEY_UUID)
            .build(callback)
    }

    private fun drmUuid(type: String): UUID? {
        val value = type.lowercase()
        return when {
            value.contains("clearkey") -> C.CLEARKEY_UUID
            value.contains("widevine") -> C.WIDEVINE_UUID
            value.contains("playready") -> C.PLAYREADY_UUID
            else -> null
        }
    }

    private fun isHttpUrl(value: String): Boolean {
        return value.startsWith("http://", ignoreCase = true) ||
            value.startsWith("https://", ignoreCase = true)
    }

    private fun clearKeyResponse(value: String): ByteArray {
        val separator = value.indexOf(':')
        require(separator > 0 && separator < value.length - 1) {
            "Format ClearKey harus KID_HEX:KEY_HEX seperti NontonTV."
        }
        val kid = hexToBytes(value.substring(0, separator))
        val key = hexToBytes(value.substring(separator + 1))
        val kid64 = Base64.encodeToString(kid, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        val key64 = Base64.encodeToString(key, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        return """{"keys":[{"kty":"oct","k":"$key64","kid":"$kid64"}],"type":"temporary"}"""
            .toByteArray(Charsets.UTF_8)
    }

    private fun hexToBytes(value: String): ByteArray {
        val clean = value.trim()
        require(clean.length % 2 == 0 && clean.matches(Regex("[0-9a-fA-F]+"))) {
            "KID/KEY ClearKey harus berupa HEX dengan panjang genap."
        }
        return ByteArray(clean.length / 2) { index ->
            clean.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }

    private fun scheduleRetry() {
        handler.removeCallbacks(retryRunnable)
        if (lastRequest != null) handler.postDelayed(retryRunnable, RETRY_DELAY_MS)
    }

    private fun setResizeMode(mode: String) {
        playerView.resizeMode = when (mode) {
            "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            "zoom" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            "fixedWidth" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH
            "fixedHeight" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_HEIGHT
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
    }

    private fun trackType(typeName: String): Int = when (typeName) {
        "audio" -> C.TRACK_TYPE_AUDIO
        "text" -> C.TRACK_TYPE_TEXT
        else -> C.TRACK_TYPE_VIDEO
    }

    private fun selectTrack(typeName: String, groupIndex: Int, trackIndex: Int) {
        val exoPlayer = player ?: return
        val type = trackType(typeName)
        val groups = exoPlayer.currentTracks.groups
        if (groupIndex !in groups.indices) return
        val group = groups[groupIndex]
        if (group.type != type || trackIndex !in 0 until group.length) return

        exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(type, false)
            .clearOverridesOfType(type)
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, trackIndex))
            .build()
    }

    private fun selectAuto(typeName: String) {
        val exoPlayer = player ?: return
        val type = trackType(typeName)
        exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(type, false)
            .clearOverridesOfType(type)
            .build()
    }

    private fun disableTrack(typeName: String) {
        val exoPlayer = player ?: return
        val type = trackType(typeName)
        exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters
            .buildUpon()
            .clearOverridesOfType(type)
            .setTrackTypeDisabled(type, true)
            .build()
    }

    private fun serializeTracks(tracks: Tracks): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        tracks.groups.forEachIndexed { groupIndex, group ->
            val typeName = when (group.type) {
                C.TRACK_TYPE_AUDIO -> "audio"
                C.TRACK_TYPE_TEXT -> "text"
                C.TRACK_TYPE_VIDEO -> "video"
                else -> null
            } ?: return@forEachIndexed

            for (trackIndex in 0 until group.length) {
                val format = group.getTrackFormat(trackIndex)
                val label = when {
                    !format.label.isNullOrBlank() -> format.label!!
                    !format.language.isNullOrBlank() -> format.language!!
                    format.height > 0 -> "${format.height}p"
                    else -> "Track ${trackIndex + 1}"
                }
                out += mapOf(
                    "type" to typeName,
                    "groupIndex" to groupIndex,
                    "trackIndex" to trackIndex,
                    "label" to label,
                    "selected" to group.isTrackSelected(trackIndex),
                    "supported" to group.isTrackSupported(trackIndex),
                    "language" to format.language,
                    "codecs" to format.codecs,
                    "width" to format.width.takeIf { it > 0 },
                    "height" to format.height.takeIf { it > 0 },
                    "frameRate" to format.frameRate.takeIf { it > 0f }?.toDouble(),
                    "bitrate" to format.bitrate.takeIf { it > 0 },
                    "channelCount" to format.channelCount.takeIf { it > 0 },
                    "sampleRate" to format.sampleRate.takeIf { it > 0 }
                )
            }
        }
        return out
    }

    private fun audioSupportWarning(tracks: Tracks): String? {
        val audioGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        if (audioGroups.isEmpty()) return null
        val hasSupportedAudio = audioGroups.any { group ->
            (0 until group.length).any { index -> group.isTrackSupported(index) }
        }
        // NontonTV patch: unsupported audio is a warning only; video playback continues.
        return if (hasSupportedAudio) null else "Format audio tidak didukung; video tetap diputar tanpa audio."
    }

    private fun stateMap(): Map<String, Any?> {
        val exoPlayer = player
        return mapOf(
            "event" to "state",
            "playing" to (exoPlayer?.isPlaying ?: false),
            "buffering" to (exoPlayer?.playbackState == Player.STATE_BUFFERING),
            "positionMs" to (exoPlayer?.currentPosition ?: 0L),
            "durationMs" to ((exoPlayer?.duration ?: 0L).takeIf { it != C.TIME_UNSET } ?: 0L),
            "error" to currentError,
            "warning" to currentWarning,
            "tracks" to (exoPlayer?.currentTracks?.let(::serializeTracks) ?: emptyList<Map<String, Any?>>())
        )
    }

    private fun emitState() {
        emit(stateMap())
    }

    private fun emit(value: Any?) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            eventSink?.success(value)
        } else {
            handler.post { eventSink?.success(value) }
        }
    }

    private fun releasePlayer(keepRequest: Boolean = false) {
        handler.removeCallbacks(retryRunnable)
        playerView.player = null
        player?.removeListener(listener)
        player?.release()
        player = null
        trackSelector = null
        optimizePrebuffer = null
        if (!keepRequest) lastRequest = null
    }

    override fun dispose() {
        handler.removeCallbacksAndMessages(null)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        releasePlayer()
    }
}

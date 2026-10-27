package com.angrymamba.vibelive

import android.app.KeyguardManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.drawable.ColorDrawable
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.util.Rational
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import com.angrymamba.vibelive.calls.CallAudioRouter
import com.angrymamba.vibelive.calls.DeadProcessDeclines
import com.angrymamba.vibelive.calls.IncomingCallRedirect
import com.angrymamba.vibelive.calls.ManufacturerPermission
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's only activity. Beyond hosting Flutter: the call channel (CE's incoming-call UI
 * channel plus RN's proximity lock, minimise and PiP), per-call lock-screen flags, and the
 * cover that hides the previous screen until Dart's call UI has drawn.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val TAG = "VibeMainActivity"

        /** Breadcrumb tag shared with Dart's accept path (`adb logcat -s CallAccept`). */
        const val ACCEPT_TAG = "CallAccept"

        /** Dart: `lib/app/callscreen/helper/native/native_call_bridge.dart`. */
        const val CHANNEL = "com.angrymamba.vibelive/call_ui"
        const val SURFACE = 0xFF080808.toInt()

        /** Backstop only: Dart drops the cover as soon as the call UI has drawn. */
        const val COVER_TIMEOUT_MS = 4_000L
    }

    private var channel: MethodChannel? = null
    private var launchCallId: String? = null // cold start: collected by Dart (takeLaunchCall)
    private var dartReady = false
    private var lockedForCall = false
    private var callCover: View? = null
    private var lastIntentAt = 0L
    private var proximity: PowerManager.WakeLock? = null
    private var pipEnabled = false // RN: PiP DISABLED per user request
    private val ui = Handler(Looper.getMainLooper())
    private val dropCover = Runnable { hideCallCover() }

    override fun onCreate(savedInstanceState: Bundle?) {
        val incoming = IncomingCallRedirect.isIncomingCallLaunch(intent)
        // BEFORE super.onCreate: the window must be marked as over-keyguard before the system
        // decides to ask for the credential (RN + CE).
        if (incoming) {
            lockedForCall = true
            applyLockFlags(true)
            logCallLaunch("cold", intent)
        }
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
        if (incoming) skipLaunchSplash()
    }

    override fun onStart() {
        super.onStart()
        if (lockedForCall) applyLockFlags(true) // a stop/start cycle drops the flags (RN onStart)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The RN build's session, read once on the first Flutter launch.
        LegacySessionReader.register(flutterEngine.dartExecutor.binaryMessenger, this)
        dartReady = false
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeLaunchCall" -> {
                        dartReady = true
                        result.success(launchCallId)
                        launchCallId = null
                    }
                    "setLockedActivity" -> {
                        setLockedActivity(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    "hideCallCover" -> {
                        runOnUiThread { hideCallCover() }
                        result.success(null)
                    }
                    "isDeviceLocked" -> result.success(isDeviceLocked())
                    "exitApp" -> {
                        runOnUiThread {
                            hideCallCover()
                            setLockedActivity(false)
                            finishAndRemoveTask()
                        }
                        result.success(null)
                    }
                    "minimizeApp" -> { // RN
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    "setVolumeControlStream" -> {
                        volumeControlStream = when (call.arguments) {
                            "ring" -> AudioManager.STREAM_RING
                            "call" -> AudioManager.STREAM_VOICE_CALL
                            else -> AudioManager.USE_DEFAULT_STREAM_TYPE
                        }
                        result.success(null)
                    }
                    "setCallAudioRoute" -> result.success(
                        CallAudioRouter.setRoute(
                            call.argument<String>("callId"),
                            call.argument<String>("route"),
                        ),
                    )
                    "callAudioRoutes" -> result.success(
                        CallAudioRouter.routes(call.argument<String>("callId")),
                    )
                    "bluetoothAvailable" -> result.success(
                        CallAudioRouter.bluetoothAvailable(this@MainActivity),
                    )
                    "acquireProximityLock" -> { // RN, audio calls
                        acquireProximity()
                        result.success(null)
                    }
                    "releaseProximityLock" -> {
                        releaseProximity()
                        result.success(null)
                    }
                    "pipSetCallActive" -> {
                        pipEnabled = call.argument<Boolean>("enabled") ?: false
                        updatePipParams(
                            call.argument<Boolean>("active") ?: false,
                            call.argument<Boolean>("video") ?: false,
                        )
                        result.success(null)
                    }
                    "pipEnter" -> result.success(enterPip())
                    "pipIsActive" -> result.success(isInPictureInPictureMode)
                    "drainNativeDeclines" -> result.success(
                        DeadProcessDeclines.drain(this@MainActivity),
                    )
                    // Video call privacy: the system blocks screenshots and records the
                    // window as black (Recents too, and the PiP window) while it is set.
                    "setSecureScreen" -> {
                        if (call.argument<Boolean>("secure") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        ManufacturerPermission.install(this, flutterEngine.dartExecutor.binaryMessenger)
        handleCallIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val now = System.currentTimeMillis()
        val bounce = now - lastIntentAt < 300 // RN: debounce rapid onNewIntent
        lastIntentAt = now
        if (bounce) return
        if (IncomingCallRedirect.isIncomingCallLaunch(intent)) {
            logCallLaunch("warm", intent)
            setLockedActivity(true)
            // The cover only hides the previous screen until the in-app incoming screen draws,
            // and only a tap on the notification (our redirect) leads there; Dart drops it.
            // A notification Accept goes straight to /call and nothing would drop it: a black
            // cover swallowing taps for 4 s (A6).
            if (IncomingCallRedirect.callIdOf(intent) != null) showCallCover()
        }
        handleCallIntent(intent)
    }

    /** A notification tap / full-screen intent: hand the call id to Dart (cold → parked). */
    private fun handleCallIntent(intent: Intent?) {
        val callId = IncomingCallRedirect.callIdOf(intent) ?: return
        Log.i(TAG, "opened on an incoming call (callId=$callId)")
        // Consume it: the activity keeps its intent, and a recreation would replay this tap.
        intent?.action = null
        intent?.removeExtra(IncomingCallRedirect.EXTRA_CALL_ID)
        if (intent != null) setIntent(intent)
        setLockedActivity(true)
        showCallCover()
        if (dartReady) channel?.invokeMethod("showIncomingCall", callId) else launchCallId = callId
    }

    // ── lock screen (CE MainActivity.setLockedActivity; no requestDismissKeyguard: on a PIN
    //    device it pops the credential prompt, so answering would ask for the password) ──
    private fun setLockedActivity(on: Boolean) = runOnUiThread {
        lockedForCall = on
        applyLockFlags(on)
        if (!on) hideCallCover()
    }

    @Suppress("DEPRECATION")
    private fun applyLockFlags(on: Boolean) {
        val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
            WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(on)
                setTurnScreenOn(on)
            }
            if (on) window.addFlags(flags) else window.clearFlags(flags)
        } catch (error: Throwable) {
            Log.w(TAG, "setLockedActivity failed", error)
        }
    }

    private fun logCallLaunch(how: String, intent: Intent?) {
        Log.d(
            ACCEPT_TAG,
            "MainActivity $how launch action=${intent?.action?.substringAfterLast('.')} " +
                "locked=${isDeviceLocked()} (show-when-locked on)",
        )
    }

    private fun isDeviceLocked(): Boolean {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager ?: return false
        return km.isKeyguardLocked || km.isDeviceLocked
    }

    // ── cover over the previous Flutter frame until Dart's call UI draws (CE) ──
    private fun showCallCover() {
        val root = findViewById<ViewGroup>(android.R.id.content)
        if (root == null || root.childCount == 0) {
            ui.post { addCover() }
            return
        }
        addCover()
    }

    private fun addCover() {
        if (callCover != null) return
        try {
            val root = findViewById<ViewGroup>(android.R.id.content) ?: return
            val cover = View(this).apply {
                setBackgroundColor(SURFACE)
                isClickable = true // swallows taps on the screen underneath
            }
            root.addView(cover, ViewGroup.LayoutParams(-1, -1))
            cover.bringToFront()
            callCover = cover
            ui.removeCallbacks(dropCover)
            ui.postDelayed(dropCover, COVER_TIMEOUT_MS)
        } catch (error: Throwable) {
            Log.w(TAG, "could not cover the previous screen", error)
        }
    }

    private fun hideCallCover() {
        ui.removeCallbacks(dropCover)
        val cover = callCover ?: return
        callCover = null
        try {
            (cover.parent as? ViewGroup)?.removeView(cover)
        } catch (error: Throwable) {
            Log.w(TAG, "could not remove the call cover", error)
        }
    }

    private fun skipLaunchSplash() {
        try {
            window.setBackgroundDrawable(ColorDrawable(SURFACE))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                splashScreen.setOnExitAnimationListener { it.remove() }
            }
        } catch (error: Throwable) {
            Log.w(TAG, "could not skip splash", error)
        }
    }

    // ── proximity (RN IncomingCallManagerModule) ──
    private fun acquireProximity() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            if (proximity == null &&
                pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)
            ) {
                proximity = pm.newWakeLock(
                    PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                    "VibeLive:Proximity",
                )
            }
            if (proximity?.isHeld == false) proximity?.acquire(4 * 60 * 60 * 1000L)
        } catch (error: Throwable) {
            Log.w(TAG, "proximity lock failed", error)
        }
    }

    private fun releaseProximity() {
        try {
            if (proximity?.isHeld == true) proximity?.release()
        } catch (error: Throwable) {
            Log.w(TAG, "proximity release failed", error)
        }
    }

    // ── PiP (RN PiPModule; off unless Dart enables it) ──
    private fun updatePipParams(active: Boolean, video: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val b = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(9, 16))
            .setActions(emptyList())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(pipEnabled && active && video)
            b.setSeamlessResizeEnabled(true)
        }
        runCatching { setPictureInPictureParams(b.build()) }
    }

    private fun enterPip(): Boolean {
        if (!pipEnabled || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return runCatching {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder().setAspectRatio(Rational(9, 16)).build(),
            )
        }.getOrDefault(false)
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPip, newConfig)
        channel?.invokeMethod("pipChanged", inPip) // RN "PiPModeChanged"
    }

    override fun onDestroy() {
        ui.removeCallbacks(dropCover)
        callCover = null
        releaseProximity()
        channel?.setMethodCallHandler(null)
        channel = null
        dartReady = false
        super.onDestroy()
    }

    // Many OEMs give apps 60 Hz by default: ask for the panel's fastest mode
    // (90/120 Hz) at the current resolution so Flutter renders at that rate.
    private fun preferHighestRefreshRate() {
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
            else @Suppress("DEPRECATION") windowManager.defaultDisplay
        val current = display?.mode ?: return
        val fastest = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        window.attributes = window.attributes.apply { preferredDisplayModeId = fastest.modeId }
    }
}

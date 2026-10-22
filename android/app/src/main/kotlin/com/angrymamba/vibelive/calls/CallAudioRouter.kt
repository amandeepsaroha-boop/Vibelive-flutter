package com.angrymamba.vibelive.calls

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.telecom.CallAudioState
import android.util.Log
import com.hiennv.flutter_callkit_incoming.CallkitConnection

/**
 * Routes the call's audio through Telecom (CE `MainActivity.setCallAudioRoute`).
 *
 * `flutter_callkit_incoming` registers every call as a self-managed Telecom connection (it
 * holds MANAGE_OWN_CALLS). While such a connection is live, Telecom, not the app, owns the
 * audio route: it pins the call to the earpiece and overrides
 * `AudioManager.setSpeakerphoneOn`, which is what Agora's `setEnableSpeakerphone` calls
 * underneath. That is why the speaker button did nothing. The route has to be asked for
 * through the connection itself; Dart asks both Agora and Telecom.
 */
object CallAudioRouter {
    private const val TAG = "VibeCallAudioRouter"

    /**
     * Puts the call on a named route: `speaker`, `earpiece`, `bluetooth` or `headset`.
     * False is not a failure: Telecom is not holding this call, so Agora's routing applies.
     */
    @Suppress("DEPRECATION")
    fun setRoute(callId: String?, route: String?): Boolean {
        if (callId.isNullOrEmpty() || route.isNullOrEmpty()) return false
        val telecomRoute = when (route) {
            "speaker" -> CallAudioState.ROUTE_SPEAKER
            "bluetooth" -> CallAudioState.ROUTE_BLUETOOTH
            "headset" -> CallAudioState.ROUTE_WIRED_HEADSET
            else -> CallAudioState.ROUTE_EARPIECE
        }
        return try {
            val connection = CallkitConnection.find(callId) ?: return false
            connection.setAudioRoute(telecomRoute)
            Log.i(TAG, "telecom audio route -> $route ($callId)")
            true
        } catch (error: Throwable) {
            Log.w(TAG, "could not set the Telecom audio route", error)
            false
        }
    }

    /**
     * The routes Telecom says this call can use, and the one it is on. Telecom is the only
     * reliable source while a self-managed connection is live: `AudioManager.getDevices` only
     * lists a headset once SCO is up.
     */
    @Suppress("DEPRECATION")
    fun routes(callId: String?): Map<String, Any?> {
        val fallback = mapOf("routes" to listOf("earpiece", "speaker"), "current" to null)
        if (callId.isNullOrEmpty()) return fallback
        return try {
            val state = CallkitConnection.find(callId)?.callAudioState ?: return fallback
            val mask = state.supportedRouteMask
            val routes = mutableListOf<String>()
            if (mask and CallAudioState.ROUTE_EARPIECE != 0) routes.add("earpiece")
            if (mask and CallAudioState.ROUTE_SPEAKER != 0) routes.add("speaker")
            if (mask and CallAudioState.ROUTE_BLUETOOTH != 0) routes.add("bluetooth")
            if (mask and CallAudioState.ROUTE_WIRED_HEADSET != 0) routes.add("headset")
            val current = when (state.route) {
                CallAudioState.ROUTE_SPEAKER -> "speaker"
                CallAudioState.ROUTE_BLUETOOTH -> "bluetooth"
                CallAudioState.ROUTE_WIRED_HEADSET -> "headset"
                else -> "earpiece"
            }
            mapOf("routes" to routes, "current" to current)
        } catch (error: Throwable) {
            Log.w(TAG, "could not read the Telecom audio routes", error)
            fallback
        }
    }

    /** Whether a Bluetooth headset or speaker is connected right now. */
    fun bluetoothAvailable(context: Context): Boolean = try {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        audio?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)?.any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
        } ?: false
    } catch (error: Throwable) {
        Log.w(TAG, "could not read the audio devices", error)
        false
    }
}

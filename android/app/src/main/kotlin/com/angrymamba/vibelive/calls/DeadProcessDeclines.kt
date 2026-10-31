package com.angrymamba.vibelive.calls

import android.content.Context
import android.os.Bundle
import android.util.Log
import com.hiennv.flutter_callkit_incoming.CallkitBackgroundExecutor
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin
import org.json.JSONArray
import org.json.JSONObject

/**
 * A Decline on the incoming-call notification while the process was dead (A5).
 *
 * The plugin's receiver hands the event to a Flutter engine: the UI engine if one listens,
 * else the background executor if Dart started it. In a process the Decline itself started,
 * neither exists, so the event was dropped: no Callend, and the caller rang on until the
 * call went "missed".
 *
 * Two things happen here, both before the plugin forwards the event (the callback runs
 * first, on the main thread):
 * 1. The plugin's background executor is started with the handle Dart registered last time,
 *    so the plugin then delivers this very Decline to Dart's background handler, which sends
 *    the Callend (`onCallKitBackgroundEvent`).
 * 2. The ring payload is kept here as a backstop. Dart drains it on its next start / resume
 *    (`drainNativeDeclines`) and declines it unless that call is already over.
 */
object DeadProcessDeclines : CallkitEventCallback {
    private const val TAG = "VibeDeadProcessDeclines"
    private const val PREFS = "vibe_native_declines"
    private const val KEY = "pending"
    private const val MAX_AGE_MS = 30 * 60 * 1000L
    private const val MAX_ITEMS = 10

    /** The plugin's own prefs (`SharedPreferencesUtils`): the handle `registerBackgroundHandler` stored. */
    private const val PLUGIN_PREFS = "flutter_callkit_incoming"
    private const val PLUGIN_HANDLE = "CALLBACK_HANDLE"

    /** `CallkitConstants.EXTRA_CALLKIT_EXTRA`: the app's ring payload. */
    private const val EXTRA_CALLKIT_EXTRA = "EXTRA_CALLKIT_EXTRA"
    private const val EXTRA_CALLKIT_ID = "EXTRA_CALLKIT_ID"

    private var app: Context? = null

    fun install(context: Context) {
        app = context.applicationContext
        // The plugin keeps a WeakReference: this object is held for the process lifetime.
        FlutterCallkitIncomingPlugin.registerEventCallback(this)
    }

    override fun onCallEvent(event: CallkitEventCallback.CallEvent, callData: Bundle) {
        if (event != CallkitEventCallback.CallEvent.DECLINE) return
        val context = app ?: return
        // An engine already ran in this process: the plugin delivers the event to it, and the
        // app's own endCall echo (answered elsewhere, ring dismissed) must never become a
        // decline. Only a process no Dart ever ran in is ours to handle.
        if (FlutterCallkitIncomingPlugin.hasInstance() || CallkitBackgroundExecutor.registered) return
        val payload = payloadOf(callData) ?: return
        Log.i(TAG, "decline with no engine (callId=${payload.optString("callId")})")
        remember(context, payload)
        startBackgroundEngine(context)
    }

    private fun startBackgroundEngine(context: Context) {
        try {
            val handle = context.getSharedPreferences(PLUGIN_PREFS, Context.MODE_PRIVATE)
                .getLong(PLUGIN_HANDLE, 0L)
            if (handle == 0L) return
            CallkitBackgroundExecutor.start(context, handle)
        } catch (error: Throwable) {
            Log.w(TAG, "could not start the background engine", error)
        }
    }

    private fun payloadOf(data: Bundle): JSONObject? {
        val extra = try {
            @Suppress("DEPRECATION")
            data.getSerializable(EXTRA_CALLKIT_EXTRA) as? Map<*, *>
        } catch (_: Throwable) {
            null
        }
        val out = JSONObject()
        // isInstantCall / instantCallSessionId: a Talk Now ring declines through
        // /instant-call/host-decline, not Callend (the id is a session's).
        for (key in listOf(
            "callId", "receiverId", "type", "calleridDocID", "callerId",
            "isInstantCall", "instantCallSessionId",
        )) {
            val v = extra?.get(key)?.toString()?.trim()
            if (!v.isNullOrEmpty() && v != "null") out.put(key, v)
        }
        if (!out.has("callId")) {
            val id = data.getString(EXTRA_CALLKIT_ID)?.trim()
            if (id.isNullOrEmpty()) return null
            out.put("callId", id)
        }
        out.put("__declinedAt", System.currentTimeMillis())
        return out
    }

    @Synchronized
    private fun remember(context: Context, payload: JSONObject) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            val kept = JSONArray()
            val old = JSONArray(prefs.getString(KEY, "[]") ?: "[]")
            for (i in 0 until old.length()) {
                val item = old.optJSONObject(i) ?: continue
                if (item.optString("callId") == payload.optString("callId")) continue
                if (now - item.optLong("__declinedAt") > MAX_AGE_MS) continue
                kept.put(item)
            }
            kept.put(payload)
            while (kept.length() > MAX_ITEMS) kept.remove(0)
            prefs.edit().putString(KEY, kept.toString()).commit()
        } catch (error: Throwable) {
            Log.w(TAG, "could not keep the decline", error)
        }
    }

    /** Dart (`NativeCallBridge.drainNativeDeclines`): the kept payloads, once. */
    @Synchronized
    fun drain(context: Context): List<Map<String, Any?>> {
        return try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY, null) ?: return emptyList()
            prefs.edit().remove(KEY).commit()
            val now = System.currentTimeMillis()
            val list = JSONArray(raw)
            val out = mutableListOf<Map<String, Any?>>()
            for (i in 0 until list.length()) {
                val item = list.optJSONObject(i) ?: continue
                if (now - item.optLong("__declinedAt") > MAX_AGE_MS) continue
                val map = mutableMapOf<String, Any?>()
                for (key in item.keys()) {
                    if (key != "__declinedAt") map[key] = item.opt(key)?.toString()
                }
                out.add(map)
            }
            out
        } catch (error: Throwable) {
            Log.w(TAG, "could not read the kept declines", error)
            emptyList()
        }
    }
}

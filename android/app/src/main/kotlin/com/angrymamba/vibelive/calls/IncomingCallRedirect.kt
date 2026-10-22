package com.angrymamba.vibelive.calls

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.angrymamba.vibelive.MainActivity

/**
 * Sends a tap on the incoming-call notification to the app's own incoming call screen
 * instead of the one `flutter_callkit_incoming` draws (CE port).
 *
 * The plugin points both the notification's content intent and its full-screen intent at its
 * own `CallkitIncomingActivity`, by class name. That is an explicit component, so no manifest
 * entry and no Dart option can point it somewhere else, and the activity raises no event when
 * it opens. The only place left to intervene is the moment it is created: the activity is
 * finished before it draws and `MainActivity` is started in its place, carrying the call it
 * was opened for. This matches RN, whose notification pointed at `MainActivity`.
 *
 * Everything else the plugin does (the notification, the ringtone, Accept, Decline, the
 * timeout, the ongoing-call service) is untouched. Only the tap target changes.
 */
object IncomingCallRedirect : Application.ActivityLifecycleCallbacks {
    private const val TAG = "VibeIncomingCallRedirect"

    /** The plugin activity to stand in for, matched by name. */
    private const val CALLKIT_ACTIVITY =
        "com.hiennv.flutter_callkit_incoming.CallkitIncomingActivity"

    /** `CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA`: the call, as the plugin passes it. */
    private const val EXTRA_INCOMING_DATA = "EXTRA_CALLKIT_INCOMING_DATA"

    /** `CallkitConstants.EXTRA_CALLKIT_ID`: the id the call was registered under. */
    private const val EXTRA_CALLKIT_ID = "EXTRA_CALLKIT_ID"

    /** `CallkitConstants.EXTRA_CALLKIT_EXTRA`: the app's own payload (the real call id). */
    private const val EXTRA_CALLKIT_EXTRA = "EXTRA_CALLKIT_EXTRA"

    /** Marks an intent this object built, so `MainActivity` knows to open the call. */
    const val ACTION_SHOW_INCOMING_CALL = "com.angrymamba.vibelive.SHOW_INCOMING_CALL"

    /** The call id, on an intent carrying [ACTION_SHOW_INCOMING_CALL]. */
    const val EXTRA_CALL_ID = "vibe_call_id"

    fun install(application: Application) {
        application.registerActivityLifecycleCallbacks(this)
        Log.i(TAG, "watching for the call notification's own activity")
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        if (activity.javaClass.name != CALLKIT_ACTIVITY) return

        val data: Bundle? = try {
            activity.intent?.getBundleExtra(EXTRA_INCOMING_DATA)
        } catch (error: Throwable) {
            Log.w(TAG, "could not read the call off the intent", error)
            null
        }
        val callId = callIdOf(data)
        Log.i(TAG, "notification opened, showing the app's incoming screen instead (callId=$callId)")

        try {
            activity.startActivity(launchIntent(activity, callId))
        } catch (error: Throwable) {
            // Losing the redirect must not leave the plugin's screen up: the call is still
            // ringing, and the notification is still there to try again with.
            Log.e(TAG, "could not start MainActivity", error)
        }

        activity.finish()
        @Suppress("DEPRECATION")
        activity.overridePendingTransition(0, 0)
    }

    /**
     * The intent that opens the app on this call. Built from the launcher intent (as the
     * plugin itself does for Accept), with the activity named outright as the fallback.
     */
    private fun launchIntent(context: Context, callId: String?): Intent {
        val intent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.cloneFilter()
            ?: Intent(context, MainActivity::class.java)

        intent.action = ACTION_SHOW_INCOMING_CALL
        if (callId != null) intent.putExtra(EXTRA_CALL_ID, callId)
        intent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
        )
        return intent
    }

    /** The app's call id for this notification: the payload's first, the plugin id second. */
    private fun callIdOf(data: Bundle?): String? {
        if (data == null) return null
        val fromPayload = try {
            @Suppress("DEPRECATION")
            val extra = data.getSerializable(EXTRA_CALLKIT_EXTRA)
            (extra as? Map<*, *>)?.get("callId")?.toString()
        } catch (_: Throwable) {
            null
        }
        if (!fromPayload.isNullOrBlank()) return fromPayload
        return data.getString(EXTRA_CALLKIT_ID)?.takeIf { it.isNotBlank() }
    }

    /** The call id on an intent this object built, or null for any other intent. */
    fun callIdOf(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action != ACTION_SHOW_INCOMING_CALL) return null
        return intent.getStringExtra(EXTRA_CALL_ID) ?: ""
    }

    /**
     * Whether this intent was opened for an incoming call (CE `MainActivity`): our redirect,
     * or the plugin's own Accept / incoming intents.
     */
    fun isIncomingCallLaunch(intent: Intent?): Boolean {
        if (intent == null) return false
        val action = intent.action ?: ""
        if (action == ACTION_SHOW_INCOMING_CALL) return true
        if (action.endsWith("ACTION_CALL_ACCEPT")) return true
        if (action.endsWith("ACTION_CALL_INCOMING")) return true
        return callIdOf(intent) != null
    }

    override fun onActivityStarted(activity: Activity) = Unit
    override fun onActivityResumed(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivityStopped(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit
}

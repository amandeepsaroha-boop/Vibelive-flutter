package com.angrymamba.vibelive

import android.app.Application
import com.angrymamba.vibelive.calls.DeadProcessDeclines
import com.angrymamba.vibelive.calls.IncomingCallRedirect

/** Watching must start before any activity exists, including one a notification tap starts
 *  while the process is dead. */
class VibeApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        IncomingCallRedirect.install(this)
        // A Decline tapped while the process was dead reaches no engine (A5).
        DeadProcessDeclines.install(this)
    }
}

package com.angrymamba.vibelive.calls

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * The OEM permissions a call depends on and the settings screens that grant them (CE port of
 * RN `ManufacturerPermissionModule.kt`, plus RN's `openSamsungOverlaySettings`).
 *
 * Every one of these is a manufacturer's own idea rather than an Android API: MIUI keeps
 * "Show on lock screen" and "Background pop-ups" as hidden app-ops that can only be read by
 * reflection and only be granted by the user in MIUI's own permission editor. Reading is all
 * this can do; there is no intent that grants any of them.
 */
object ManufacturerPermission {
    private const val TAG = "VibeManufacturerPerm"

    /** Dart: `lib/app/callscreen/helper/native/manufacturer_permission.dart`. */
    const val CHANNEL = "com.angrymamba.vibelive/manufacturer_permission"

    /** `OP_SYSTEM_ALERT_WINDOW`, the standard AOSP index RN reads on MIUI. */
    private const val OP_SYSTEM_ALERT_WINDOW = 24

    private var channel: MethodChannel? = null

    fun install(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "manufacturer" -> result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "brand" to Build.BRAND,
                        ),
                    )
                    "canDrawOverlays" -> result.success(canDrawOverlays(app))
                    "checkXiaomiPermission" -> result.success(
                        checkXiaomiOp(app, (call.arguments as? Number)?.toInt() ?: 0),
                    )
                    "openXiaomiPermissions" -> {
                        openXiaomiPermissions(app)
                        result.success(null)
                    }
                    "openOverlaySettings" -> {
                        openOverlaySettings(app)
                        result.success(null)
                    }
                    "openSamsungOverlaySettings" -> {
                        openSamsungOverlaySettings(app)
                        result.success(null)
                    }
                    "openAppSettings" -> {
                        openAppSettings(app)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** MIUI answers for its own app-op; elsewhere the framework check. */
    private fun canDrawOverlays(context: Context): Boolean {
        if (isXiaomi()) return checkXiaomiOp(context, OP_SYSTEM_ALERT_WINDOW)
        return Settings.canDrawOverlays(context)
    }

    /**
     * Reads one of MIUI's proprietary app-ops by reflection. A failed read counts as granted
     * (RN): the reflection is refused on some builds, and a failed read must not put a modal
     * in front of a user whose permissions are fine.
     */
    private fun checkXiaomiOp(context: Context, op: Int): Boolean {
        return try {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val method = ops.javaClass.getMethod(
                "checkOpNoThrow",
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                String::class.java,
            )
            val mode = method.invoke(ops, op, Process.myUid(), context.packageName) as Int
            mode == AppOpsManager.MODE_ALLOWED
        } catch (error: Throwable) {
            Log.w(TAG, "could not read app-op $op", error)
            true
        }
    }

    private fun isXiaomi(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.ROOT)
        return manufacturer.contains("xiaomi") ||
            manufacturer.contains("redmi") ||
            Build.BRAND.lowercase(Locale.ROOT).contains("poco")
    }

    /** MIUI's own per-app permission editor, with app settings as the fallback. */
    private fun openXiaomiPermissions(context: Context) {
        try {
            val intent = Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                setClassName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity",
                )
                putExtra("extra_pkgname", context.packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (error: Throwable) {
            Log.w(TAG, "MIUI permission editor not available", error)
            openAppSettings(context)
        }
    }

    private fun openOverlaySettings(context: Context) {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            context.startActivity(intent)
        } catch (error: Throwable) {
            Log.w(TAG, "overlay settings not available", error)
            openAppSettings(context)
        }
    }

    /**
     * RN: Samsung One UI opens the app-specific "Appear on top" page directly (app name
     * visible, a single toggle), then app details, then the generic overlay screen.
     */
    private fun openSamsungOverlaySettings(context: Context) {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("app_package", context.packageName)
                putExtra("app_uid", Process.myUid())
            }
            context.startActivity(intent)
        } catch (error: Throwable) {
            Log.w(TAG, "Samsung overlay page not available", error)
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", context.packageName, null)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            } catch (second: Throwable) {
                openOverlaySettings(context)
            }
        }
    }

    private fun openAppSettings(context: Context) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", context.packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (error: Throwable) {
            Log.w(TAG, "app settings not available", error)
        }
    }
}

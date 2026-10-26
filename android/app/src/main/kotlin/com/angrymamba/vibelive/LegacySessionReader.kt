package com.angrymamba.vibelive

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec

/**
 * Read-only access to the session the React Native build left on this device, so the
 * first Flutter launch after the store update continues it instead of asking to log in.
 * Dart: `lib/core/session/legacy_session_migration.dart`.
 *
 * Nothing here writes or deletes: RN's data stays as it was (a rollback to the RN build
 * keeps working).
 *
 * - Tokens: `expo-secure-store` 15 — SharedPreferences "SecureStore", key
 *   "key_v1-<name>" (older builds: "<name>"), a JSON item {scheme:"aes", ct, iv, tlen}
 *   encrypted with AES/GCM under the AndroidKeyStore key "AES/GCM/NoPadding:key_v1"
 *   (":keystoreUnauthenticated" appended when the item says usesKeystoreSuffix).
 * - Everything else (and a copy of the tokens since 2026-05): AsyncStorage's SQLite
 *   database "RKStorage", table catalystLocalStorage(key, value).
 */
object LegacySessionReader {
    const val CHANNEL = "com.angrymamba.vibelive/legacy_session"
    private const val TAG = "LegacySession"

    private val TOKEN_KEYS = listOf("access_token", "refresh_token")
    private val ASYNC_KEYS =
        listOf("access_token", "refresh_token", "auth_user", "auth_expert", "device_id")

    /** RN `languageStep.service`: the language question answered or skipped, per user. */
    private const val LANGUAGE_DONE_PREFIX = "@language_step_done:"

    private const val SECURE_PREFS = "SecureStore"
    private const val KEYCHAIN_SERVICE = "key_v1"
    private const val AES_CIPHER = "AES/GCM/NoPadding"

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "read") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            // Keystore and SQLite off the main thread.
            Thread {
                val out = try {
                    read(app)
                } catch (e: Throwable) {
                    Log.w(TAG, "read failed: ${e.message}")
                    mapOf("error" to (e.message ?: e.javaClass.simpleName))
                }
                Handler(Looper.getMainLooper()).post { result.success(out) }
            }.start()
        }
    }

    private fun read(context: Context): Map<String, Any?> {
        val secure = HashMap<String, String>()
        val errors = ArrayList<String>()
        for (key in TOKEN_KEYS) {
            try {
                readSecureStore(context, key)?.let { secure[key] = it }
            } catch (e: Throwable) {
                errors.add("secure:$key:${e.javaClass.simpleName}")
            }
        }
        val async = try {
            readAsyncStorage(context)
        } catch (e: Throwable) {
            errors.add("async:${e.javaClass.simpleName}")
            emptyMap()
        }
        return mapOf("secure" to secure, "async" to async, "errors" to errors)
    }

    private fun readSecureStore(context: Context, key: String): String? {
        val prefs = context.getSharedPreferences(SECURE_PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString("$KEYCHAIN_SERVICE-$key", null)
            ?: prefs.getString(key, null)
            ?: return null
        val item = JSONObject(raw)
        // "hybrid" was only used below API 23 (minSdk is 24); biometric items can't be
        // read without a prompt, and RN never wrote any.
        if (item.optString("scheme") != "aes") return null
        if (item.optBoolean("requireAuthentication", false)) return null
        val base = "$AES_CIPHER:$KEYCHAIN_SERVICE"
        val alias =
            if (item.optBoolean("usesKeystoreSuffix", false)) "$base:keystoreUnauthenticated" else base
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val entry = keyStore.getEntry(alias, null) as? KeyStore.SecretKeyEntry ?: return null
        val ciphertext = Base64.decode(item.getString("ct"), Base64.DEFAULT)
        val iv = Base64.decode(item.getString("iv"), Base64.DEFAULT)
        val cipher = Cipher.getInstance(AES_CIPHER)
        cipher.init(Cipher.DECRYPT_MODE, entry.secretKey, GCMParameterSpec(item.getInt("tlen"), iv))
        return String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8).takeIf { it.isNotEmpty() }
    }

    private fun readAsyncStorage(context: Context): Map<String, String> {
        val file = context.getDatabasePath("RKStorage")
        if (!file.exists()) return emptyMap()
        val db = try {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY)
        } catch (e: Throwable) {
            // A WAL database can need its -shm file created; nothing is written.
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE)
        }
        val out = HashMap<String, String>()
        db.use {
            val marks = ASYNC_KEYS.joinToString(",") { "?" }
            it.rawQuery(
                "SELECT key, value FROM catalystLocalStorage WHERE key IN ($marks) OR key LIKE ?",
                (ASYNC_KEYS + "$LANGUAGE_DONE_PREFIX%").toTypedArray(),
            ).use { c ->
                while (c.moveToNext()) {
                    val value = c.getString(1)
                    if (!value.isNullOrEmpty()) out[c.getString(0)] = value
                }
            }
        }
        return out
    }
}

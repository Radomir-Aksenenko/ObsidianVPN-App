package com.obsidian.vpn

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/**
 * Last successful connect request, used by always-on starts. When the system starts the service
 * without an app intent, there is no config in the intent, so the tunnel is rebuilt from this file.
 *
 * The file holds server keys. It lives in noBackupFilesDir and is readable only by the app.
 * Disconnecting does not delete it, so always-on still works after a manual disconnect. A profile
 * deleted in the app is not removed here: the Dart side does not know about always-on, so the saved
 * config stays until the next successful connect replaces it.
 */
object TunnelStore {
    private const val FILE_NAME = "last_tunnel.json"
    private const val TEMP_NAME = "last_tunnel.json.tmp"

    /** Writes the request atomically (temp file, then rename). Returns false on any failure. */
    fun save(context: Context, request: TunnelRequest): Boolean {
        val dir = context.noBackupFilesDir
        val target = File(dir, FILE_NAME)
        val temp = File(dir, TEMP_NAME)
        val json = JSONObject()
            .put("profileId", request.profileId)
            .put("name", request.name)
            .put("serverHost", request.serverHost)
            .put("configJson", request.configJson)
            .toString()
        return try {
            FileOutputStream(temp).use { out ->
                out.write(json.toByteArray(Charsets.UTF_8))
                out.fd.sync()
            }
            // Owner-only before the rename, so the final file never becomes visible with wider access.
            temp.setReadable(false, false)
            temp.setReadable(true, true)
            temp.setWritable(false, false)
            temp.setWritable(true, true)
            if (temp.renameTo(target)) {
                true
            } else {
                temp.delete()
                false
            }
        } catch (e: Exception) {
            temp.delete()
            false
        }
    }

    /** Returns the saved request, or null when none exists or the file cannot be parsed. */
    fun load(context: Context): TunnelRequest? {
        val file = File(context.noBackupFilesDir, FILE_NAME)
        if (!file.isFile) return null
        return try {
            val json = JSONObject(file.readText(Charsets.UTF_8))
            TunnelRequest(
                profileId = json.getString("profileId"),
                name = json.getString("name"),
                serverHost = json.getString("serverHost"),
                configJson = json.getString("configJson"),
            )
        } catch (e: Exception) {
            null
        }
    }
}

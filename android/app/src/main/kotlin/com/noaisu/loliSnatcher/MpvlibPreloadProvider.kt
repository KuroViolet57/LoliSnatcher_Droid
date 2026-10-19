package com.noaisu.loliSnatcher

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.util.Log
import java.io.File

/**
 * Loads one mpvlib build before Flutter registers plugins.
 *
 * media_kit also calls System.loadLibrary("mpv") and catches the failure.
 * Loading our copy first makes that catch take the already-loaded library
 * out of the picture: we never construct media_kit's player while this
 * variant is the one in memory. "off" loads nothing, which is today's path.
 */
class MpvlibPreloadProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        val ctx = context ?: return true
        val variant = readVariant(ctx)
        loadedVariant = variant
        if (variant == "off") {
            Log.i(TAG, "video-engine: mpvlib preload off")
            return true
        }
        try {
            val dir = ensureCopied(ctx, variant)
            val order = File(dir, "order.txt").readLines()
                .map { it.trim() }
                .filter { it.isNotEmpty() && !it.startsWith("#") }
            for (name in order) {
                val library = File(dir, name)
                if (!library.isFile) {
                    throw IllegalStateException("missing ${library.name}")
                }
                System.load(library.absolutePath)
                Log.i(TAG, "video-engine: loaded ${library.name}")
            }
            Log.i(TAG, "video-engine: mpvlib preload $variant")
        } catch (error: Throwable) {
            loadedVariant = "off"
            Log.e(TAG, "video-engine: mpvlib preload failed", error)
        }
        return true
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

    companion object {
        private const val TAG = "video-engine"
        var loadedVariant: String = "off"

        private fun variantFile(context: android.content.Context) = File(context.filesDir, "mpvlib-variant")

        fun readVariant(context: android.content.Context): String {
            val file = variantFile(context)
            if (!file.isFile) return "off"
            val text = file.readText().trim()
            return if (text == "vulkan" || text == "opengl") text else "off"
        }

        fun writeVariant(context: android.content.Context, variant: String) {
            val safe = if (variant == "vulkan" || variant == "opengl") variant else "off"
            variantFile(context).writeText(safe)
            Log.i(TAG, "video-engine: variant file $safe (loaded $loadedVariant)")
        }

        private fun ensureCopied(context: android.content.Context, variant: String): File {
            val dest = File(context.filesDir, "mpvlib/$variant")
            dest.mkdirs()
            val assetStamp = context.assets.open("mpvlib/$variant/STAMP").bufferedReader().use { it.readText() }
            val localStamp = File(dest, "STAMP")
            if (localStamp.isFile && localStamp.readText() == assetStamp && File(dest, "order.txt").isFile) {
                return dest
            }
            val names = context.assets.list("mpvlib/$variant") ?: emptyArray()
            for (name in names) {
                context.assets.open("mpvlib/$variant/$name").use { input ->
                    File(dest, name).outputStream().use { output -> input.copyTo(output) }
                }
            }
            return dest
        }
    }
}

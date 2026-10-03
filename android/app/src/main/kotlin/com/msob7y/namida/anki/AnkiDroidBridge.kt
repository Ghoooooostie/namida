package com.msob7y.namida.anki

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import com.ichi2.anki.FlashCardsContract
import com.ichi2.anki.api.AddContentApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.math.BigInteger
import java.security.MessageDigest
import java.text.Normalizer

/**
 * AnkiDroid 的 ContentProvider 桥接。
 *
 * 只负责「把一次方法调用转成 AnkiDroid API 调用」，不含任何制卡策略；
 * 字段模板渲染、查重策略都在 Dart 侧的 `AnkiController`。
 *
 * 需要的清单声明（在 AndroidManifest.xml 里）：
 * ```
 * <uses-permission android:name="com.ichi2.anki.permission.READ_WRITE_DATABASE" />
 * <queries>
 *     <package android:name="com.ichi2.anki" />
 *     <provider android:authorities="com.ichi2.anki.flashcards" />
 * </queries>
 * ```
 */
object AnkiDroidBridge {
    private const val CHANNEL = "namida/anki"
    private const val TAG = "AnkiDroidBridge"
    private const val ANKI_PACKAGE = "com.ichi2.anki"
    private const val BROWSER_ACTIVITY = "com.ichi2.anki.CardBrowser"
    private const val SYNC_ACTION = "com.ichi2.anki.DO_SYNC"

    /**
     * AnkiDroid 的 ContentProvider 守卫权限。
     *
     * AnkiDroid 把它声明成 `prot=dangerous`，所以**必须运行时申请**，
     * 只在 manifest 里 `<uses-permission>` 是不够的——默认就是拒绝，
     * 每次 query 都会抛 `SecurityException`。
     */
    private const val ANKI_PERMISSION = "com.ichi2.anki.permission.READ_WRITE_DATABASE"

    const val REQUEST_PERMISSION_CODE = 0x41A7

    private var channel: MethodChannel? = null

    /**
     * 申请权限必须用 Activity，`applicationContext` 转不过来。
     * 收藏库读写本身只用 applicationContext 就够了。
     */
    @Volatile
    private var activity: Activity? = null

    @Volatile
    private var api: AddContentApi? = null

    fun register(messenger: BinaryMessenger, activity: Activity) {
        this.activity = activity
        val app = activity.applicationContext
        channel = MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler { call, result -> handle(app, call, result) }
        }
    }

    fun unregister() {
        channel?.setMethodCallHandler(null)
        channel = null
        activity = null
    }

    /** 权限结果回传给 Dart，让它刷新 UI 上的权限状态。 */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_PERMISSION_CODE) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        channel?.invokeMethod("onPermissionResult", mapOf("granted" to granted))
    }

    // ------------------------------------------------------------------
    // dispatch
    // ------------------------------------------------------------------

    private fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isAvailable" -> result.success(isInstalled(context))

                "permissionStatus" -> result.success(permissionStatus(context))

                "requestPermission" -> {
                    val act = activity
                    if (act == null) {
                        result.error("UNAVAILABLE", "No activity available to request the permission from", null)
                    } else if (!isInstalled(context)) {
                        result.error("UNAVAILABLE", "AnkiDroid is not installed", null)
                    } else if (hasAnkiPermission(context)) {
                        result.success(true)
                    } else {
                        act.requestPermissions(arrayOf(ANKI_PERMISSION), REQUEST_PERMISSION_CODE)
                        result.success(true)
                    }
                }

                "openAppSettings" -> {
                    context.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", context.packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        },
                    )
                    result.success(true)
                }

                "openAnkiDroid" -> result.success(openPackage(context))

                // -- 注意：deckList/modelList 是 Map<Long, String>。直接 toList() 到 Dart 会变成
                //    [{0: id, 1: name}]（键是下标），Dart 侧按 "id"/"name" 取会全拿到 null，
                //    结果就是「不报错但牌组为空」。这里显式摊成带字符串键的 Map。
                "deckList" -> result.success(
                    withApi(context, "DECK_LIST") { api ->
                        val decks = api.deckList?.map { (id, name) -> mapOf("id" to id, "name" to name) }?.toList()
                        Log.i(TAG, "deckList -> ${decks?.size ?: -1} decks")
                        decks
                    },
                )

                "modelList" -> result.success(
                    withApi(context, "MODEL_LIST") { api ->
                        val models = api.modelList?.map { (id, name) -> mapOf("id" to id, "name" to name) }?.toList()
                        Log.i(TAG, "modelList -> ${models?.size ?: -1} note types")
                        models
                    },
                )

                "fieldList" -> {
                    val modelId = call.argument<Number>("modelId")?.toLong()
                        ?: throw IllegalArgumentException("modelId is required")
                    // -- getFieldList 返回的是 Java String[]，StandardMessageCodec 编不了数组
                    //    （会抛 "Unsupported value: [Ljava.lang.String;"），必须转成 List。
                    result.success(
                        withApi(context, "MODEL_FIELDS") { api ->
                            val fields = api.getFieldList(modelId)
                            Log.i(TAG, "fieldList($modelId) -> ${fields?.size ?: -1} fields")
                            fields?.asList()?.toList()
                        },
                    )
                }

                "findDuplicates" -> {
                    val modelId = call.argument<Number>("modelId")?.toLong() ?: 0L
                    val checksum = call.argument<Number>("checksum")?.toLong() ?: 0L
                    val deckIds = call.argument<List<Number>>("deckIds")?.map { it.toLong() }?.toSet() ?: emptySet()
                    val checkAllModels = call.argument<Boolean>("checkAllModels") ?: false
                    result.success(findDuplicates(context, modelId, checksum, deckIds, checkAllModels))
                }

                "firstFieldChecksum" ->
                    result.success(firstFieldChecksum(call.argument<String>("data").orEmpty()))

                "addNote" -> {
                    val modelId = call.argument<Number>("modelId")?.toLong() ?: 0L
                    val deckId = call.argument<Number>("deckId")?.toLong() ?: 0L
                    val fields = (call.argument<List<String>>("fields") ?: emptyList()).toTypedArray()
                    val tags = (call.argument<List<String>>("tags") ?: emptyList()).toSet()
                    result.success(withApi(context, "DECK_LIST") { it.addNote(modelId, deckId, fields, tags) != null })
                }

                "addMedia" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.success(null)
                    } else {
                        val name = call.argument<String>("name").orEmpty()
                        val mimeType = call.argument<String>("mimeType").orEmpty()
                        result.success(addMedia(context, path, name, mimeType))
                    }
                }

                "sync" -> result.success(sync(context))

                "openNotes" -> result.success(openBrowser(context, call.argument<String>("query").orEmpty()))

                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "AnkiDroid database permission denied.", e)
            result.error("PERMISSION_DENIED", e.message, null)
        } catch (e: AnkiUnavailable) {
            Log.w(TAG, "AnkiDroid unavailable for '${call.method}'.", e)
            result.error(e.code, e.message, null)
        } catch (e: Throwable) {
            Log.e(TAG, "AnkiDroid call '${call.method}' failed.", e)
            result.error("UNAVAILABLE", e.message ?: e.javaClass.simpleName, null)
        }
    }

    // ------------------------------------------------------------------
    // AnkiDroid API
    // ------------------------------------------------------------------

    private class AnkiUnavailable(val code: String, message: String) : RuntimeException(message)

    /**
     * AnkiDroid 装没装。
     *
     * 先问 AnkiDroid 官方 API —— 它能认出社区版/定制版的不同包名，
     * 这也是 Hoshi Reader 的做法。拿不到再退回官方包名查 packageManager。
     *
     * Android 11+ 有包可见性过滤，`getPackageInfo` 对看不见的包会抛
     * `NameNotFoundException`。这里把异常原样记进日志，别再靠猜。
     */
    private fun isInstalled(context: Context): Boolean {
        val reported = try {
            AddContentApi.getAnkiDroidPackageName(context)
        } catch (e: Throwable) {
            Log.w(TAG, "getAnkiDroidPackageName threw", e)
            null
        }
        if (!reported.isNullOrEmpty()) {
            Log.i(TAG, "isInstalled: true via AddContentApi ($reported)")
            return true
        }

        return try {
            context.packageManager.getPackageInfo(ANKI_PACKAGE, 0)
            Log.i(TAG, "isInstalled: true via packageManager ($ANKI_PACKAGE)")
            true
        } catch (e: Throwable) {
            Log.e(TAG, "isInstalled: false, $ANKI_PACKAGE not visible", e)
            false
        }
    }

    /** 拿不到就抛 [AnkiUnavailable]，让 Dart 侧统一映射成可读文案。 */
    private fun requireApi(context: Context): AddContentApi {
        if (!isInstalled(context)) {
            throw AnkiUnavailable("UNAVAILABLE", "AnkiDroid is not installed")
        }
        return api ?: AddContentApi(context).also { api = it }
    }

    private fun <T> withApi(context: Context, code: String, block: (AddContentApi) -> T?): T {
        return block(requireApi(context)) ?: throw AnkiUnavailable(code, "AnkiDroid returned nothing for $code")
    }

    private fun hasAnkiPermission(context: Context): Boolean =
        context.checkSelfPermission(ANKI_PERMISSION) == PackageManager.PERMISSION_GRANTED

    /**
     * `granted` / `notDetermined` / `denied` / `unavailable`。
     *
     * `denied` 与 `notDetermined` 的区别：用户点过「拒绝」就再也弹不出系统对话框了，
     * 只能去系统设置页，所以 UI 要分开提示。
     */
    private fun permissionStatus(context: Context): String {
        // -- 顺序很重要：先看权限。
        //    持有 AnkiDroid 的守卫权限就说明它一定装着，这条比「查包可见性」可靠得多
        //    （Android 11+ 的包可见性过滤会让 getPackageInfo 对看不见的包抛 NameNotFound）。
        if (hasAnkiPermission(context)) {
            Log.i(TAG, "permissionStatus -> granted (holds $ANKI_PERMISSION)")
            return "granted"
        }
        if (!isInstalled(context)) {
            Log.i(TAG, "permissionStatus -> unavailable (not installed)")
            return "unavailable"
        }
        val activity = this.activity
        val shouldExplain = activity != null && activity.shouldShowRequestPermissionRationale(ANKI_PERMISSION)
        val status = if (shouldExplain) "notDetermined" else "denied"
        Log.i(TAG, "permissionStatus -> $status")
        return status
    }

    private fun findDuplicates(
        context: Context,
        modelId: Long,
        checksum: Long,
        deckIds: Set<Long>,
        checkAllModels: Boolean,
    ): Boolean {
        if (checksum == 0L) return false
        requireApi(context)

        val selection = buildString {
            if (!checkAllModels) append("${FlashCardsContract.Note.MID} = $modelId and ")
            append("${FlashCardsContract.Note.CSUM} in ($checksum)")
        }

        val cursor = context.contentResolver.query(
            FlashCardsContract.Note.CONTENT_URI_V2,
            arrayOf(FlashCardsContract.Note._ID),
            selection,
            null,
            null,
        ) ?: return false

        cursor.use {
            while (it.moveToNext()) {
                // -- deckIds 为空表示整个收藏，命中即算重复。
                if (deckIds.isEmpty()) return true
                val noteId = it.getLong(it.getColumnIndexOrThrow(FlashCardsContract.Note._ID))
                if (noteHasCardInDeck(context, noteId, deckIds)) return true
            }
        }
        return false
    }

    private fun noteHasCardInDeck(context: Context, noteId: Long, deckIds: Set<Long>): Boolean {
        val noteUri = Uri.withAppendedPath(FlashCardsContract.Note.CONTENT_URI, noteId.toString())
        val cursor = context.contentResolver.query(
            Uri.withAppendedPath(noteUri, "cards"),
            arrayOf(FlashCardsContract.Card.DECK_ID),
            null,
            null,
            null,
        ) ?: return false

        cursor.use {
            while (it.moveToNext()) {
                if (it.getLong(it.getColumnIndexOrThrow(FlashCardsContract.Card.DECK_ID)) in deckIds) return true
            }
        }
        return false
    }

    private fun addMedia(context: Context, path: String, preferredName: String, mimeType: String): String? {
        val file = File(path)
        if (!file.exists()) return null
        val api = requireApi(context)

        // -- AnkiDroid 需要一个它能读到的 Uri。app 私有目录里的文件用 FileProvider 授权过去，
        //    共享存储里的文件本来就在那边，直接给 file://。
        val uri: Uri = try {
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        } catch (_: IllegalArgumentException) {
            Uri.fromFile(file)
        }

        val type = if (mimeType.startsWith("audio/")) "audio" else "image"
        return api.addMediaFromUri(uri, preferredMediaName(preferredName), type)
    }

    /** AnkiDroid 会在这个名字后面自己加序号，所以先砍掉目录与后缀。 */
    private fun preferredMediaName(preferredName: String): String {
        val fileName = preferredName.substringAfterLast('/').substringAfterLast('\\')
        return fileName.substringBeforeLast('.', fileName).ifBlank { "namida_media" }
    }

    private fun sync(context: Context): Boolean = try {
        context.startActivity(
            Intent(SYNC_ACTION).apply {
                setPackage(ankiPackageName(context))
                addCategory(Intent.CATEGORY_DEFAULT)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_NO_HISTORY or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION
            },
        )
        true
    } catch (e: Throwable) {
        Log.w(TAG, "Unable to start the AnkiDroid sync.", e)
        false
    }

    private fun openPackage(context: Context): Boolean = try {
        context.startActivity(
            Intent().apply {
                setPackage(ankiPackageName(context))
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
        true
    } catch (e: Throwable) {
        false
    }

    /** 打开卡片浏览器并带上搜索串。查重范围写在 query 里，别写进浏览器的选中状态。 */
    private fun openBrowser(context: Context, query: String): Boolean {
        if (query.isBlank()) return false
        return try {
            context.startActivity(
                Intent().apply {
                    setClassName(ankiPackageName(context), BROWSER_ACTIVITY)
                    putExtra("search_query", query)
                    putExtra("all_decks", true)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            true
        } catch (e: Throwable) {
            Log.w(TAG, "Unable to open the AnkiDroid card browser.", e)
            false
        }
    }

    /** 优先用 AnkiDroid 自己报告的包名（社区版/定制版包名不同），拿不到再退回官方包名。 */
    private fun ankiPackageName(context: Context): String = try {
        AddContentApi.getAnkiDroidPackageName(context) ?: ANKI_PACKAGE
    } catch (_: Throwable) {
        ANKI_PACKAGE
    }

    // ------------------------------------------------------------------
    // csum
    // ------------------------------------------------------------------

    /**
     * Anki 的首字段校验和 `csum`。
     *
     * 必须与 Anki 内部完全一致，否则查重永远查不出来：
     * 字段先 NFC 规范化 → 去 HTML 媒体 → 去标签 → 解实体 → SHA1 → 取前 8 个十六进制字符。
     * 这一步只能在原生做，Dart 没有内置 NFC 规范化。
     */
    private fun firstFieldChecksum(data: String): Long {
        val stripped = Normalizer.normalize(data, Normalizer.Form.NFC).stripHtmlMedia()
        val digest = MessageDigest.getInstance("SHA1").digest(stripped.toByteArray(Charsets.UTF_8))
        val hex = BigInteger(1, digest).toString(16).padStart(40, '0')
        return hex.substring(0, 8).toLong(16)
    }

    private val STYLE_REGEX = Regex("(?is)<style.*?>.*?</style>")
    private val SCRIPT_REGEX = Regex("(?is)<script.*?>.*?</script>")
    private val TAG_REGEX = Regex("<.*?>")
    private val IMG_REGEX = Regex("""<img src=["']?([^"'>\s]+)["']?\s*/?>""", RegexOption.IGNORE_CASE)
    private val ENTITY_REGEX = Regex("""&#?\w+;""")

    private fun String.stripHtmlMedia(): String =
        IMG_REGEX.replace(this) { " ${it.groupValues[1]} " }
            .replace(STYLE_REGEX, "")
            .replace(SCRIPT_REGEX, "")
            .replace(TAG_REGEX, "")
            .decodeHtmlEntities()

    private fun String.decodeHtmlEntities(): String =
        ENTITY_REGEX.replace(replace("&nbsp;", " ")) { match ->
            when (match.value) {
                "&amp;" -> "&"
                "&lt;" -> "<"
                "&gt;" -> ">"
                "&quot;" -> "\""
                "&#39;", "&apos;" -> "'"
                else -> match.value.decodeNumericHtmlEntity() ?: match.value
            }
        }

    private fun String.decodeNumericHtmlEntity(): String? {
        var value = removePrefix("&#").removeSuffix(";")
        if (value.isEmpty()) return null
        val codePoint = when {
            value.startsWith("x") || value.startsWith("X") -> value.substring(1).toIntOrNull(16)
            value.all { it.isDigit() } -> value.toIntOrNull()
            else -> null
        } ?: return null
        return runCatching { String(Character.toChars(codePoint)) }.getOrNull()
    }
}

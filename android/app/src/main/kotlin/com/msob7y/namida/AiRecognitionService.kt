package com.msob7y.namida

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service that keeps AI subtitle recognition alive while the app is
 * in the background: holds a partial wakelock (so the CPU keeps running with
 * the screen off) and shows a progress notification with a cancel action.
 *
 * Dart drives it through the `namida` channel. [updateNotification] is static
 * on purpose - once backgrounded, `startService` calls are restricted, so
 * progress updates go straight to the NotificationManager instead.
 *
 * A watchdog stops the service if Dart stops reporting (process was killed),
 * so the wakelock and the notification never outlive the actual work.
 */
class AiRecognitionService : Service() {
  companion object {
    private const val TAG = "AiRecognitionService"
    private const val CHANNEL_ID = "ai_recognition"
    private const val NOTIFICATION_ID = 21
    private const val ACTION_CANCEL = "com.msob7y.namida.ai_recognition.CANCEL"

    private const val WAKELOCK_TAG = "namida:ai_recognition"

    /// progress updates flow in about every second, 10 minutes without any
    /// means dart is gone (killed from recents, crash) - release everything.
    private const val WATCHDOG_TIMEOUT_MS = 10 * 60 * 1000L

    /// the live instance, so dart can push notification updates without
    /// going through restricted startService calls while backgrounded.
    private var instance: AiRecognitionService? = null

    /// a stop that raced the service start (startForegroundService followed by
    /// an immediate stopService, e.g. a task that failed instantly): tearing the
    /// service down before startForeground() is a hard app crash, so the stop
    /// parks here and is honored as soon as the service is up.
    @Volatile
    private var pendingStop = false

    fun start(context: Context, title: String, text: String, cancelLabel: String, channelName: String, channelDescription: String) {
      pendingStop = false
      try {
        val intent = Intent(context, AiRecognitionService::class.java)
          .putExtra("title", title)
          .putExtra("text", text)
          .putExtra("cancelLabel", cancelLabel)
          .putExtra("channelName", channelName)
          .putExtra("channelDescription", channelDescription)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          context.startForegroundService(intent)
        } else {
          context.startService(intent)
        }
      } catch (e: Exception) {
        Log.e(TAG, "startForegroundService failed", e)
      }
    }

    fun updateNotification(context: Context, title: String, text: String, progress: Int) {
      instance?.postNotification(title, text, progress)
    }

    fun stop(context: Context) {
      try {
        if (instance == null) {
          // -- the service has not come up yet: stopping it now leaves
          // -- startForegroundService() unsatisfied and kills the app.
          pendingStop = true
          return
        }
        context.stopService(Intent(context, AiRecognitionService::class.java))
      } catch (e: Exception) {
        Log.e(TAG, "stopService failed", e)
      }
    }
  }

  private var wakeLock: PowerManager.WakeLock? = null
  private var cancelLabel: String = "Cancel"

  private var lastTitle: String = ""
  private var lastText: String = ""
  private var lastProgress: Int = -1

  private val watchdog = Handler(Looper.getMainLooper())
  private val watchdogRunnable = Runnable { stopSelf() }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onCreate() {
    super.onCreate()
    instance = this
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent?.action == ACTION_CANCEL) {
      // -- the queue lives in dart, the service only relays the tap.
      notifyDartCancelled()
      watchdog.removeCallbacks(watchdogRunnable)
      stopSelf()
      return START_NOT_STICKY
    }

    lastTitle = intent?.getStringExtra("title") ?: lastTitle
    lastText = intent?.getStringExtra("text") ?: lastText
    cancelLabel = intent?.getStringExtra("cancelLabel") ?: cancelLabel
    val channelName = intent?.getStringExtra("channelName") ?: "AI"
    val channelDescription = intent?.getStringExtra("channelDescription") ?: ""

    createChannel(channelName, channelDescription)
    startAsForeground(buildNotification(lastTitle, lastText, lastProgress))
    acquireWakeLock()

    watchdog.removeCallbacks(watchdogRunnable)
    watchdog.postDelayed(watchdogRunnable, WATCHDOG_TIMEOUT_MS)

    // -- a stop that raced the service start is honored as soon as the
    // -- foreground state is in place (stopSelf alone would not satisfy
    // -- the system: startForeground must have been called first).
    if (pendingStop) {
      pendingStop = false
      stopSelf()
      return START_NOT_STICKY
    }

    // -- not START_STICKY: a restarted service would have no dart work behind it.
    return START_NOT_STICKY
  }

  fun postNotification(title: String, text: String, progress: Int) {
    lastTitle = title
    lastText = text
    lastProgress = progress

    try {
      val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.notify(NOTIFICATION_ID, buildNotification(title, text, progress))
    } catch (_: Exception) {
    }

    watchdog.removeCallbacks(watchdogRunnable)
    watchdog.postDelayed(watchdogRunnable, WATCHDOG_TIMEOUT_MS)
  }

  private fun buildNotification(title: String, text: String, progress: Int): Notification {
    val builder = NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(R.drawable.ic_stat_musicnote)
      .setContentTitle(title)
      .setContentText(text)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setSilent(true)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

    if (progress in 0..100) {
      builder.setProgress(100, progress, false)
    } else {
      builder.setProgress(0, 0, true)
    }

    try {
      packageManager.getLaunchIntentForPackage(packageName)?.let {
        builder.setContentIntent(
          PendingIntent.getActivity(
            this,
            0,
            it,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
          )
        )
      }
    } catch (_: Exception) {
    }

    try {
      builder.addAction(
        0,
        cancelLabel,
        PendingIntent.getService(
          this,
          1,
          Intent(this, AiRecognitionService::class.java).setAction(ACTION_CANCEL),
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ),
      )
    } catch (_: Exception) {
    }

    return builder.build()
  }

  private fun createChannel(name: String, description: String) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      try {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW)
        channel.description = description
        channel.setShowBadge(false)
        nm.createNotificationChannel(channel)
      } catch (_: Exception) {
      }
    }
  }

  private fun startAsForeground(notification: Notification) {
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
      } else {
        startForeground(NOTIFICATION_ID, notification)
      }
    } catch (e: Exception) {
      // -- never swallow this: a startForegroundService() that never reaches
      // -- startForeground() kills the whole app seconds later with
      // -- RemoteServiceException. the untyped call is the fallback for
      // -- devices that reject the declared type.
      Log.e(TAG, "startForeground(type=dataSync) failed, retrying untyped", e)
      try {
        startForeground(NOTIFICATION_ID, notification)
      } catch (e2: Exception) {
        Log.e(TAG, "startForeground() untyped failed too", e2)
      }
    }
  }

  private fun acquireWakeLock() {
    if (wakeLock?.isHeld == true) return
    try {
      val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
      wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG).apply {
        setReferenceCounted(false)
        // -- 2x the watchdog: a hard cap so it can never be held forever.
        acquire(WATCHDOG_TIMEOUT_MS * 2)
      }
    } catch (_: Exception) {
    }
  }

  private fun releaseWakeLock() {
    try {
      wakeLock?.let { if (it.isHeld) it.release() }
    } catch (_: Exception) {
    }
    wakeLock = null
  }

  private fun notifyDartCancelled() {
    try {
      val engine = AudioServicePlugin.getFlutterEngine(applicationContext)
      MethodChannel(engine.dartExecutor.binaryMessenger, "namida").invokeMethod("cancelAiRecognition", null)
    } catch (_: Exception) {
    }
  }

  override fun onDestroy() {
    watchdog.removeCallbacks(watchdogRunnable)
    releaseWakeLock()
    instance = null

    try {
      val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.cancel(NOTIFICATION_ID)
    } catch (_: Exception) {
    }

    super.onDestroy()
  }
}

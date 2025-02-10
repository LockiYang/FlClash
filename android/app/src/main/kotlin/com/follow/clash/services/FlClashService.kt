package com.follow.clash.services

import android.annotation.SuppressLint
import android.app.Notification.FOREGROUND_SERVICE_IMMEDIATE
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.follow.clash.GlobalState
import com.follow.clash.MainActivity
import com.follow.clash.extensions.getActionPendingIntent
import com.follow.clash.models.VpnOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async

// 普通的Clash服务
// 将服务启动为前台服务，并持续显示前台通知
// 似乎没有启动clash？？
class FlClashService : Service(), BaseServiceInterface {

    private val binder = LocalBinder()

    // Binder 用于跨组件通信
    // 外部组件（如Activity）可通过Binder获取该服务的引用
    inner class LocalBinder : Binder() {
        fun getService(): FlClashService = this@FlClashService
    }

    // 服务绑定时返回binder
    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    override fun onUnbind(intent: Intent?): Boolean {
        return super.onUnbind(intent)
    }

    private val CHANNEL = "FlClash"

    private val notificationId: Int = 1

    // 构建用于前台服务的通知
    private val notificationBuilderDeferred: Deferred<NotificationCompat.Builder> by lazy {
        CoroutineScope(Dispatchers.Main).async {
            val stopText = GlobalState.getText("stop")

            // intent指定点击通知应该打开的MainActivity
            val intent = Intent(
                this@FlClashService, MainActivity::class.java
            )

            val pendingIntent = if (Build.VERSION.SDK_INT >= 31) {
                PendingIntent.getActivity(
                    this@FlClashService,
                    0,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            } else {
                PendingIntent.getActivity(
                    this@FlClashService,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT
                )
            }

            with(NotificationCompat.Builder(this@FlClashService, CHANNEL)) {
                setSmallIcon(com.follow.clash.R.drawable.ic_stat_name)
                setContentTitle("FlClash")
                setContentIntent(pendingIntent)
                setCategory(NotificationCompat.CATEGORY_SERVICE)
                priority = NotificationCompat.PRIORITY_MIN
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    foregroundServiceBehavior = FOREGROUND_SERVICE_IMMEDIATE
                }
                addAction(
                    0,
                    stopText, // 使用 suspend 函数获取的文本
                    getActionPendingIntent("STOP")
                )
                setOngoing(true)
                setShowWhen(false)
                setOnlyAlertOnce(true)
                setAutoCancel(true)
            }
        }
    }
    private suspend fun getNotificationBuilder(): NotificationCompat.Builder {
        return notificationBuilderDeferred.await()
    }

    // 直接返回0
    override fun start(options: VpnOptions) = 0

    // 停止当前服务
    // 移除前台通知，停止前台服务
    override fun stop() {
        stopSelf()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }

    // 将服务启动为前台服务，并持续显示前台通知
    @SuppressLint("ForegroundServiceType", "WrongConstant")
    override suspend fun startForeground(title: String, content: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            var channel = manager?.getNotificationChannel(CHANNEL)
            if (channel == null) {
                channel =
                    NotificationChannel(CHANNEL, "FlClash", NotificationManager.IMPORTANCE_LOW)
                manager?.createNotificationChannel(channel)
            }
        }
        val notification =
            getNotificationBuilder()
                .setContentTitle(title)
                .setContentText(content).build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(notificationId, notification, FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(notificationId, notification)
        }
    }
}
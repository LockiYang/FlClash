package com.follow.clash.services

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import androidx.lifecycle.Observer
import com.follow.clash.GlobalState
import com.follow.clash.RunState
import com.follow.clash.TempActivity

// App开关 磁贴
@RequiresApi(Build.VERSION_CODES.N)
class FlClashTileService : TileService() {

    // 观察 RunState 状态的变化，当 RunState 变化时，调用 updateTile() 方法更新磁贴的状态
    private val observer = Observer<RunState> { runState ->
        updateTile(runState)
    }

    private fun updateTile(runState: RunState) {
        if (qsTile != null) {
            qsTile.state = when (runState) {
                RunState.START -> Tile.STATE_ACTIVE
                RunState.PENDING -> Tile.STATE_UNAVAILABLE
                RunState.STOP -> Tile.STATE_INACTIVE
            }
            qsTile.updateTile()
        }
    }

    // TileService 初始化
    override fun onStartListening() {
        super.onStartListening()
        // 用runState的值初始化 qsTile.state
        GlobalState.runState.value?.let { updateTile(it) }
        // 注册观察器
        GlobalState.runState.observeForever(observer)
    }

    // 启动TempActivity
    // PendingIntent：一种延迟执行的 Intent，允许外部应用（如通知或快捷方式）触发此 Intent
    // Android 14以上：启动活动并关闭快速设置面板
    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun activityTransfer() {
        val intent = Intent(this, TempActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        val pendingIntent = if (Build.VERSION.SDK_INT >= 31) {
            PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } else {
            PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // 启动活动 并 关闭当前的快速设置面板
            // Android 14 及以上，支持 PendingIntent
            startActivityAndCollapse(pendingIntent)
        } else {
            startActivityAndCollapse(intent)
        }
    }

    // 点击磁贴，转换App开关状态
    override fun onClick() {
        super.onClick()
        activityTransfer()
        GlobalState.handleToggle()
    }

    override fun onDestroy() {
        GlobalState.runState.removeObserver(observer)
        super.onDestroy()
    }
}
package com.follow.clash

import android.content.Context
import androidx.lifecycle.MutableLiveData
import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.ServicePlugin
import com.follow.clash.plugins.TilePlugin
import com.follow.clash.plugins.VpnPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

enum class RunState {
    START,
    PENDING,
    STOP
}

// object 用于创建单例对象或静态工具类
// 不需要手动实例化、自动是一个单例对象
object GlobalState {
    val runLock = ReentrantLock()

    val runState: MutableLiveData<RunState> = MutableLiveData<RunState>(RunState.STOP)
    // 在MainActivity中初始化
    // FlutterEngine会创建一个独立的Dart虚拟机，用于执行Dart代码，destroy后虚拟机停止运行。
    var flutterEngine: FlutterEngine? = null
    private var serviceEngine: FlutterEngine? = null

    fun getCurrentAppPlugin(): AppPlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        return currentEngine?.plugins?.get(AppPlugin::class.java) as AppPlugin?
    }

    suspend fun getText(text: String): String {
        return getCurrentAppPlugin()?.getText(text) ?: ""
    }

    fun getCurrentTilePlugin(): TilePlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        return currentEngine?.plugins?.get(TilePlugin::class.java) as TilePlugin?
    }

    fun getCurrentVPNPlugin(): VpnPlugin? {
        return serviceEngine?.plugins?.get(VpnPlugin::class.java) as VpnPlugin?
    }

    // 磁贴：VPN开关
    fun handleToggle() {
        val starting = handleStart()
        if (!starting) {
            handleStop()
        }
    }

    fun handleStart(): Boolean {
        if (runState.value == RunState.STOP) {
            runState.value = RunState.PENDING
            runLock.lock()
            val tilePlugin = getCurrentTilePlugin()
            if (tilePlugin != null) {
                tilePlugin.handleStart()
            } else {
                initServiceEngine()
            }
            return true
        }
        return false
    }

    fun handleStop() {
        if (runState.value == RunState.START) {
            runState.value = RunState.PENDING
            runLock.lock()
            getCurrentTilePlugin()?.handleStop()
        }
    }

    fun handleTryDestroy() {
        if (flutterEngine == null) {
            destroyServiceEngine()
        }
    }

    fun destroyServiceEngine() {
        runLock.withLock {
            serviceEngine?.destroy()
            serviceEngine = null
        }
    }

    // 执行service的Flutter Engine -> 指定Dart入口点（立即执行）
    fun initServiceEngine() {
        if (serviceEngine != null) return
        destroyServiceEngine()
        runLock.withLock {
            serviceEngine = FlutterEngine(FlClashApplication.getAppContext())
            serviceEngine?.plugins?.add(VpnPlugin)
            serviceEngine?.plugins?.add(AppPlugin())
            serviceEngine?.plugins?.add(TilePlugin())
            val vpnService = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "_service"
            )
            serviceEngine?.dartExecutor?.executeDartEntrypoint(
                vpnService,
                if (flutterEngine == null) listOf("quick") else null
            )
        }
    }
}



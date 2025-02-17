package com.follow.clash

import android.app.Activity
import android.os.Bundle
import com.follow.clash.extensions.wrapAction

// 无界面，用来后台执行方法
// 根据传入的 Intent 的 action 字段，决定调用的方法
class TempActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        when (intent.action) {
            wrapAction("START") -> {
                GlobalState.handleStart()
            }

            wrapAction("STOP") -> {
                GlobalState.handleStop()
            }

            wrapAction("CHANGE") -> {
                GlobalState.handleToggle()
            }
        }
        // 结束当前的活动并从任务栈中移除该活动
        finishAndRemoveTask()
    }
}
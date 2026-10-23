package com.example.campus_app

import android.app.ActivityManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Migrate empty Recents records left by the former preview launch path.
        // Live tasks are never removed here; singleTask prevents new duplicates.
        val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        for (task in manager.appTasks) {
            val info = task.taskInfo ?: continue
            if (info.numActivities == 0 && info.baseIntent.component == componentName) {
                task.finishAndRemoveTask()
            }
        }
    }

    // Flutter calls this only after its own route stack declines Back. Keep
    // root Back consistent with Android 12+ launcher behavior on older devices
    // and explicit component launches too; profile/game Back still pops routes.
    override fun popSystemNavigator(): Boolean {
        return if (isTaskRoot) moveTaskToBack(false) else super.popSystemNavigator()
    }
}

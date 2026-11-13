package com.wrngwrld.chanyan

import android.content.Context
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onResume() {
        super.onResume()
        applyAppSwitcherCover()
    }

    override fun onPause() {
        // Before the recents screen takes its picture, with the setting as
        // it is now.
        applyAppSwitcherCover()
        super.onPause()
    }

    /// With "Hide in the app switcher" on, recents shows nothing of the app.
    /// Before Android 13 that also blocks screenshots, the only way there.
    private fun applyAppSwitcherCover() {
        // The setting, as shared_preferences keeps it (SettingsProvider).
        val cover = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean("flutter.coverInAppSwitcher", false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(!cover)
        } else if (cover) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}

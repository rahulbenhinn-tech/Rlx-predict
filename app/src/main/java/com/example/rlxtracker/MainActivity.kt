package com.example.rlxtracker

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var pm: MediaProjectionManager
    private val launcher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { res ->
        if (res.resultCode == Activity.RESULT_OK && res.data != null) {
            startForegroundService(Intent(this, TrackerOverlayService::class.java).apply {
                putExtra("CODE", res.resultCode)
                putExtra("DATA", res.data)
            })
            moveTaskToBack(true)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
        }
        val btn = Button(this).apply {
            text = "START RLX TRACKER"
            setTextColor(Color.GREEN)
            setBackgroundColor(Color.rgb(0, 60, 0))
            setOnClickListener {
                if (!Settings.canDrawOverlays(this@MainActivity)) {
                    startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                } else {
                    launcher.launch(pm.createScreenCaptureIntent())
                }
            }
        }
        layout.addView(btn)
        setContentView(layout)
    }
}

package com.example.rlxtracker

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.WindowManager
import android.widget.*

class TrackerOverlayService : Service() {
    private lateinit var wm: WindowManager
    private lateinit var root: FrameLayout
    private lateinit var bar: LinearLayout
    private lateinit var view: TrackerCanvasView
    private lateinit var params: WindowManager.LayoutParams
    private var mp: MediaProjection? = null
    private var vd: VirtualDisplay? = null
    private var ir: ImageReader? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val chId = "rlx_ch"
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(chId, "RLX", NotificationManager.IMPORTANCE_LOW)
        )
        startForeground(1, Notification.Builder(this, chId).setContentTitle("RLX Active").setSmallIcon(android.R.drawable.ic_menu_compass).build())

        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        root = FrameLayout(this)
        view = TrackerCanvasView(this)
        params = WindowManager.LayoutParams(-1, -1, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE, PixelFormat.TRANSLUCENT)

        bar = LinearLayout(this).apply { setBackgroundColor(Color.argb(200, 0, 20, 0)) }
        fun addBtn(t: String, c: Int, fn: () -> Unit) {
            bar.addView(Button(this).apply { text = t; setTextColor(c); setBackgroundColor(Color.TRANSPARENT); setOnClickListener { fn() } })
        }
        addBtn("CALIB", Color.GREEN) { setTouch(false); view.startCalibration() }
        addBtn("PLAY", Color.CYAN) { setTouch(true); view.startTracking() }
        addBtn("RESET", Color.YELLOW) { view.resetSpin() }
        addBtn("X", Color.RED) { stopSelf() }

        val bp = WindowManager.LayoutParams(-2, -2, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT).apply { gravity = Gravity.TOP or Gravity.END; y = 80 }
        root.addView(view)
        wm.addView(root, params)
        wm.addView(bar, bp)

        val code = intent?.getIntExtra("CODE", Activity.RESULT_CANCELED) ?: return START_NOT_STICKY
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra("DATA", Intent::class.java)
        else @Suppress("DEPRECATION") intent.getParcelableExtra("DATA")
        if (data == null) return START_NOT_STICKY

        mp = (getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager).getMediaProjection(code, data)
        val m = resources.displayMetrics
        val w = m.widthPixels / 2
        val h = m.heightPixels / 2
        ir = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
        vd = mp?.createVirtualDisplay("RLX", w, h, m.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, ir?.surface, null, null)
        ir?.setOnImageAvailableListener({ r ->
            val img = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            val p = img.planes[0]
            view.processFrame(p.buffer, w, h, p.rowStride, m.widthPixels, m.heightPixels)
            img.close()
        }, null)
        return START_STICKY
    }

    private fun setTouch(pass: Boolean) {
        params.flags = if (pass) WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        else WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        wm.updateViewLayout(root, params)
    }

    override fun onDestroy() {
        super.onDestroy()
        vd?.release(); mp?.stop()
        if (::root.isInitialized) wm.removeView(root)
        if (::bar.isInitialized) wm.removeView(bar)
    }
    override fun onBind(intent: Intent?): IBinder? = null
}

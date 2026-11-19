mkdir -p .github/workflows app/src/main/java/com/example/rlxtracker

cat << 'EOF' > .github/workflows/build.yml
name: Build Android APK
on:
  push:
    branches: [ "main" ]
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - uses: android-actions/setup-android@v3
      - uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: '8.7'
      - run: gradle assembleDebug
      - uses: actions/upload-artifact@v4
        with:
          name: RLX-Tracker-Pro-APK
          path: app/build/outputs/apk/debug/app-debug.apk
EOF

cat << 'EOF' > settings.gradle
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "RLXTracker"
include ':app'
EOF

cat << 'EOF' > build.gradle
plugins {
    id 'com.android.application' version '8.3.2' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.22' apply false
}
EOF

cat << 'EOF' > gradle.properties
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
EOF

cat << 'EOF' > app/build.gradle
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}
android {
    namespace 'com.example.rlxtracker'
    compileSdk 34
    defaultConfig {
        applicationId "com.example.rlxtracker"
        minSdk 26
        targetSdk 34
        versionCode 2
        versionName "2.0"
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = '17' }
}
dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
}
EOF

cat << 'EOF' > app/src/main/AndroidManifest.xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://android.com">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
    <application android:label="RLX Vision Pro" android:theme="@style/Theme.AppCompat.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name=".TrackerOverlayService" android:exported="false" android:foregroundServiceType="mediaProjection" />
    </application>
</manifest>
EOF
cat << 'EOF' > app/src/main/java/com/example/rlxtracker/MainActivity.kt
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
EOF

cat << 'EOF' > app/src/main/java/com/example/rlxtracker/TrackerOverlayService.kt
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
            val p = img.planes
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
EOF
cat << 'EOF' > app/src/main/java/com/example/rlxtracker/TrackerCanvasView.kt
package com.example.rlxtracker

import android.content.Context
import android.graphics.*
import android.view.MotionEvent
import android.view.View
import java.nio.ByteBuffer
import kotlin.math.*

class TrackerCanvasView(context: Context) : View(context) {
    private val nums = intArrayOf(0,32,15,19,4,21,2,25,17,34,6,27,13,36,11,30,8,23,10,5,24,16,33,1,20,14,31,9,22,18,29,7,28,12,35,3,26)
    private var cx = 0f; private var cy = 0f; private var rx = 0f; private var ry = 0f; private var inRatio = 0.72f
    private var calib = false; private var track = false
    private val pts = mutableListOf<PointF>()
    private var prev: ByteArray? = null

    private var estVel = 0.0; private var err = 1.0; private var lastT = 0.0; private var lastA = 0.0; private var locked = false
    private data class S(val a: Double, val t: Double, val x: Float, val y: Float, val v: Double)
    private val bHist = mutableListOf<S>()
    private val zHist = mutableListOf<S>()
    private var status = "Tap CALIB (Center, Right Rim, Bottom Rim, 0-Ring)"
    private var pred = ""; private var info = ""

    private val pRing = Paint().apply { color = Color.argb(150,0,255,0); style = Paint.Style.STROKE; strokeWidth = 3.5f }
    private val pIn = Paint().apply { color = Color.argb(150,0,200,255); style = Paint.Style.STROKE; strokeWidth = 3.5f }
    private val pBall = Paint().apply { color = Color.YELLOW }
    private val pZero = Paint().apply { color = Color.GREEN }
    private val pTxt = Paint().apply { color = Color.GREEN; textSize = 32f; typeface = Typeface.MONOSPACE; setShadowLayer(4f,0f,0f,Color.BLACK) }
    private val pPred = Paint().apply { color = Color.WHITE; textSize = 82f; typeface = Typeface.DEFAULT_BOLD; textAlign = Paint.Align.CENTER; setShadowLayer(12f,0f,0f,Color.GREEN) }

    fun startCalibration() { calib = true; track = false; pts.clear(); status = "1/4: Tap CENTER"; invalidate() }
    fun startTracking() {
        if (rx <= 0f) { status = "Calibrate first!"; invalidate(); return }
        calib = false; track = true; resetSpin(); status = "TRACKING"
    }
    fun resetSpin() { bHist.clear(); zHist.clear(); prev = null; locked = false; estVel = 0.0; err = 1.0; pred = ""; info = ""; postInvalidate() }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (!calib || e.action != MotionEvent.ACTION_DOWN) return false
        pts.add(PointF(e.x, e.y))
        when (pts.size) {
            1 -> status = "2/4: Tap RIGHT Rim"
            2 -> status = "3/4: Tap BOTTOM Rim"
            3 -> status = "4/4: Tap GREEN 0 Ring"
            4 -> {
                cx = pts.x; cy = pts.y
                rx = abs(pts.x - cx).coerceAtLeast(30f)
                ry = abs(pts.y - cy).coerceAtLeast(30f)
                inRatio = hypot((pts.x - cx) / rx, (pts.y - cy) / ry).coerceIn(0.45f, 0.92f)
                calib = false; status = "Ready! Tap PLAY"
            }
        }
        invalidate(); return true
    }

    private fun wheelAngle(x: Float, y: Float) = atan2(((y - cy) / ry).toDouble(), ((x - cx) / rx).toDouble())

    fun processFrame(buf: ByteBuffer, w: Int, h: Int, stride: Int, sw: Int, sh: Int) {
        if (!track || rx <= 0f) return
        val sx = w.toFloat() / sw; val sy = h.toFloat() / sh
        val scx = cx * sx; val scy = cy * sy; val srx = rx * sx; val sry = ry * sy
        val bytes = buf.remaining(); val cur = ByteArray(bytes); buf.get(cur)
        val prv = prev; if (prv == null || prv.size != bytes) { prev = cur; return }

        var bW = 0.0; var sBx = 0.0; var sBy = 0.0; var sGx = 0.0; var sGy = 0.0; var gC = 0
        val minY = max(0, (scy - sry * 1.15f).toInt()); val maxY = min(h - 1, (scy + sry * 1.15f).toInt())
        val minX = max(0, (scx - srx * 1.15f).toInt()); val maxX = min(w - 1, (scx + srx * 1.15f).toInt())

        for (y in minY until maxY step 2) {
            val row = y * stride; val ny = (y - scy) / sry
            for (x in minX until maxX step 2) {
                val nd = hypot((x - scx) / srx, ny)
                val i = row + x * 4; if (i + 2 >= bytes) continue
                val r = cur[i].toInt() and 255; val g = cur[i+1].toInt() and 255; val b = cur[i+2].toInt() and 255
                if (nd in 0.86f..1.09f) {
                    val diff = abs(r - (prv[i].toInt() and 255)) + abs(g - (prv[i+1].toInt() and 255)) + abs(b - (prv[i+2].toInt() and 255))
                    val luma = (r + g + b) / 3
                    if (luma > 205 && diff > 65) { val wt = (luma + diff).toDouble(); sBx += (x/sx)*wt; sBy += (y/sy)*wt; bW += wt }
                }
                if (nd in (inRatio * 0.85f)..(inRatio * 1.15f) && g > 100 && g > r * 1.45 && g > b * 1.45) {
                    sGx += x / sx; sGy += y / sy; gC++
                }
            }
        }
        prev = cur
        val now = System.nanoTime() / 1e9

        if (bW > 0) {
            val bx = (sBx / bW).toFloat(); val by = (sBy / bW).toFloat(); val ang = wheelAngle(bx, by)
            if (locked && (now - lastT) in 0.008..0.25) {
                var da = ang - lastA; while (da > PI) da -= 2*PI; while (da < -PI) da += 2*PI
                val rv = da / (now - lastT)
                if (abs(rv) < 18.0) {
                    err += 0.08; val k = err / (err + 0.35); estVel += k * (rv - estVel); err *= (1.0 - k)
                    bHist.add(S(ang, now, bx, by, estVel)); if (bHist.size > 60) bHist.removeAt(0)
                }
            } else locked = true
            lastA = ang; lastT = now
        }
        if (gC >= 3) {
            val zx = (sGx / gC).toFloat(); val zy = (sGy / gC).toFloat()
            zHist.add(S(wheelAngle(zx, zy), now, zx, zy, 0.0)); if (zHist.size > 50) zHist.removeAt(0)
        }

        if (bHist.size >= 14 && zHist.size >= 6) {
            val subZ = zHist.takeLast(10); val dtZ = subZ.last().t - subZ.first().t
            var dZ = 0.0; for (i in 1 until subZ.size) { var d = subZ[i].a - subZ[i-1].a; while (d > PI) d -= 2*PI; while (d < -PI) d += 2*PI; dZ += d }
            val wVel = if (dtZ > 0.02) dZ / dtZ else 0.0

            val rec = bHist.takeLast(10); val dtB = rec.last().t - rec.first().t
            val decel = if (dtB > 0.05) abs((abs(rec.last().v) - abs(rec.first().v)) / dtB).coerceIn(0.45, 1.55) else 0.85
            val spd = abs(estVel)
            info = String.format("Ball: %.2f | Decel: %.2f | Wheel: %.2f", estVel, decel, wVel)

            if (pred.isEmpty() && spd in 1.85..2.65) {
                val tDrop = ((spd - 1.18) / decel).coerceIn(0.55, 1.75)
                val fBall = bHist.last().a + estVel * tDrop - 0.5 * sign(estVel) * decel * tDrop * tDrop
                val fZero = zHist.last().a + wVel * tDrop
                var rel = (fBall - fZero) % (2 * PI); if (rel < 0) rel += 2 * PI
                val idx = ((rel / (2 * PI / 37.0)).toInt()) % 37
                val m = nums[idx]; val n1 = nums[(idx+36)%37]; val n2 = nums[(idx+1)%37]; val n3 = nums[(idx+35)%37]; val n4 = nums[(idx+2)%37]
                pred = "$m  [$n3 · $n1 · $m · $n2 · $n4]"
                status = "LOCKED (t=${String.format("%.2fs", tDrop)})"
            }
        }
        postInvalidate()
    }

    override fun onDraw(c: Canvas) {
        super.onDraw(c)
        c.drawText(status, 25f, 100f, pTxt)
        if (info.isNotEmpty()) c.drawText(info, 25f, 140f, pTxt)
        if (rx > 0f) {
            c.drawOval(RectF(cx-rx, cy-ry, cx+rx, cy+ry), pRing)
            c.drawOval(RectF(cx-rx*inRatio, cy-ry*inRatio, cx+rx*inRatio, cy+ry*inRatio), pIn)
        }
        bHist.lastOrNull()?.let { c.drawCircle(it.x, it.y, 14f, pBall) }
        zHist.lastOrNull()?.let { c.drawCircle(it.x, it.y, 12f, pZero) }
        if (pred.isNotEmpty()) c.drawText(pred, width / 2f, height * 0.44f, pPred)
    }
}
EOF

git add . && git commit -m "Build RLX Vision Pro" && git push origin main

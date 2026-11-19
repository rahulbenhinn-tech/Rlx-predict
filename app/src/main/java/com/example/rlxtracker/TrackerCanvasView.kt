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
                cx = pts[0].x; cy = pts[0].y
                rx = abs(pts[1].x - cx).coerceAtLeast(30f)
                ry = abs(pts[2].y - cy).coerceAtLeast(30f)
                inRatio = hypot((pts[3].x - cx) / rx, (pts[3].y - cy) / ry).coerceIn(0.45f, 0.92f)
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

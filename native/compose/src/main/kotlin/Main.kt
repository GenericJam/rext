// rext — Compose Desktop render backend.
//
// The universal baseline renderer: one Kotlin/Compose (Skia) codebase that runs
// on macOS, Windows, and Linux with consistent styling. Implements the rext
// render protocol (see rext/guides/render_protocol.md) over the socket
// transport — the same wire format the SwiftUI renderer uses.
//
// Connect: REXT_PORT (bridge port), REXT_WINDOW (which window to draw).
// Run:     ./gradlew run   (REXT_PORT / REXT_WINDOW from the environment)

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.Button
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.platform.Font
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import java.awt.Taskbar
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.net.Socket
import javax.imageio.ImageIO
import kotlin.concurrent.thread
import kotlin.system.exitProcess
import org.jetbrains.skia.Image
import org.json.JSONArray
import org.json.JSONObject

// ── Render-tree model ────────────────────────────────────────────────────────

class RNode(val type: String, private val props: JSONObject, val children: List<RNode>) {
  fun str(k: String): String? = if (props.has(k)) props.optString(k) else null
  fun num(k: String): Int? = if (props.has(k)) props.optInt(k) else null

  companion object {
    fun parse(o: JSONObject): RNode {
      val kids = ArrayList<RNode>()
      val arr = o.optJSONArray("children") ?: JSONArray()
      for (i in 0 until arr.length()) kids.add(parse(arr.getJSONObject(i)))
      return RNode(o.optString("type", "box"), o.optJSONObject("props") ?: JSONObject(), kids)
    }
  }
}

// Bundled font (src/main/resources/font/Inter.ttf) so text renders consistently
// across macOS/Windows/Linux instead of depending on each OS's system fonts.
private val InterFamily = FontFamily(Font("font/Inter.ttf"))

fun hexColor(s: String?): Color? {
  if (s == null || !s.startsWith("#") || s.length != 7) return null
  val v = s.substring(1).toInt(16)
  return Color((v shr 16 and 0xFF) / 255f, (v shr 8 and 0xFF) / 255f, (v and 0xFF) / 255f)
}

// ── Bridge: socket transport (4-byte length-framed JSON) ─────────────────────

class Bridge(private val port: Int, val target: String) {
  private var out: DataOutputStream? = null
  val root = mutableStateOf<RNode?>(null)

  fun start() {
    thread(isDaemon = true) {
      try {
        val sock = Socket("127.0.0.1", port)
        val input = DataInputStream(sock.getInputStream())
        out = DataOutputStream(sock.getOutputStream())
        send(JSONObject().put("t", "hello").put("renderer", "compose-desktop"))
        while (true) {
          val len = input.readInt() // 4-byte big-endian, matches Erlang {:packet, 4}
          val buf = ByteArray(len)
          input.readFully(buf)
          val obj = JSONObject(String(buf, Charsets.UTF_8))
          // One renderer draws one window; ignore frames for others.
          if (obj.optString("t") == "render" && obj.optString("window") == target) {
            root.value = RNode.parse(obj.getJSONObject("tree"))
          }
        }
      } catch (_: Exception) {
        // Connection ended (BEAM gone) — quit so we don't orphan the renderer.
        exitProcess(0)
      }
    }
  }

  fun sendEvent(event: String, tag: String) {
    send(JSONObject().put("t", "event").put("window", target).put("event", event).put("tag", tag))
  }

  private fun send(o: JSONObject) {
    val bytes = o.toString().toByteArray(Charsets.UTF_8)
    val d = out ?: return
    synchronized(d) {
      d.writeInt(bytes.size)
      d.write(bytes)
      d.flush()
    }
  }
}

// ── Compose views ────────────────────────────────────────────────────────────

@Composable
fun NodeView(node: RNode, bridge: Bridge) {
  when (node.type) {
    "column" -> {
      var m: Modifier = Modifier.fillMaxSize()
      hexColor(node.str("background"))?.let { m = m.background(it) }
      m = m.padding((node.num("padding") ?: 0).dp)
      Column(modifier = m, verticalArrangement = Arrangement.spacedBy((node.num("spacing") ?: 8).dp)) {
        node.children.forEach { NodeView(it, bridge) }
      }
    }
    "row" ->
      Row(
        modifier = Modifier.padding((node.num("padding") ?: 0).dp),
        horizontalArrangement = Arrangement.spacedBy((node.num("spacing") ?: 8).dp),
      ) {
        node.children.forEach { NodeView(it, bridge) }
      }
    "text" ->
      Text(
        text = node.str("text") ?: "",
        fontSize = (node.num("font_size") ?: 15).sp,
        color = hexColor(node.str("text_color")) ?: Color.Unspecified,
        fontFamily = InterFamily,
      )
    "button" ->
      Button(onClick = { node.str("on_click")?.let { bridge.sendEvent("click", it) } }) {
        Text(node.str("text") ?: "", fontFamily = InterFamily)
      }
    else -> Column { node.children.forEach { NodeView(it, bridge) } }
  }
}

// Optional per-app branding: REXT_ICON points at any image file loadable by
// Skia (PNG/JPEG/etc). No default — an app that doesn't set it gets the
// platform's default window icon, same as before this existed.
fun loadIcon(path: String?): Painter? {
  if (path.isNullOrBlank()) return null
  return try {
    BitmapPainter(Image.makeFromEncoded(File(path).readBytes()).toComposeImageBitmap())
  } catch (e: Exception) {
    System.err.println("[rext] REXT_ICON=$path failed to load: ${e.message}")
    null
  }
}

// AWT's Frame.setIconImage (what Window(icon=) sets under the hood) covers
// the title-bar/taskbar icon on Linux and Windows, but macOS ignores it for
// the Dock — that needs java.awt.Taskbar.setIconImage explicitly. Harmless
// no-op on platforms without Taskbar support.
fun setDockIcon(path: String?) {
  if (path.isNullOrBlank()) return
  try {
    if (Taskbar.isTaskbarSupported()) {
      val taskbar = Taskbar.getTaskbar()
      if (taskbar.isSupported(Taskbar.Feature.ICON_IMAGE)) {
        taskbar.iconImage = ImageIO.read(File(path))
      }
    }
  } catch (e: Exception) {
    System.err.println("[rext] REXT_ICON=$path dock icon failed: ${e.message}")
  }
}

fun main() {
  val port = (System.getenv("REXT_PORT") ?: "8137").toInt()
  val target = System.getenv("REXT_WINDOW") ?: "main"
  val iconPath = System.getenv("REXT_ICON")
  val icon = loadIcon(iconPath)
  setDockIcon(iconPath)
  val bridge = Bridge(port, target)
  bridge.start()

  application {
    // Closing the window exits the app; the dropped socket then halts the BEAM
    // under `mix rext.run` (see PLAN.md lifecycle).
    Window(
      onCloseRequest = ::exitApplication,
      title = target.replaceFirstChar { it.uppercase() },
      icon = icon,
    ) {
      val current = bridge.root.value
      if (current != null) NodeView(current, bridge) else Text("Waiting for BEAM…")
    }
  }
}

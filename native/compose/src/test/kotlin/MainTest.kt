import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

// REXT_ICON is optional per-app branding — these pin loadIcon's fallback
// behavior so a missing/blank/bad path degrades to "no icon" rather than
// crashing the renderer.
class MainTest {
  @Test
  fun `loadIcon returns null for a null path`() {
    assertNull(loadIcon(null))
  }

  @Test
  fun `loadIcon returns null for a blank path`() {
    assertNull(loadIcon("   "))
  }

  @Test
  fun `loadIcon returns null when the file does not exist`() {
    assertNull(loadIcon("/definitely/not/a/real/path.png"))
  }

  @Test
  fun `loadIcon returns a painter for a valid image file`() {
    val tmp = File.createTempFile("rext-icon-test", ".png")
    tmp.deleteOnExit()
    ImageIO.write(BufferedImage(4, 4, BufferedImage.TYPE_INT_ARGB), "png", tmp)

    assertNotNull(loadIcon(tmp.absolutePath))
  }
}

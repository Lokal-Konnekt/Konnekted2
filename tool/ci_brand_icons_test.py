"""Icon-generation regression tests: run after gen_lokal_launcher_icons.py."""
import unittest
from pathlib import Path
from PIL import Image

class BrandIconsTest(unittest.TestCase):
    def test_sticker_mask_alignment_and_square_art(self):
        base = Image.open("assets/branding/lokal_icon.png").convert("RGBA")
        mask = Image.open("assets/branding/lokal_icon_sticker.png").convert("RGBA")
        self.assertEqual(base.size, (512, 512))
        self.assertEqual(mask.size, base.size)
        self.assertEqual(base.getpixel((0, 0))[3], 255)  # full bleed
        self.assertEqual(mask.getpixel((0, 0))[3], 0)
        self.assertEqual(mask.getpixel((445, 255))[3], 255)
        self.assertEqual(mask.getpixel((260, 256))[3], 0)

    def test_android_accent_variants_and_transparency(self):
        root = Path("android/app/src/main/res")
        for color in ("lime", "purple", "blue", "orange", "chartreuse"):
            icon = Image.open(root / f"drawable-xxxhdpi/ic_lokal_fg_{color}.png").convert("RGBA")
            self.assertEqual(icon.size, (432, 432))
            self.assertEqual(icon.getpixel((0, 0))[3], 0)
        lime = Image.open(root / "drawable-xxxhdpi/ic_lokal_fg_lime.png").convert("RGBA")
        blue = Image.open(root / "drawable-xxxhdpi/ic_lokal_fg_blue.png").convert("RGBA")
        self.assertNotEqual(lime.getpixel((335, 215)), blue.getpixel((335, 215)))
        self.assertEqual(lime.getpixel((216, 216)), blue.getpixel((216, 216)))

    def test_legacy_corners_and_themed_monochrome(self):
        root = Path("android/app/src/main/res")
        square = Image.open(root / "mipmap-xxxhdpi/launcher_icon.png").convert("RGBA")
        self.assertEqual(square.getpixel((0, 0))[3], 255)
        mono = Image.open(root / "drawable-xxxhdpi/ic_lokal_fg_mono.png").convert("RGBA")
        self.assertEqual(mono.getpixel((0, 0))[3], 0)
        self.assertGreater(mono.getpixel((216, 153))[3], 0)

if __name__ == "__main__":
    unittest.main()

import pathlib
import tempfile
import unittest
import zipfile

from extract_samsung_swap_assets import extract_apk_assets


class ExtractSamsungSwapAssetsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.apk = self.root / "fixture.apk"
        with zipfile.ZipFile(self.apk, "w") as archive:
            archive.writestr(
                "assets/flutter_assets/assets/firmwares/DA41-00814A.mot",
                b"firmware-a",
            )
            archive.writestr(
                "assets/flutter_assets/assets/firmwares/DA41-00814D_0459G.mot",
                b"firmware-g",
            )
            archive.writestr(
                "assets/flutter_assets/assets/firmwares/DA41-00814D_0459M.bin",
                b"firmware-m",
            )
            archive.writestr(
                "assets/flutter_assets/assets/images/app_logo.jpg",
                b"image-logo",
            )
            archive.writestr(
                "assets/flutter_assets/FontManifest.json",
                b"{}",
            )
            archive.writestr(
                "assets/flutter_assets/assets/sounds/success.mp3",
                b"sound",
            )
            archive.writestr("classes.dex", b"not-a-flutter-asset")

    def tearDown(self):
        self.temp.cleanup()

    def test_default_extracts_known_firmware_and_images(self):
        output = self.root / "default"
        extracted = extract_apk_assets(self.apk, output)
        self.assertEqual(len(extracted), 4)
        self.assertTrue(
            (output / "firmwares/DA41-00814A.mot").read_bytes()
            == b"firmware-a"
        )
        self.assertTrue((output / "images/app_logo.jpg").is_file())
        self.assertFalse((output / "FontManifest.json").exists())

    def test_all_preserves_flutter_asset_tree_and_skips_dex(self):
        output = self.root / "all"
        extracted = extract_apk_assets(self.apk, output, include_all=True)
        self.assertEqual(len(extracted), 6)
        self.assertEqual(
            (output / "assets/firmwares/DA41-00814A.mot").read_bytes(),
            b"firmware-a",
        )
        self.assertTrue((output / "FontManifest.json").is_file())
        self.assertTrue((output / "assets/sounds/success.mp3").is_file())
        self.assertFalse((output / "classes.dex").exists())


if __name__ == "__main__":
    unittest.main()

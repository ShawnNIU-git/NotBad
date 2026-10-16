from PIL import Image

from notbad_recog.image_utils import bbox_to_pixels, crop_bbox, resize_max_side


def test_bbox_to_pixels_scales_and_clamps():
    assert bbox_to_pixels([100, 500, 600, 1000], (2000, 1000)) == (200, 500, 1200, 1000)
    assert bbox_to_pixels([-50, -50, 1100, 1100], (100, 100)) == (0, 0, 100, 100)


def test_crop_bbox_adds_padding():
    img = Image.new("RGB", (1000, 1000))
    assert crop_bbox(img, [100, 100, 200, 200], pad=10).size == (120, 120)


def test_resize_keeps_small_images():
    img = Image.new("RGB", (300, 200))
    assert resize_max_side(img, 1000) is img
    assert resize_max_side(img, 150).size == (150, 100)

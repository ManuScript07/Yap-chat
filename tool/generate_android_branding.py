"""Build EN Android assets from supplied artwork; retain existing RU geometry."""
from pathlib import Path
import xml.etree.ElementTree as ET
import math
import re
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"
source = Image.open(ROOT / "assets/logo/adaptive_icon_foreground_en.png").convert("RGBA")
source = source.crop(source.getbbox())

def fit_art(reference, bounds):
    left, top, right, bottom = bounds
    art = source.copy()
    art.thumbnail((right - left, bottom - top), Image.Resampling.LANCZOS)
    result = Image.new("RGBA", reference.size)
    result.alpha_composite(art, (left + (right - left - art.width) // 2,
                                 top + (bottom - top - art.height) // 2))
    return result

def centered_bounds(size, bounds):
    width, height = bounds[2] - bounds[0], bounds[3] - bounds[1]
    left, top = (size[0] - width) // 2, (size[1] - height) // 2
    return left, top, left + width, top + height

def center_art(image):
    bounds = image.getbbox()
    result = Image.new('RGBA', image.size)
    result.alpha_composite(image.crop(bounds), centered_bounds(image.size, bounds)[:2])
    return result

for directory in RES.glob("mipmap-*dpi"):
    for name in ("ic_launcher_foreground", "ic_launcher_monochrome", "ic_launcher"):
        reference = Image.open(directory / f"{name}.png").convert("RGBA")
        if name == "ic_launcher":
            pixels = list(reference.get_flattened_data())
            blue = Image.new("L", reference.size)
            blue.putdata([255 if b > 100 and g > 80 and a > 250 else 0
                          for r, g, b, a in pixels])
            x0, y0, x1, y1 = blue.getbbox()
            mask = Image.new("L", reference.size)
            mask.putdata([255 if a > 200 and max(r, g, b) < 80 and
                          x0 <= i % reference.width < x1 and y0 <= i // reference.width < y1 else 0
                          for i, (r, g, b, a) in enumerate(pixels)])
            bounds = mask.getbbox()
            art_width, art_height = bounds[2] - bounds[0], bounds[3] - bounds[1]
            left, top = (x0 + x1 - art_width) // 2, (y0 + y1 - art_height) // 2
            bounds = left, top, left + art_width, top + art_height
            background = reference.copy()
            background.putdata([(3, 166, 225, a) if a > 200 and
                                x0 <= i % reference.width < x1 and y0 <= i // reference.width < y1
                                else (r, g, b, a)
                                for i, (r, g, b, a) in enumerate(pixels)])
            background.alpha_composite(fit_art(reference, bounds))
            output = background
        else:
            bounds = reference.getbbox()
            centered = centered_bounds(reference.size, bounds)
            output = center_art(fit_art(reference, centered))
            if name.endswith("monochrome"):
                white = Image.new("RGBA", output.size, "white")
                white.putalpha(output.getchannel("A"))
                output = white
        output.save(directory / f"{name}_en.png")

(RES / "mipmap-anydpi-v26/ic_launcher_en.xml").write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@mipmap/ic_launcher_background"/>
  <foreground android:drawable="@mipmap/ic_launcher_foreground_en"/>
  <monochrome android:drawable="@mipmap/ic_launcher_monochrome_en"/>
</adaptive-icon>
''', encoding="utf-8")

original = RES / "drawable/ic_notification_ru.xml"
if not original.exists():
    original.write_bytes((RES / "drawable/ic_notification.xml").read_bytes())
(RES / "drawable-ru").mkdir(exist_ok=True)
(RES / "drawable-ru/ic_notification.xml").write_bytes(original.read_bytes())

def path_bounds(paths):
    """Exact bounds of the supplied M/L/C/Z artwork, including Bezier extrema."""
    points = []
    for data in paths:
        tokens = re.findall(r'[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?', data)
        i, command, current, start = 0, None, (0.0, 0.0), (0.0, 0.0)
        while i < len(tokens):
            if tokens[i].isalpha():
                command = tokens[i]
                i += 1
            if command == 'Z':
                current = start
                continue
            assert command in ('M', 'L', 'C'), f'Unsupported SVG command: {command}'
            count = 6 if command == 'C' else 2
            values = list(map(float, tokens[i:i+count]))
            i += count
            end = tuple(values[-2:])
            points.extend([current, end] if command != 'M' else [end])
            if command == 'C':
                controls = [current, tuple(values[:2]), tuple(values[2:4]), end]
                times = set()
                for axis in (0, 1):
                    a, b, c, d = [p[axis] for p in controls]
                    qa, qb, qc = -a+3*b-3*c+d, 2*(a-2*b+c), b-a
                    if abs(qa) < 1e-12:
                        roots = [-qc/qb] if abs(qb) > 1e-12 else []
                    else:
                        delta = qb*qb-4*qa*qc
                        roots = [(-qb+sign*math.sqrt(delta))/(2*qa) for sign in (-1, 1)] if delta >= 0 else []
                    times.update(t for t in roots if 0 < t < 1)
                for t in times:
                    points.append(tuple((1-t)**3*controls[0][axis] + 3*(1-t)**2*t*controls[1][axis]
                        + 3*(1-t)*t*t*controls[2][axis] + t**3*controls[3][axis] for axis in (0, 1)))
            current = end
            if command == 'M':
                start, command = end, 'L'
    return min(p[0] for p in points), min(p[1] for p in points), max(p[0] for p in points), max(p[1] for p in points)

notification_svg = ET.parse(ROOT / 'assets/logo/icon_yapchat_foreground_en.svg').getroot()
_, _, width, height = notification_svg.attrib['viewBox'].split()
notification_paths = [p.attrib['d'] for p in notification_svg.iter('{http://www.w3.org/2000/svg}path')]
x0, y0, x1, y1 = path_bounds(notification_paths)
# Translate only: retain the existing 24dp size, viewport, and glyph scale.
offset_x = float(width)/2 - (x0+x1)/2
offset_y = float(height)/2 - (y0+y1)/2
notification_xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android" '
    f'android:width="24dp" android:height="24dp" android:viewportWidth="{width}" android:viewportHeight="{height}">\n'
    f'  <group android:translateX="{offset_x:.8f}" android:translateY="{offset_y:.8f}">\n'
    + ''.join(f'    <path android:fillColor="@android:color/white" android:pathData="{p}"/>\n' for p in notification_paths)
    + '  </group>\n</vector>\n')
(RES / 'drawable/ic_notification_en.xml').write_text(notification_xml, encoding='utf-8')
(RES / 'drawable/ic_notification.xml').write_text(notification_xml, encoding='utf-8')

for language, filename in [('ru', 'icon_yapchat_foregraund.svg'), ('en', 'icon_yapchat_foreground_en.svg')]:
    logo = ET.parse(ROOT / 'assets/logo' / filename).getroot()
    paths = [p.attrib['d'] for p in logo.iter('{http://www.w3.org/2000/svg}path')]
    x0, y0, x1, y1 = path_bounds(paths)
    # Keep the original Russian native splash transform exactly. Only English
    # artwork is centered; the Russian Flutter splash uses its original asset.
    if language == 'ru':
        scale, tx, ty = 0.86624205, 76.0, 84.67898
    else:
        scale = 116.673 / (x1-x0)
        tx, ty = 144-scale*(x0+x1)/2, 144-scale*(y0+y1)/2
    svg_paths = ''.join(f'<path d="{p}"/>' for p in paths)
    if language == 'en':
        (ROOT / 'assets/logo/splash_logo_en.svg').write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="288" height="288" viewBox="0 0 288 288">'
            f'<g transform="translate({tx:.8f} {ty:.8f}) scale({scale:.8f})">{svg_paths}</g></svg>\n', encoding='utf-8')
    vector = ('<?xml version="1.0" encoding="utf-8"?>\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="288dp" android:height="288dp" android:viewportWidth="288" android:viewportHeight="288">\n'
        f'<group android:scaleX="{scale:.8f}" android:scaleY="{scale:.8f}" android:translateX="{tx:.8f}" android:translateY="{ty:.8f}">\n'
        + ''.join(f'<path android:fillColor="#FF000000" android:pathData="{p}"/>\n' for p in paths)
        + '</group></vector>\n')
    (RES / f'drawable/splash_icon_{language}.xml').write_text(vector, encoding='utf-8')
    background = ('<?xml version="1.0" encoding="utf-8"?>\n'
        '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">'
        '<item android:drawable="@color/yap_splash_primary"/>'
        f'<item android:drawable="@drawable/splash_icon_{language}" android:gravity="center"/>'
        '</layer-list>\n')
    (RES / f'drawable/launch_background_{language}.xml').write_text(background, encoding='utf-8')
(RES / 'drawable/splash_icon.xml').write_bytes((RES / 'drawable/splash_icon_en.xml').read_bytes())
(RES / 'drawable-ru/splash_icon.xml').write_bytes((RES / 'drawable/splash_icon_ru.xml').read_bytes())

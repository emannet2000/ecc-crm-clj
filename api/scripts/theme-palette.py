"""Replace legacy green CSS colors with navy, gold, and cool neutrals."""
import colorsys
import re
from pathlib import Path

HEX_COLOR = re.compile(r'#[\da-fA-F]{8}\b|#[\da-fA-F]{6}\b|#[\da-fA-F]{4}\b|#[\da-fA-F]{3}\b')


def remove_green(css):
    def replace(match):
        raw = match.group()[1:]
        raw = ''.join(char * 2 for char in raw) if len(raw) in (3, 4) else raw
        rgb = [int(raw[index:index + 2], 16) / 255 for index in (0, 2, 4)]
        hue, lightness, saturation = colorsys.rgb_to_hls(*rgb)
        if not (65 <= hue * 360 <= 185 and saturation > .025):
            return match.group()
        if .25 <= lightness <= .65 and saturation > .3:
            color = '916113' if lightness < .5 else 'e2b457'
        else:
            # Preserve lightness for readable text, surfaces and dark-mode borders.
            channels = colorsys.hls_to_rgb(218 / 360, lightness, min(saturation, .22))
            color = ''.join(f'{round(channel * 255):02x}' for channel in channels)
        return '#' + color + raw[6:]
    return HEX_COLOR.sub(replace, css)


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    source = root / 'web/public/css/app.css'
    css = remove_green(source.read_text())
    source.write_text(css)
    (root / 'web/dist/css/app.css').write_text(css)
    print('Updated source and deployed stylesheet')

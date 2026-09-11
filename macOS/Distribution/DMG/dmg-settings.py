"""Finder installation layout for dmgbuild 1.6.7.

Usage: dmgbuild -s dmg-settings.py -D "app=/path/to/Angel Live.app" AngelLive output.dmg
"""

import inspect
import json
from pathlib import Path


def settings_directory():
    # dmgbuild executes this file without defining __file__.
    return Path(inspect.getfile(settings_directory)).resolve().parent


assets = settings_directory()
layout = json.loads((assets / "layout.json").read_text(encoding="utf-8"))
app_argument = defines.get("app")  # Provided by dmgbuild.
if not app_argument:
    raise ValueError("Pass the exported application with -D app=/path/to/AngelLive.app")
application = Path(app_argument).expanduser().resolve()
if application.suffix != ".app" or not (application / "Contents" / "Info.plist").is_file():
    raise ValueError("The app argument must point to an exported macOS .app bundle")

format = "UDZO"
filesystem = "HFS+"
files = [str(application)]
symlinks = {"Applications": "/Applications"}
hide_extensions = [application.name]
background = str(assets / "background.tiff")
if not Path(background).is_file():
    raise FileNotFoundError("Render the DMG background before packaging")

window_rect = ((160, 160), (layout["width"], layout["height"]))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_spacing = 80
scroll_position = (0, 0)
label_pos = "bottom"
text_size = layout["labelSize"]
icon_size = layout["iconSize"]
icon_locations = {
    application.name: tuple(layout["applicationPosition"]),
    "Applications": tuple(layout["applicationsPosition"]),
}

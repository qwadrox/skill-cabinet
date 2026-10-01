from pathlib import Path

format = 'UDZO'
files = [defines['app']]
symlinks = {'Applications': '/Applications'}
background = defines['background']
icon = str(Path(defines['app']) / 'Contents/Resources/AppIcon.icns')
window_rect = ((200, 200), (660, 400))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 96
text_size = 14
icon_locations = {
    'Skill Cabinet.app': (170, 205),
    'Applications': (490, 205),
}

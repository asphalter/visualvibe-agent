#!/usr/bin/env python3
"""
Customizes KasmVNC Web UI with VisualVibe Agent branding:
- Replaces KasmVNC favicons with VisualVibe Agent icons
- Sets tab title permanently to 'VisualVibe Agent'
- Replaces sidebar logo with VisualVibe Agent branding card
- Injects FileBrowser Quantum quick-link in the sidebar
- Customizes transition / connecting splash screen with official VisualVibe Agent logo and 'Connecting...'
"""

import base64
import glob
import os
import re
import shutil
import sys

WWW_DIR = os.environ.get("KASMVNC_WWW_DIR", "/usr/share/kasmvnc/www")

if not os.path.isdir(WWW_DIR):
    print(f"[Brand] Notice: {WWW_DIR} does not exist, skipping branding.")
    sys.exit(0)

assets_dir = os.path.join(WWW_DIR, "assets")
os.makedirs(assets_dir, exist_ok=True)

# 1. Resolve and copy VisualVibe Agent official icons
config_dir = os.path.dirname(os.path.abspath(__file__))

potential_main_logos = [
    os.path.join("/etc/visualvibe/media", "visualvibe_icon.png"),
    os.path.join("/etc/visualvibe/media", "visualvibe.png"),
    os.path.join(config_dir, "../media/visualvibe_icon.png"),
    os.path.join(config_dir, "../media/visualvibe.png"),
    os.path.join(config_dir, "media/visualvibe_icon.png"),
    os.path.join(config_dir, "media/visualvibe.png"),
    os.path.join("/etc/visualvibe", "visualvibe_icon.png"),
    os.path.join("/etc/visualvibe", "visualvibe.png"),
]

potential_horizontal_logos = [
    os.path.join("/etc/visualvibe/media", "visualvibe_horizontal.png"),
    os.path.join(config_dir, "../media/visualvibe_horizontal.png"),
    os.path.join(config_dir, "media/visualvibe_horizontal.png"),
]

main_logo_path = next((p for p in potential_main_logos if os.path.isfile(p)), None)
horizontal_logo_path = next((p for p in potential_horizontal_logos if os.path.isfile(p)), None)


def get_mime(path):
    """Return MIME type for a given file path based on extension."""
    ext = os.path.splitext(path)[1].lower()
    if ext in [".jpg", ".jpeg"]:
        return "image/jpeg"
    elif ext == ".svg":
        return "image/svg+xml"
    return "image/png"


def get_data_uri(path):
    """Return (data_uri, mime) for small icons only (favicon use).
    FIX C-01: Large images are served as static files, not Data URIs.
    This function is retained only for the favicon <link> tag,
    which requires a Data URI for reliable cross-browser support.
    For images >50KB, we fall back to the asset path.
    """
    if not path or not os.path.isfile(path):
        return None, None
    mime = get_mime(path)
    size = os.path.getsize(path)
    if size > 51200:  # 50 KB threshold — use file reference instead
        return None, mime
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    return f"data:{mime};base64,{b64}", mime

# FIX C-01: Copy images to assets/ and reference by URL path, not inline Data URI.
# Images can be several MB — embedding them inline in HTML causes multi-MB HTML documents.

logo_mime = "image/png"
logo_asset_url = "./assets/visualvibe.png"       # default fallback URL
horizontal_asset_url = None
favicon_data_uri = None                           # only used for <link rel="icon"> (small logo only)

if main_logo_path:
    ext = os.path.splitext(main_logo_path)[1].lower()
    logo_mime = get_mime(main_logo_path)
    dest_logo = os.path.join(assets_dir, f"visualvibe{ext}")
    shutil.copy2(main_logo_path, dest_logo)
    logo_asset_url = f"./assets/visualvibe{ext}"
    
    # Also save as visualvibe_icon.png in assets
    shutil.copy2(main_logo_path, os.path.join(assets_dir, "visualvibe_icon.png"))

    media_dir = os.path.dirname(main_logo_path)
    # Replace KasmVNC bundled logos with matching sharp multi-resolution favicons
    for kasm_logo in glob.glob(os.path.join(assets_dir, "368_kasm_logo_only_*.png")):
        m = re.search(r"(\d+x\d+)", os.path.basename(kasm_logo))
        copied = False
        if m:
            dim = m.group(1)
            matching_favicon = os.path.join(media_dir, f"favicon_{dim}.png")
            if os.path.isfile(matching_favicon):
                shutil.copy2(matching_favicon, kasm_logo)
                copied = True
        if not copied:
            fav_fallback = os.path.join(media_dir, "favicon_32x32.png")
            if os.path.isfile(fav_fallback):
                shutil.copy2(fav_fallback, kasm_logo)
            else:
                shutil.copy2(main_logo_path, kasm_logo)

    # Copy favicon.ico and favicon pngs to assets and root www
    ico_src = os.path.join(media_dir, "favicon.ico")
    if os.path.isfile(ico_src):
        shutil.copy2(ico_src, os.path.join(assets_dir, "favicon.ico"))
        shutil.copy2(ico_src, os.path.join(WWW_DIR, "favicon.ico"))
    png32_src = os.path.join(media_dir, "favicon_32x32.png")
    if os.path.isfile(png32_src):
        shutil.copy2(png32_src, os.path.join(assets_dir, "favicon_32x32.png"))
        shutil.copy2(png32_src, os.path.join(assets_dir, "favicon.png"))
        shutil.copy2(png32_src, os.path.join(WWW_DIR, "favicon.png"))
    png16_src = os.path.join(media_dir, "favicon_16x16.png")
    if os.path.isfile(png16_src):
        shutil.copy2(png16_src, os.path.join(assets_dir, "favicon_16x16.png"))
    png180_src = os.path.join(media_dir, "favicon_180x180.png")
    if os.path.isfile(png180_src):
        shutil.copy2(png180_src, os.path.join(assets_dir, "favicon_180x180.png"))

    favicon_data_uri = "./assets/favicon.ico"
    size_kb = os.path.getsize(main_logo_path) // 1024
    print(f"[Brand] Main logo: {main_logo_path} ({size_kb} KB) → {logo_asset_url}")
else:
    favicon_data_uri = logo_asset_url
    print("[Brand] Notice: No primary VisualVibe Agent logo file found, using fallback path.")

if horizontal_logo_path:
    ext = os.path.splitext(horizontal_logo_path)[1].lower()
    dest_horiz = os.path.join(assets_dir, f"visualvibe_horizontal{ext}")
    shutil.copy2(horizontal_logo_path, dest_horiz)
    horizontal_asset_url = f"./assets/visualvibe_horizontal{ext}"
    size_kb = os.path.getsize(horizontal_logo_path) // 1024
    print(f"[Brand] Horizontal logo: {horizontal_logo_path} ({size_kb} KB) → {horizontal_asset_url}")

# 2. Splash Screen (Transition / Connecting) Configuration
splash_css = """
<style id="visualvibe-splash-style">
#noVNC_transition {
    position: fixed !important;
    top: 0 !important; left: 0 !important; bottom: 0 !important; right: 0 !important;
    background: #0f172a !important;
    background-image: none !important;
    color: #f1f5f9 !important;
    display: none;
    flex-direction: column !important;
    align-items: center !important;
    justify-content: center !important;
    z-index: 50 !important;
    transition: opacity 0.8s ease-in-out !important;
}
:root.noVNC_loading #noVNC_transition,
:root.noVNC_connecting #noVNC_transition,
:root.noVNC_disconnecting #noVNC_transition,
:root.noVNC_reconnecting #noVNC_transition {
    display: flex !important;
}
.noVNC_vv_logo_container {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    animation: vvPulse 2.5s infinite ease-in-out;
}
.noVNC_vv_logo {
    width: 140px;
    height: 140px;
    object-fit: contain;
    filter: drop-shadow(0 10px 25px rgba(56, 189, 248, 0.3));
}
.noVNC_vv_title {
    color: #ffffff;
    font-size: 26px;
    font-weight: 600;
    letter-spacing: 0.5px;
    margin-top: 16px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
}
#noVNC_transition_text {
    color: #94a3b8 !important;
    font-size: 16px !important;
    font-weight: 500 !important;
    letter-spacing: 0.8px !important;
    margin-top: 14px !important;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
}
.noVNC_vv_spinner {
    display: inline-flex;
    gap: 6px;
    margin-top: 20px;
}
.noVNC_vv_spinner div {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #38bdf8;
    animation: vvBounce 1.4s infinite ease-in-out both;
}
.noVNC_vv_spinner div:nth-child(1) { animation-delay: -0.32s; }
.noVNC_vv_spinner div:nth-child(2) { animation-delay: -0.16s; }
@keyframes vvBounce {
    0%, 80%, 100% { transform: scale(0); opacity: 0.3; }
    40% { transform: scale(1); opacity: 1; }
}
@keyframes vvPulse {
    0%, 100% { transform: scale(1); }
    50% { transform: scale(1.02); }
}
#noVNC_container {
    position: absolute !important;
    top: 0 !important;
    left: 0 !important;
    right: 0 !important;
    bottom: 0 !important;
    width: 100vw !important;
    height: 100vh !important;
    margin: 0 !important;
    padding: 0 !important;
    overflow: hidden !important;
}
#noVNC_container > canvas {
    display: block !important;
}
</style>
"""

# FIX C-01: Use asset URL, not Data URI, for the splash screen logo
splash_html = (
    '<div id="noVNC_transition">'
    '<div class="noVNC_vv_logo_container">'
    f'<img class="noVNC_vv_logo" src="{logo_asset_url}" alt="VisualVibe Agent">'
    '<div class="noVNC_vv_title">VisualVibe Agent</div>'
    '</div>'
    '<div id="noVNC_transition_text">Connecting...</div>'
    '<div><input type="button" id="noVNC_cancel_reconnect_button" value="Cancel" class="noVNC_submit"></div>'
    '<div class="noVNC_vv_spinner"><div></div><div></div><div></div></div>'
    '</div>'
)

# 3. Patch index.html and vnc.html
switch_window_html = (
    '<div id="noVNC_switch_window_button" class="noVNC_button_div" role="button" tabindex="0" '
    'style="display: flex; align-items: center; padding: 8px 10px; margin: 4px 0 6px 0; '
    'background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.12); border-radius: 6px; '
    'color: #ffffff; text-decoration: none; cursor: pointer; transition: all 0.2s ease; user-select: none;" '
    'onmouseover="this.style.background=\'rgba(255, 255, 255, 0.18)\'; this.style.borderColor=\'rgba(255, 255, 255, 0.3)\';" '
    'onmouseout="this.style.background=\'rgba(255, 255, 255, 0.08)\'; this.style.borderColor=\'rgba(255, 255, 255, 0.12)\';" '
    'onmousedown="this.style.transform=\'scale(0.97)\';" onmouseup="this.style.transform=\'none\';" '
    'onclick="window.kasmSwitchWindow && window.kasmSwitchWindow();" '
    'onkeydown="if(event.key===\'Enter\'||event.key===\' \'){event.preventDefault();window.kasmSwitchWindow&&window.kasmSwitchWindow();}" '
    'title="Switch active window (Alt+Tab)">'
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin-right: 10px; flex-shrink: 0; color: #38bdf8;"><rect x="2" y="7" width="13" height="13" rx="2"></rect><path d="M5 7V4a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3"></path></svg>'
    '<span style="font-size: 13px; font-weight: 500; letter-spacing: 0.3px; flex-grow: 1;">Switch Window</span>'
    '<span style="font-size: 10px; font-weight: 600; opacity: 0.65; background: rgba(255, 255, 255, 0.12); padding: 2px 6px; border-radius: 4px; font-family: -apple-system, BlinkMacSystemFont, monospace;">Alt+Tab</span>'
    '</div>'
)

open_browser_html = (
    '<div id="noVNC_open_browser_button" class="noVNC_button_div" role="button" tabindex="0" '
    'style="display: flex; align-items: center; padding: 8px 10px; margin: 4px 0 6px 0; '
    'background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.12); border-radius: 6px; '
    'color: #ffffff; text-decoration: none; cursor: pointer; transition: all 0.2s ease; user-select: none;" '
    'onmouseover="this.style.background=\'rgba(255, 255, 255, 0.18)\'; this.style.borderColor=\'rgba(255, 255, 255, 0.3)\';" '
    'onmouseout="this.style.background=\'rgba(255, 255, 255, 0.08)\'; this.style.borderColor=\'rgba(255, 255, 255, 0.12)\';" '
    'onmousedown="this.style.transform=\'scale(0.97)\';" onmouseup="this.style.transform=\'none\';" '
    'onclick="window.kasmOpenBrowser && window.kasmOpenBrowser();" '
    'onkeydown="if(event.key===\'Enter\'||event.key===\' \'){event.preventDefault();window.kasmOpenBrowser&&window.kasmOpenBrowser();}" '
    'title="Open or focus Chromium Browser">'
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin-right: 10px; flex-shrink: 0; color: #34d399;"><circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="12" r="4"></circle><line x1="21.17" y1="8" x2="12" y2="8"></line><line x1="3.95" y1="6.06" x2="8.54" y2="14"></line><line x1="10.88" y1="21.94" x2="15.46" y2="14"></line></svg>'
    '<span style="font-size: 13px; font-weight: 500; letter-spacing: 0.3px; flex-grow: 1;">Open Browser</span>'
    '<span style="font-size: 10px; font-weight: 600; opacity: 0.65; background: rgba(255, 255, 255, 0.12); padding: 2px 6px; border-radius: 4px; font-family: -apple-system, BlinkMacSystemFont, monospace;">Web</span>'
    '</div>'
)

browser_actions_script = (
    '<script id="noVNC_browser_actions_script">\n'
    'window.kasmSwitchWindow = function() {\n'
    '    try {\n'
    '        var u = window.UI;\n'
    '        if (u && u.rfb && u.rfb._rfbConnectionState === "connected") {\n'
    '            u.rfb.sendKey(65513, "AltLeft", true);\n'
    '            setTimeout(function() {\n'
    '                u.rfb.sendKey(65289, "Tab");\n'
    '                setTimeout(function() { u.rfb.sendKey(65513, "AltLeft", false); }, 120);\n'
    '            }, 30);\n'
    '            return;\n'
    '        }\n'
    '        var altBtn = document.getElementById("noVNC_toggle_alt_button");\n'
    '        var tabBtn = document.getElementById("noVNC_send_tab_button");\n'
    '        if (altBtn && tabBtn) {\n'
    '            if (!altBtn.classList.contains("noVNC_selected")) altBtn.click();\n'
    '            setTimeout(function() {\n'
    '                tabBtn.click();\n'
    '                setTimeout(function() {\n'
    '                    if (altBtn.classList.contains("noVNC_selected")) altBtn.click();\n'
    '                }, 120);\n'
    '            }, 30);\n'
    '        }\n'
    '    } catch (e) { console.error("Switch window error:", e); }\n'
    '};\n'
    'window.kasmOpenBrowser = function() {\n'
    '    try {\n'
    '        var u = window.UI;\n'
    '        if (u && u.rfb && u.rfb._rfbConnectionState === "connected") {\n'
    '            u.rfb.sendKey(65507, "ControlLeft", true);\n'
    '            u.rfb.sendKey(65513, "AltLeft", true);\n'
    '            setTimeout(function() {\n'
    '                u.rfb.sendKey(119, "KeyW");\n'
    '                setTimeout(function() {\n'
    '                    u.rfb.sendKey(65513, "AltLeft", false);\n'
    '                    u.rfb.sendKey(65507, "ControlLeft", false);\n'
    '                }, 120);\n'
    '            }, 30);\n'
    '            return;\n'
    '        }\n'
    '    } catch (e) { console.error("Open browser error:", e); }\n'
    '};\n'
    '// Default video quality to High (3) for new sessions and upgrade existing defaults\n'
    'try {\n'
    '    if (!localStorage.getItem("video_quality") || localStorage.getItem("video_quality") === "2") {\n'
    '        localStorage.setItem("video_quality", "3");\n'
    '    }\n'
    '    // Force "Native Resolution" display mode (resize=remote) by default\n'
    '    if (!localStorage.getItem("resize")) {\n'
    '        localStorage.setItem("resize", "remote");\n'
    '    }\n'
    '} catch(e) {}\n'
    '// Heartbeat keep-alive every 10 seconds to prevent reverse proxy (Nginx, Traefik, Cloudflare) idle timeouts\n'
    'setInterval(function() {\n'
    '    try {\n'
    '        var u = window.UI;\n'
    '        if (u && u.rfb && (u.connected || u.rfb._rfbConnectionState === "connected")) {\n'
    '            u.rfb.sendKeepAlive();\n'
    '        }\n'
    '    } catch(e) {}\n'
    '}, 10000);\n'
    '</script>\n'
)

if horizontal_asset_url:
    sidebar_brand_content = (
        f'<img src="{horizontal_asset_url}" '
        'style="height: 56px !important; width: auto !important; max-width: 98% !important; '
        'object-fit: contain; filter: drop-shadow(0 2px 5px rgba(0, 0, 0, 0.4)); display: block; margin: 0 auto;" '
        'alt="VisualVibe Agent">'
    )
else:
    sidebar_brand_content = (
        '<div style="display: flex; align-items: center; width: 100%;">'
        '<img src="./assets/visualvibe_icon.png" style="width: 38px !important; height: 38px !important; object-fit: contain; flex-shrink: 0; filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.4));" alt="VisualVibe Agent">'
        '<div style="display: flex; flex-direction: column; margin-left: 10px; line-height: 1.15; overflow: hidden; text-align: left;">'
        '<span style="color: #ffffff; font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, sans-serif; font-size: 15px; font-weight: 700; letter-spacing: 0.5px; white-space: nowrap; text-shadow: 0 0 8px rgba(56, 189, 248, 0.4);">VisualVibe</span>'
        '<span style="color: #38bdf8; font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, sans-serif; font-size: 11px; font-weight: 700; letter-spacing: 1.5px; text-transform: uppercase;">Agent</span>'
        '</div>'
        '</div>'
    )

replacement_logo_html = (
    '<h1 class="noVNC_logo" style="background: rgba(255, 255, 255, 0.08); '
    'border-radius: 8px; padding: 6px 8px; margin: 4px 0 6px 0; display: flex; '
    'align-items: center; justify-content: center; box-shadow: 0 2px 8px rgba(0,0,0,0.3); '
    'border: 1px solid rgba(255, 255, 255, 0.12);">'
    f'{sidebar_brand_content}'
    '</h1>\n'
    f'{switch_window_html}\n'
    f'{open_browser_html}\n'
    '<a href="/filebrowser/" target="_blank" rel="noopener noreferrer" id="noVNC_filebrowser_link" '
    'class="noVNC_button_div" style="display: flex; align-items: center; padding: 8px 10px; margin: 4px 0 10px 0; '
    'background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.12); border-radius: 6px; '
    'color: #ffffff; text-decoration: none; cursor: pointer; transition: all 0.2s ease;" '
    'onmouseover="this.style.background=\'rgba(255, 255, 255, 0.18)\'; this.style.borderColor=\'rgba(255, 255, 255, 0.3)\';" '
    'onmouseout="this.style.background=\'rgba(255, 255, 255, 0.08)\'; this.style.borderColor=\'rgba(255, 255, 255, 0.12)\';" '
    'onclick="event.preventDefault(); var u = \'/filebrowser/\'; if(window.location.port===\'8080\'){ u = window.location.protocol+\'//\'+window.location.hostname+\':8081/filebrowser/\'; } window.open(u, \'_blank\', \'noopener,noreferrer\');" '
    'title="Open VisualVibe Filebrowser in a new window">'
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin-right: 10px; flex-shrink: 0; color: #60a5fa;"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path></svg>'
    '<span style="font-size: 13px; font-weight: 500; letter-spacing: 0.3px; flex-grow: 1;">FileBrowser</span>'
    '<svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="opacity: 0.6; flex-shrink: 0;"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg>'
    '</a>'
)

title_script = (
    '<title>VisualVibe Agent</title>'
    '<link rel="icon" type="image/x-icon" href="./assets/favicon.ico">'
    '<link rel="icon" type="image/png" sizes="32x32" href="./assets/favicon_32x32.png">'
    '<link rel="icon" type="image/png" sizes="16x16" href="./assets/favicon_16x16.png">'
    '<link rel="apple-touch-icon" sizes="180x180" href="./assets/favicon_180x180.png">'
    '<script>document.title="VisualVibe Agent";'
    'try{Object.defineProperty(document,"title",{get:function(){return"VisualVibe Agent"},set:function(){},configurable:true});}catch(e){}'
    '</script>'
)

for filename in ["index.html", "vnc.html"]:
    filepath = os.path.join(WWW_DIR, filename)
    if not os.path.isfile(filepath):
        continue

    with open(filepath, "r", encoding="utf-8") as f:
        html = f.read()

    # 3a. Title and favicons
    if "<title>KasmVNC</title>" in html:
        html = html.replace("<title>KasmVNC</title>", title_script)
    elif "<title>VisualVibe Agent</title>" in html and "visualvibe-splash-style" not in html:
        pass

    # 3b. Sidebar logo, Switch Window button, Open Browser button, and FileBrowser link
    if 'id="noVNC_open_browser_button"' not in html:
        if 'id="noVNC_switch_window_button"' in html:
            html = re.sub(
                r'(<div\s+[^>]*id="noVNC_switch_window_button"[^>]*>.*?</div>\s*)',
                f'\\1{open_browser_html}\n',
                html,
                flags=re.DOTALL
            )
        elif 'id="noVNC_filebrowser_link"' in html:
            html = re.sub(
                r'(<a\s+[^>]*id="noVNC_filebrowser_link")',
                f'{switch_window_html}\n{open_browser_html}\n\\1',
                html
            )
        elif '<h1 class="noVNC_logo">' in html:
            html = re.sub(
                r'<h1 class="noVNC_logo">.*?</h1>',
                replacement_logo_html,
                html,
                count=1,
                flags=re.DOTALL
            )

    # 3b-2. Browser actions script
    if 'id="noVNC_browser_actions_script"' in html:
        html = re.sub(r'<script\s+id="noVNC_browser_actions_script">.*?</script>\n?', browser_actions_script, html, flags=re.DOTALL)
    elif 'id="noVNC_switch_window_script"' in html:
        html = re.sub(r'<script\s+id="noVNC_switch_window_script">.*?</script>\n?', browser_actions_script, html, flags=re.DOTALL)
    elif '</body>' in html:
        html = html.replace('</body>', f'{browser_actions_script}\n</body>')

    # 3c. Splash styles injection in <head>
    if "visualvibe-splash-style" not in html and "</head>" in html:
        html = html.replace("</head>", f"{splash_css}\n</head>")

    # 3d. Replace transition / connecting splash container in <body>
    target_transition = '<div id="noVNC_transition"><div id="noVNC_transition_text"></div><div><input type="button" id="noVNC_cancel_reconnect_button" value="Cancel" class="noVNC_submit"></div><div class="noVNC_spinner"></div></div>'
    if target_transition in html:
        html = html.replace(target_transition, splash_html)
    elif "noVNC_vv_logo_container" not in html and '<div id="noVNC_transition">' in html:
        transition_pattern = r'<div id="noVNC_transition">.*?<div id="noVNC_container">'
        m = re.search(transition_pattern, html, flags=re.DOTALL)
    # 3e. Cache-busting on stylesheet and script links to prevent stale browser caches
    html = re.sub(r'href="(\./assets/ui-[^"]+\.css)(?:\?[^"]*)?"', r'href="\1?v=vvagent_v7"', html)
    html = re.sub(r'src="(\./assets/ui-[^"]+\.js)(?:\?[^"]*)?"', r'src="\1?v=vvagent_v7"', html)

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[Brand] Successfully patched {filename} ({len(html)} bytes)")

# 4. Patch assets/ui-*.css (remove legacy KasmVNC logo background)
# FIX B-01: More robust regex — handles whitespace, property order, and minified/pretty CSS
for css_file in glob.glob(os.path.join(assets_dir, "ui-*.css")):
    with open(css_file, "r", encoding="utf-8") as f:
        css = f.read()

    # Safely replace the KasmVNC SVG background on #noVNC_transition if present.
    # The SVG data URI is enclosed in double quotes: url("data:image/svg+xml,...")
    # Using non-greedy matching .*? up to ") no-repeat fixed center; avoids breaking
    # on internal parentheses/semicolons inside the SVG XML payload.
    css_patched = re.sub(
        r'background\s*:\s*#fff\s+url\("data:image/svg\+xml.*?"\)\s*no-repeat fixed center;',
        'background:#0f172a;',
        css
    )

    # Append override rules at end of file to guarantee correct behavior regardless of minification:
    # 1. Override splash screen background to VisualVibe dark theme
    # 2. Ensure #noVNC_displays is strictly hidden unless it has the .noVNC_open class
    override_rules = (
        '\n/* VisualVibe Agent: UI layout and theme overrides */\n'
        '#noVNC_transition{background:#0f172a !important;background-image:none !important;}\n'
        '#noVNC_displays:not(.noVNC_open){display:none !important;visibility:hidden !important;}\n'
        '#noVNC_displays.noVNC_open{display:flex !important;visibility:visible !important;z-index:1000 !important;}\n'
        '#noVNC_control_bar .noVNC_logo{display:flex !important;align-items:center !important;justify-content:center !important;padding:6px 8px !important;margin:4px 0 6px 0 !important;}\n'
        '#noVNC_control_bar .noVNC_logo img{width:auto !important;max-width:98% !important;height:56px !important;object-fit:contain !important;}\n'
    )
    if '/* VisualVibe Agent: UI layout and theme overrides */' not in css_patched:
        css_patched += override_rules

    if css_patched != css:
        with open(css_file, "w", encoding="utf-8") as f:
            f.write(css_patched)
        print(f"[Brand] Successfully patched KasmVNC CSS background in {os.path.basename(css_file)}")

# 5. Patch assets/ui-*.js (title strings & expose window.UI)
# FIX B-02: Use flexible regex to match minified variable names instead of hardcoded 'Sx'
for js_file in glob.glob(os.path.join(assets_dir, "ui-*.js")):
    with open(js_file, "r", encoding="utf-8") as f:
        js = f.read()

    modified = False

    # Match any minified variable name holding the "KasmVNC" string constant
    # e.g.: const Sx="KasmVNC", let Tx="KasmVNC", var Ux="KasmVNC"
    title_var_match = re.search(r'(?:const|let|var)\s+(\w+)\s*=\s*"KasmVNC"', js)
    if title_var_match:
        var_name = title_var_match.group(1)
        js = re.sub(
            r'\b(const|let|var)\s+' + re.escape(var_name) + r'\s*=\s*"KasmVNC"',
            r'\1 ' + var_name + r'="VisualVibe Agent"',
            js,
            count=1
        )
        modified = True

    # Fallback: direct literal replacement if still present
    if '"KasmVNC"' in js:
        js = js.replace('"KasmVNC"', '"VisualVibe Agent"')
        modified = True

    # Expose window.UI for kasmSwitchWindow and kasmOpenBrowser to work
    if "window.UI=" not in js:
        # Match .prime() call on a single-letter object variable
        if re.search(r'\w\.prime\(\)', js):
            js = re.sub(r'(\w)\.prime\(\)', r'(window.UI=\1,\1.prime())', js, count=1)
            js = re.sub(r'\.then\((\w)\.prime\)', r'.then(()=>(window.UI=\1,\1.prime()))', js, count=1)
            modified = True

    # FIX IDLE-01: Enable automatic reconnection by default with 2s delay
    # Ensures tunnel disconnects (e.g. proxy idle timeout) seamlessly reconnect without error dialogs or manual F5
    if 'o.initSetting("reconnect",!1)' in js:
        js = js.replace('o.initSetting("reconnect",!1)', 'o.initSetting("reconnect",!0)')
        js = js.replace('o.initSetting("reconnect_delay",5e3)', 'o.initSetting("reconnect_delay",2e3)')
        modified = True

    # FIX IDLE-02: Disable client-side 20-minute idle disconnect
    # Prevents KasmVNC from unilaterally terminating the session after inactivity
    if 'c>l?(et("Idle Disconnect reached' in js:
        js = js.replace('c>l?(et("Idle Disconnect reached', '!1&&c>l?(et("Idle Disconnect reached')
        js = js.replace('o.initSetting("idle_disconnect",20)', 'o.initSetting("idle_disconnect",0)')
        modified = True

    # FIX RECONNECT-UNCLEAN: Automatically reconnect on unclean disconnects (e.g. reverse proxy idle timeout, network drop)
    # Stock KasmVNC only reconnects if !n.detail.clean is false. Intermediate proxy drops (e.g. after 3 minutes idle)
    # have !n.detail.clean == true, which gets trapped in the error branch and halts instead of auto-reconnecting.
    target_disconnect = 'if(o.connected=!1,o.rfb=void 0,o.monitors=[],o.sortedMonitors=[],!n.detail.clean)o.updateVisualState("disconnected"),e?o.showStatus(rr("Something went wrong, connection is closed"),"error"):o.showStatus(rr("Failed to connect to server"),"error");else if(o.getSetting("reconnect",!1)===!0&&!o.inhibitReconnect){o.updateVisualState("reconnecting");const t=parseInt(o.getSetting("reconnect_delay"));o.reconnectCallback=setTimeout(o.reconnect,t);return}'
    reconnect_patch = 'if(o.connected=!1,o.rfb=void 0,o.monitors=[],o.sortedMonitors=[],o.getSetting("reconnect",!0)===!0&&!o.inhibitReconnect){o.updateVisualState("reconnecting");const t=parseInt(o.getSetting("reconnect_delay"))||2e3;o.reconnectCallback=setTimeout(o.reconnect,t);return}else if(!n.detail.clean)o.updateVisualState("disconnected"),e?o.showStatus(rr("Something went wrong, connection is closed"),"error"):o.showStatus(rr("Failed to connect to server"),"error");'
    if target_disconnect in js:
        js = js.replace(target_disconnect, reconnect_patch)
        modified = True

    # FIX KEEPALIVE-STANDALONE: Send periodic RFB keepalive (1 byte) even when running in standalone mode (not iframe)
    # Stock KasmVNC only starts _sessionTimeoutInterval inside Gt() (iframe), leading to reverse proxy idle timeouts after 3 minutes
    target_keepalive = '):document.getElementById("noVNC_status").style.visibility="visible"'
    keepalive_patch = '):(document.getElementById("noVNC_status").style.visibility="visible",o._sessionTimeoutInterval=setInterval(function(){o.rfb&&o.connected&&o.rfb.sendKeepAlive()},5e3))'
    if target_keepalive in js:
        js = js.replace(target_keepalive, keepalive_patch)
        modified = True

    # FIX QUALITY-HIGH: Set default video quality preset to High (3) instead of Medium (2)
    # High (3) enables 60fps, dynamic quality 7-9, WebP/JPEG quality 8, lossless threshold 8
    if 'o.initSetting("video_quality",2)' in js:
        js = js.replace('o.initSetting("video_quality",2)', 'o.initSetting("video_quality",3)')
        js = js.replace('Gt()&&o.initSetting("video_quality",hr("video_quality",2))', 'Gt()&&o.initSetting("video_quality",hr("video_quality",3))')
        js = js.replace('o.updateSetting("video_quality",2)', 'o.updateSetting("video_quality",3)')
        modified = True

    if modified:
        with open(js_file, "w", encoding="utf-8") as f:
            f.write(js)
        print(f"[Brand] Successfully patched {os.path.basename(js_file)}")

# 6. Patch /usr/bin/vncserver to use http:// and show both VisualVibe Agent & FileBrowser Quantum
vncserver_path = "/usr/bin/vncserver"
if os.path.isfile(vncserver_path):
    try:
        with open(vncserver_path, "r", encoding="utf-8") as f:
            vnc_script = f.read()

        vnc_modified = False

        # Fix uninitialized $desktopName warning on line 2837
        if "$desktopName //=" not in vnc_script:
            vnc_script = vnc_script.replace(
                "$logger->warn(\"\\nNew '$desktopName' desktop is $host:$displayNumber\");",
                "$desktopName //= 'VisualVibe Agent';\n  $logger->warn(\"\\nNew '$desktopName' desktop is $host:$displayNumber\");"
            )
            vnc_modified = True

        # Fix URL scheme from https to http
        if 'my @urls = map { "https://$_:$browserPort" } @browserHosts;' in vnc_script:
            vnc_script = vnc_script.replace(
                'my @urls = map { "https://$_:$browserPort" } @browserHosts;',
                'my @urls = map { "http://$_:$browserPort" } @browserHosts;'
            )
            vnc_modified = True

        # Replace single VNC URL with VisualVibe Agent and FileBrowser Quantum URLs
        old_print_url = '$logger->warn("\\nPaste this url in your browser:\\n$browserUrls");'
        new_print_url = (
            'my @hosts = DeduceBrowserHosts();\n'
            '  my $host_ip = $hosts[0] || "127.0.0.1";\n'
            '  $logger->warn("\\nVisualVibe Agent:     http://$host_ip:8080\\n'
            'FileBrowser Quantum:  http://$host_ip:8081/filebrowser\\n");'
        )
        if old_print_url in vnc_script:
            vnc_script = vnc_script.replace(old_print_url, new_print_url)
            vnc_modified = True

        if vnc_modified:
            with open(vncserver_path, "w", encoding="utf-8") as f:
                f.write(vnc_script)
            print("[Brand] Successfully patched /usr/bin/vncserver (HTTP URLs & service branding)")
    except Exception as e:
        print(f"[Brand] Warning: Could not patch {vncserver_path}: {e}")

# 7. Marker file
with open(os.path.join(assets_dir, ".visualvibe_branded"), "w") as f:
    f.write("branded\n")

print("[Brand] VisualVibe Agent branding & vector splash screen applied cleanly.")

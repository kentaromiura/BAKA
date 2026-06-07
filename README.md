BAKA

Compiling under linux:
- you'll need to manually compile webview/webview project and copying the files:
*.so both in webview_odin and APP folder (only numbered version is required),
build config for linux in webview_odin is :
SHARED :: #config(SHARED, true)
LOCAL :: #config(LOCAL, true)

gtk and webkitgtk need to be installed
sudo pacman -Syu webkitgtk-6.0


For mac, you can use the dynamic dll available at free pascal webview, and change the config to:

SHARED :: #config(SHARED, true)
LOCAL :: #config(LOCAL, true)

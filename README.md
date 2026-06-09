BAKA
==

A little code-review AI assistant.

Baka is a code-review, inspired by https://github.com/nkzw-tech/codiff but using pi.dev for review, allowing infinite customization for both local models and any API/subscription services, not limited to openAI.

It's combining different stuff I was doing so no code from codiff has been used directly (*) 







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
also copy libwebview.dylib from the odin folder inside odin_webview to successfully compile, eg from odin_webview: cp ../libwebview.dylib .

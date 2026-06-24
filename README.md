BAKA
==

A little code-review AI assistant.

Baka is a code-review, inspired by https://github.com/nkzw-tech/codiff but using pi.dev for review, allowing infinite customization for both local models and any API/subscription services, not limited to openAI.

It's combining different stuff I was doing so no code from codiff has been used directly (*) 



Screenshots:
![Main screen v0.01](SCREEN/main.png)

![light mode v0](SCREEN/light.png)
![dark mode v0](SCREEN/dark.png)





Build the UI bundle, libwebview, and BAKA from the repository root:

```sh
make
```

The Makefile installs the UI dependencies from `yarn.lock` when needed, then
builds the ReScript/esbuild bundle before compiling the application. The
executable and shared library are kept under `build/`. The executable has an
rpath pointing to `build/webview/core`, so no webview library needs to be copied
into `APP/` or `APP/webview-odin/`.

Run BAKA with:

```sh
make run
make run ARGS='--verbose /path/to/repository'
```

On Linux, install GTK and WebKitGTK development packages before building.

## Third-party acknowledgements

- [`@pierre/diffs`](https://github.com/pierrecomputer/pierre/tree/main/packages/diffs)
  and [`@pierre/trees`](https://github.com/pierrecomputer/pierre/tree/main/packages/trees)
  provide the diff and file-tree interfaces. Both are licensed under the
  [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
  `@pierre/trees` also includes ideas and code derived from
  [`headless-tree`](https://github.com/lukasbach/headless-tree), as documented
  in its bundled notice.
- [`Ioskeley Mono`](https://github.com/ahatem/IoskeleyMono) by Ahmed Hatem is
  embedded as BAKA's interface font. Ioskeley Mono is a custom configuration
  of [`Iosevka`](https://github.com/be5invis/Iosevka), created by Belleve Invis
  and the Iosevka contributors. Both fonts are licensed under the SIL Open Font
  License 1.1. The redistributed font license is included at
  [`UI/bakaui/assets/fonts/IoskeleyMono/LICENSE`](UI/bakaui/assets/fonts/IoskeleyMono/LICENSE).

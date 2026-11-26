# Drop to Del

Drop to Del is a drag-and-drop cleanup utility for macOS. Drop a file, project folder, or app onto its floating desktop widget, review what it finds, and move the items you select to the macOS Trash.

Drop to Del 是一款 macOS 桌面清理工具。将文件、项目文件夹或应用拖到悬浮小机器上，查看并勾选清理项，再移到系统废纸篓。

## Download and install

Download the ZIP for your Mac from this repository’s **Releases** tab, unzip it, and move **Drop to Del.app** to **Applications**. Drop to Del requires macOS 14 or later. Choose `arm64` for Apple silicon or `x86_64` for Intel.

The release is ad hoc signed and has no Apple notarization. If macOS blocks the first launch, open **System Settings → Privacy & Security** after attempting to open the app and check for **Open Anyway**. The current interface is in Simplified Chinese.

## What it does

- Finds project clutter such as Finder metadata, preview thumbnails, and generated reports.
- Finds app copies, related files, and possible installers for review.
- Lets you open each candidate in Finder before selecting what to move to the Trash.

## Build from source

On macOS 14 or later, install Xcode Command Line Tools and run:

```sh
bash Scripts/build.sh
```

The app and ZIP are written to `build/<architecture>/`. Set `ARCH=arm64` or `ARCH=x86_64` to select a target.

## License

[MIT](LICENSE)

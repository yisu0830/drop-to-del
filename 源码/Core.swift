import Foundation
struct Item: Identifiable {
    let url: URL, title: String, reason: String, root: URL
    let bytes: Int64, stamp: Date, inode: UInt64
    var checked: Bool
    var bundledComponents: [String] = []
    var id: String { url.path }
}
enum Scan {
    static let fm = FileManager.default
    static let reports = ["最新检查.json","motion-qa.json","最新导出.log","结尾检查.png"]
    static func run(_ input: URL) -> ([Item], Int) {
        let root = input.standardizedFileURL.resolvingSymlinksInPath()
        if isApplication(root) { return scanApplication(root) }
        var rows = [Item](), skipped = 0
        func visit(_ url: URL) {
            do {
                let a = try fm.attributesOfItem(atPath: url.path)
                let type = a[.type] as? FileAttributeType
                let dir = type == .typeDirectory, name = url.lastPathComponent, parent = url.deletingLastPathComponent()
                guard dir || type == .typeRegular else { return }
                var rule: (String,String,Bool)?
                if dir {
                    if [".git",".svn",".hg"].contains(name) || ["app","bundle","framework","photoslibrary","xcodeproj"].contains(url.pathExtension.lowercased()) { return }
                    if name == "node_modules" {
                        guard fm.fileExists(atPath: parent.appendingPathComponent("package.json").path) else { return }
                        rule = ("项目依赖","再次预览或导出前需要重新安装；请确认项目已停用。",false)
                    }
                } else if name == ".DS_Store" {
                    rule = ("Finder 显示设置","清理后 Finder 可以重新生成。",true)
                } else if parent.lastPathComponent == ".thumbnails", name.hasPrefix("v5_"), name.contains("_index.html_"), url.pathExtension == "jpg", fm.fileExists(atPath: parent.deletingLastPathComponent().appendingPathComponent("hyperframes.json").path) {
                    rule = ("预览缩略图","HyperFrames 生成的时间点预览图。",true)
                } else if parent.lastPathComponent == "_work", reports.contains(name) {
                    let note = parent.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("交付说明.txt")
                    let documented = (try? String(contentsOf: note, encoding: .utf8))?.contains("过程检查：hyperframes-video/_work/") == true && parent.deletingLastPathComponent().lastPathComponent == "hyperframes-video"
                    rule = ("过程检查","检查截图、报告或导出日志；清理后无法回看这份记录。",documented)
                } else if ["png","jpg","jpeg","webp"].contains(url.pathExtension.lowercased()), ["demo","screenshot","检查","自测","截图"].contains(where: { name.lowercased().contains($0) }) {
                    rule = ("待确认图片","仅按名称发现，可能是正式素材。可在 Finder 查看，取消勾选要保留的图片。",true)
                }
                if let (title, reason, auto) = rule {
                    var size = (a[.size] as? NSNumber)?.int64Value ?? 0
                    if dir {
                        size = 0
                        let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey,.isRegularFileKey], options: [], errorHandler: { _,_ in skipped += 1; return true })
                        while let f = e?.nextObject() as? URL {
                            let v = try f.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
                            if v.isRegularFile == true { size += Int64(v.fileSize ?? 0) }
                        }
                    }
                    let trackedRisk = auto && title == "过程检查" && hasRepository(parent)
                    rows.append(Item(url:url,title:title,reason:reason + (trackedRisk ? " 位于 Git 项目中，请确认。" : ""),root:root,bytes:size,stamp:a[.modificationDate] as! Date,inode:(a[.systemFileNumber] as! NSNumber).uint64Value,checked:auto && !trackedRisk))
                } else if dir {
                    for child in try fm.contentsOfDirectory(at:url, includingPropertiesForKeys:nil) { visit(child) }
                }
            } catch { skipped += 1 }
        }
        visit(root)
        return (rows.sorted { ($0.checked ? 0 : 1,$0.title,$0.url.path) < ($1.checked ? 0 : 1,$1.title,$1.url.path) }, skipped)
    }
    static func isApplication(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private static func scanApplication(_ app: URL) -> ([Item], Int) {
        let bundle = Bundle(url: app)
        let bundleID = bundle?.bundleIdentifier
        let appNames = [app.deletingPathExtension().lastPathComponent,
                        bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
                        bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                        bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String]
            .compactMap { $0 }.map(installerKey).filter { $0.count >= 2 }
        var components = [String]()
        var componentPaths = [String]()
        var componentIDs = Set<String>()
        let componentEntries = fm.enumerator(at: app.appendingPathComponent("Contents"),
                                             includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                             options: [.skipsHiddenFiles])
        while let url = componentEntries?.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            guard ["app", "appex", "xpc"].contains(ext),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            if !componentPaths.contains(where: { url.path.hasPrefix($0 + "/") }) {
                componentPaths.append(url.path)
                components.append(url.deletingPathExtension().lastPathComponent)
            }
            if let id = Bundle(url: url)?.bundleIdentifier { componentIDs.insert(id) }
        }
        let applicationIDs = componentIDs.union([bundleID].compactMap { $0 })
        let home = fm.homeDirectoryForCurrentUser
        let parent = app.deletingLastPathComponent()
        let folders = [parent, home, URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Users/Shared")]
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        let homeLibrary = home.appendingPathComponent("Library").path
        let systemPrefixes = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private"]
        var rows = [Item]()
        var skipped = 0
        var seen = Set<String>()
        var scannedFolders = Set<String>()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey, .fileSizeKey]

        func add(_ url: URL, title: String, reason: String, isDirectory: Bool, bundledComponents: [String] = []) {
            guard seen.insert(url.path).inserted else { return }
            do {
                let info = try fm.attributesOfItem(atPath: url.path)
                guard let modified = info[.modificationDate] as? Date,
                      let inode = info[.systemFileNumber] as? NSNumber else { return }
                var size = (info[.size] as? NSNumber)?.int64Value ?? 0
                if isDirectory {
                    size = 0
                    let entries = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                errorHandler: { _, _ in skipped += 1; return true })
                    while let entry = entries?.nextObject() as? URL {
                        if let value = try? entry.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                           value.isRegularFile == true { size += Int64(value.fileSize ?? 0) }
                    }
                }
                rows.append(Item(url: url, title: title, reason: reason, root: url,
                                 bytes: size, stamp: modified, inode: inode.uint64Value, checked: true,
                                 bundledComponents: bundledComponents))
            } catch { skipped += 1 }
        }

        if (try? app.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true {
            if !systemPrefixes.contains(where: { app.path == $0 || app.path.hasPrefix($0 + "/") }) {
                add(app, title: "应用替身", reason: "将 Finder 替身移到废纸篓。", isDirectory: false)
            }
            return (rows, skipped)
        }

        if !systemPrefixes.contains(where: { app.path == $0 || app.path.hasPrefix($0 + "/") }),
           (try? app.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            add(app, title: "拖入的应用", reason: "勾选后可将这个应用移到废纸篓。", isDirectory: true,
                bundledComponents: components.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        }

        for folder in folders where scannedFolders.insert(folder.path).inserted {
            guard !systemPrefixes.contains(where: { folder.path == $0 || folder.path.hasPrefix($0 + "/") }),
                  folder.path != "/", folder.path != "/Volumes",
                  fm.fileExists(atPath: folder.path) else { continue }
            let entries = fm.enumerator(at: folder, includingPropertiesForKeys: Array(keys),
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                        errorHandler: { _, _ in skipped += 1; return true })
            while let url = entries?.nextObject() as? URL {
                if url.path == homeLibrary || url.path == app.path {
                    entries?.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: keys) else { skipped += 1; continue }
                guard values.isSymbolicLink != true else { continue }
                let ext = url.pathExtension.lowercased()
                if ext == "app", values.isDirectory == true {
                    entries?.skipDescendants()
                    if let id = Bundle(url: url)?.bundleIdentifier {
                        if id == bundleID {
                            add(url, title: "其他应用副本", reason: "与拖入应用的 Bundle ID 相同。", isDirectory: true)
                        } else if componentIDs.contains(id) {
                            add(url, title: "关联应用", reason: "与内置组件的 Bundle ID 相同。", isDirectory: true)
                        }
                    }
                } else if ext == "app", values.isAliasFile == true {
                    guard let target = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) else { continue }
                    let path = target.standardizedFileURL.resolvingSymlinksInPath().path
                    if path == app.path || componentPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                        add(url, title: "应用替身", reason: "Finder 替身指向拖入的应用或其内置组件。", isDirectory: false)
                    }
                } else if ["dmg", "pkg", "mpkg", "zip", "xip", "tar", "gz", "tgz", "7z"].contains(ext),
                          values.isRegularFile == true || (values.isDirectory == true && ["pkg", "mpkg"].contains(ext)) {
                    if values.isDirectory == true { entries?.skipDescendants() }
                    let name = installerKey(url.deletingPathExtension().lastPathComponent)
                    if appNames.contains(where: { matchesInstaller(name, appName: $0) }) {
                        add(url, title: "可能的安装包", reason: "按文件名匹配，请核对路径。",
                            isDirectory: values.isDirectory == true)
                    }
                }
            }
        }
        let libraryLocations = [
            ("Caches", "应用缓存"), ("Logs", "应用日志"),
            ("Preferences", "偏好设置"), ("Application Support", "应用支持文件"),
            ("Containers", "应用容器"), ("HTTPStorages", "网络存储"),
            ("WebKit", "网页数据"), ("Saved Application State", "窗口状态")
        ]
        for (location, title) in libraryLocations {
            let folder = URL(fileURLWithPath: homeLibrary).appendingPathComponent(location)
            guard folder.resolvingSymlinksInPath().path == folder.path else { continue }
            for id in applicationIDs {
                let name: String
                switch location {
                case "Preferences": name = id + ".plist"
                case "Saved Application State": name = id + ".savedState"
                default: name = id
                }
                guard !name.contains("/"), name != ".", name != ".." else { continue }
                let url = folder.appendingPathComponent(name)
                guard url.path != app.path, !url.path.hasPrefix(app.path + "/"),
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isSymbolicLink != true,
                      values.isDirectory == true || values.isRegularFile == true else { continue }
                add(url, title: title, reason: "按主应用或内置组件的 Bundle ID 匹配。",
                    isDirectory: values.isDirectory == true)
            }
        }
        return (rows.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }, skipped)
    }

    private static func installerKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
    }

    private static func matchesInstaller(_ name: String, appName: String) -> Bool {
        guard name.hasPrefix(appName) else { return false }
        let suffix = String(name.dropFirst(appName.count))
        if suffix.isEmpty { return true }
        return suffix.range(of: #"^(?:v?[0-9]+|macos|mac|osx|arm64|aarch64|x64|x8664|intel|universal|installer|install|setup|release|stable|beta|安装包|安装|副本|copy|targz|tar)+$"#,
                            options: .regularExpression) != nil
    }

    static func hasRepository(_ start: URL) -> Bool {
        var p = start
        while p.path != "/" && !p.path.isEmpty {
            if fm.fileExists(atPath:p.appendingPathComponent(".git").path) { return true }
            p = p.deletingLastPathComponent()
        }
        return false
    }
    static func trash(_ item: Item) throws {
        let p = item.url.standardizedFileURL
        guard p.resolvingSymlinksInPath().path == p.path, p == item.root || p.path.hasPrefix(item.root.path + "/") else { throw CocoaError(.fileWriteInvalidFileName) }
        let a = try fm.attributesOfItem(atPath:p.path)
        guard a[.modificationDate] as? Date == item.stamp, (a[.systemFileNumber] as? NSNumber)?.uint64Value == item.inode else { throw NSError(domain:"Scan",code:1,userInfo:[NSLocalizedDescriptionKey:"文件已改变，请重新扫描"]) }
        try fm.trashItem(at:p,resultingItemURL:nil)
    }
}

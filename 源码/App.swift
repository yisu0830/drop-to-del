import SwiftUI
import AppKit
private let ink = Color(red: 0.13, green: 0.15, blue: 0.20)
private let paper = Color(.sRGB, red: 0.99, green: 0.96, blue: 0.90)
private let rule = Color(red: 0.78, green: 0.72, blue: 0.64)
private let muted = Color(red: 0.33, green: 0.31, blue: 0.29)
private let mint = Color(red: 0.08, green: 0.36, blue: 0.31)
private let gold = Color(red: 0.98, green: 0.73, blue: 0.22)
private func fileSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private enum PanelSound: String {
    case checklist = "PageTurn"
    case success = "Glass"
    case failure = "Basso"

    func play(replacing current: inout NSSound?) {
        current?.stop()
        if let url = Bundle.main.url(forResource: rawValue, withExtension: "wav") {
            current = NSSound(contentsOf: url, byReference: false)
        } else {
            current = NSSound(named: NSSound.Name(rawValue))
        }
        current?.volume = 0.32
        current?.play()
    }
}

// The main queue joins the filesystem result with the end of a complete shred cycle.
private final class ShredPlayback {
    private let sound = Bundle.main.url(forResource: "Shred", withExtension: "wav")
        .flatMap { NSSound(contentsOf: $0, byReference: false) }
    private var completion: (() -> Void)?
    private let minimumCycle: TimeInterval

    private let animateCycle: () -> Void

    init(reducedMotion: Bool, animateCycle: @escaping () -> Void) {
        self.animateCycle = animateCycle
        minimumCycle = reducedMotion ? 0.25 : DesktopPet.paperFallDuration
        sound?.volume = 0.85
    }

    func finishAfterCycle(_ action: @escaping () -> Void) {
        completion = action
    }

    func playCycle() {
        animateCycle()
        sound?.currentTime = 0
        let playing = sound?.play() == true
        let duration = max(minimumCycle, playing ? sound?.duration ?? 0 : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { self.endCycle() }
    }

    private func endCycle() {
        if sound?.isPlaying == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { self.endCycle() }
        } else if let action = completion {
            completion = nil
            action()
        } else {
            playCycle()
        }
    }
}

struct Panel:View {
    @State private var currentSound: NSSound?
    let initial:URL
    let petState: (Bool, Bool) -> Void
    let hide: () -> Void
    let captureSheet: () -> Void
    let beginFeed: (@escaping () -> Void) -> Void
    let animateShredCycle: () -> Void
    let reportSuccess: (String) -> Void
    let endFeed: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feeding = false
    @State private var sliding = false
    @State private var unfolded = false
    @State var rows=[Item]()
    @State var expanded=Set<String>()
    @State private var cleanupFailures: [String: String] = [:]
    @State var root:URL?
    @State var busy=false
    @State private var completed = false
    @State var status="正在扫描…"
    var scanningApplication: Bool { Scan.isApplication(initial) }
    var chosen:[Item]{rows.filter{$0.checked}}
    func scan(_ url:URL){
        guard !busy else { return }
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) { unfolded = false }
        busy = true
        petState(true, false)
        completed = false
        root = url
        rows = []
        cleanupFailures = [:]
        expanded = []
        status = "正在扫描…"
        let revealTime = DispatchTime.now() + (reduceMotion ? 0 : 0.24)
        DispatchQueue.global(qos:.userInitiated).async {
            let (found,missed)=Scan.run(url)
            DispatchQueue.main.asyncAfter(deadline: max(.now(), revealTime)) {
                PanelSound.checklist.play(replacing: &currentSound)
                rows = found
                if scanningApplication { expanded = Set(found.map(\.title)) }
                busy = false
                status = "\(found.count) 项" + (missed > 0 ? " · 部分未读取" : "")
                petState(false, false)
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.34)) { unfolded = true }
            }
        }
    }
    func pick(){let p=NSOpenPanel(); p.canChooseDirectories=true; p.canChooseFiles=true; if p.runModal() == .OK,let url=p.url{scan(url)}}
    func clean(){
        let batch=chosen
        guard !busy && !batch.isEmpty else { return }
        if !reduceMotion { captureSheet() }
        completed = false
        busy = true
        currentSound?.stop()
        let playback = ShredPlayback(reducedMotion: reduceMotion, animateCycle: animateShredCycle)
        petState(true, reduceMotion)
        if reduceMotion {
            playback.playCycle()
            withAnimation(.easeOut(duration: 0.2)) { feeding = true }
        } else {
            withAnimation(.easeInOut(duration: 0.32)) { feeding = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                beginFeed { playback.playCycle() }
                withAnimation(.linear(duration: 0.48).delay(0.22)) { sliding = true }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var done = Set<String>()
            var failures = [(item: Item, message: String)]()
            var hasPermissionFailure = false
            for item in batch {
                do {
                    try Scan.trash(item)
                    done.insert(item.id)
                } catch {
                    let failure = error as NSError
                    let permissionDenied = failure.domain == NSCocoaErrorDomain &&
                        [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(failure.code)
                    hasPermissionFailure = hasPermissionFailure || permissionDenied
                    let message = permissionDenied ? "权限不足" : error.localizedDescription
                    failures.append((item, message))
                }
            }
            DispatchQueue.main.async {
                playback.finishAfterCycle {
                    let cue: PanelSound = failures.isEmpty ? .success : .failure
                    cue.play(replacing: &currentSound)
                    completed = failures.isEmpty
                    endFeed()
                    rows.removeAll { done.contains($0.id) }
                    for id in done { cleanupFailures.removeValue(forKey: id) }
                    for failure in failures {
                        cleanupFailures[failure.item.id] = failure.message
                        expanded.insert(failure.item.title)
                    }
                    busy = false
                    let bytes = batch.filter { done.contains($0.id) }.reduce(Int64(0)) { $0 + $1.bytes }
                    let summary = "\(done.count) 项 · \(fileSize(bytes))"
                    status = summary + " 已移入废纸篓"
                    if failures.isEmpty { reportSuccess(summary) }
                    if !failures.isEmpty { status += " · \(failures.count) 项失败" }
                    petState(false, false)
                    withAnimation(failures.isEmpty ? nil : .easeOut(duration: 0.2)) {
                        feeding = false
                        sliding = false
                    }
                    if !failures.isEmpty {
                        let alert = NSAlert()
                        alert.messageText = done.isEmpty ? "所选项目未能移入废纸篓" : "部分项目未能移入废纸篓"
                        alert.informativeText = failures.prefix(6).map {
                            $0.item.url.lastPathComponent + " · " + $0.message
                        }.joined(separator: "\n")
                        if hasPermissionFailure {
                            alert.informativeText += "\n\n如果 macOS 提示授权，允许后可重试。也可以在 Finder 中定位并尝试手动移入废纸篓。"
                        }
                        alert.addButton(withTitle: "关闭")
                        alert.addButton(withTitle: "在 Finder 中查看")
                        if alert.runModal() == .alertSecondButtonReturn {
                            NSWorkspace.shared.activateFileViewerSelecting(failures.map(\.item.url))
                        }
                    }
                }
            }
        }
    }

    func toggle(_ ids:Set<String>,_ on:Bool){for i in rows.indices where ids.contains(rows[i].id){rows[i].checked=on}}
    func group(_ title: String) -> some View {
        let items = rows.filter { $0.title == title }
        let ids = Set(items.map(\.id))
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Toggle(title, isOn: Binding(get: { items.allSatisfy(\.checked) },
                                            set: { toggle(ids, $0) })).labelsHidden()
                Button {
                    if expanded.contains(title) { expanded.remove(title) }
                    else { expanded.insert(title) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: expanded.contains(title) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                        Text(title).fontWeight(.semibold).lineLimit(1)
                        Text(String(items.count)).foregroundStyle(muted)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .modifier(HoverName(name: title, enabled: !busy))
            if expanded.contains(title) {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        Toggle(item.url.lastPathComponent,
                               isOn: Binding(get: { item.checked }, set: { toggle([item.id], $0) }))
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            if !item.bundledComponents.isEmpty {
                                Text("随应用一起移走：" + item.bundledComponents.joined(separator: "、"))
                                    .foregroundStyle(muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(fileSize(item.bytes))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(muted)
                            if let failure = cleanupFailures[item.id] {
                                Text(failure)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                                    .help(failure)
                            }
                        }
                        Spacer(minLength: 0)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                            Image(systemName: "magnifyingglass")
                        }.buttonStyle(.plain).foregroundStyle(mint).help("在 Finder 中查看")
                    }
                    .modifier(HoverName(name: scanningApplication ? item.url.path : item.url.lastPathComponent, enabled: !busy))
                    .padding(.leading, 12)
                }
            }
        }
        .font(.caption)
        .toggleStyle(PixelCheckbox())
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 1) }
    }

    private func actionLabel(_ label: String, fill: Color, enabled: Bool) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(enabled ? ink : muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(enabled ? fill : rule.opacity(0.42))
            .overlay { Rectangle().strokeBorder(ink.opacity(enabled ? 0.48 : 0.16), lineWidth: 1) }
    }

    var body: some View {
        let shrinkPaper = feeding && !reduceMotion
        let slideIntoIntake = sliding && !reduceMotion
        let intakeWidth = DesktopPet.intakeWidth
        let canRescan = root != nil && !busy
        let canClean = canRescan && !chosen.isEmpty
        let retrying = canClean && chosen.allSatisfy { cleanupFailures[$0.id] != nil }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("清理清单").font(.system(size: 12, weight: .heavy, design: .monospaced))
                Spacer()
                Button(action: hide) {
                    Image(systemName: "xmark").font(.caption.weight(.semibold)).padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭清理清单")
                .help("关闭")
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(ink)
            .foregroundStyle(paper)
            Text(initial.lastPathComponent).font(.subheadline.weight(.semibold))
                .lineLimit(1).truncationMode(.middle).help(initial.path)
            if completed {
                Label("清理完成", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(mint)
            }
            Text(status).font(.caption).foregroundStyle(mint)
            Rectangle().fill(mint).frame(height: 2)

            if rows.isEmpty {
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(Set(rows.map(\.title))).sorted(), id: \.self) { group($0) }
                    }
                    .containerRelativeFrame(.horizontal)
                }.clipped().disabled(busy)
            }

            HStack(spacing: 3) {
                Text("已选 \(chosen.count) 项").lineLimit(1)
                Spacer(minLength: 2)
                if !chosen.isEmpty {
                    Text(fileSize(chosen.reduce(0) { $0 + $1.bytes }))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(muted)
                }
            }
            .font(.caption.monospacedDigit())
            HStack(spacing: 4) {
                Button { scan(initial) } label: {
                    actionLabel("重新扫描", fill: rule.opacity(0.62), enabled: canRescan)
                }.buttonStyle(.plain).disabled(!canRescan)
                Button(action: clean) {
                    actionLabel(retrying ? "重试所选项" : "一键清理", fill: gold, enabled: canClean)
                }.buttonStyle(.plain).disabled(!canClean)
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 9)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PaperSheet().fill(paper)
                .overlay { PaperSheet().stroke(rule, lineWidth: 1) }
        }
        .foregroundStyle(ink)
        .tint(mint)
        .preferredColorScheme(.light)
        .mask(alignment: .bottom) {
            Rectangle().scaleEffect(x: 1, y: unfolded ? 1 : 0, anchor: .bottom)
        }
        .visualEffect { sheet, geometry in
            let scale = min(1, (intakeWidth - 2) / max(1, geometry.size.width))
            let travel = geometry.size.height * scale + 1
            return sheet.scaleEffect(shrinkPaper ? scale : 1, anchor: .bottom)
                .offset(y: slideIntoIntake ? travel : 0)
        }
        .clipped()
        .opacity(feeding && reduceMotion ? 0 : 1)
        .allowsHitTesting(!feeding && unfolded)
        .onAppear { if root == nil { scan(initial) } }
    }
}

private struct HoverName: ViewModifier {
    let name: String
    let enabled: Bool
    @State private var toast: NSPanel?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering && enabled { show() }
                else { hide() }
            }
            .onChange(of: enabled) { _, available in
                if !available { hide() }
            }
            .onDisappear { hide() }
    }

    private func show() {
        guard toast == nil else { return }
        let label = NSHostingView(rootView:
            Text(name)
                .font(.caption)
                .foregroundStyle(Color.black)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)
                .padding(8)
                .background(paper)
                .overlay { Rectangle().strokeBorder(rule, lineWidth: 1) }
        )
        let size = label.fittingSize
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) else { return }
        let visible = screen.visibleFrame
        let x = max(visible.minX, min(cursor.x + 12, visible.maxX - size.width))
        let below = cursor.y - size.height - 12
        let y = below >= visible.minY ? below : min(cursor.y + 12, visible.maxY - size.height)
        let frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        label.sizingOptions = []
        panel.contentView = label
        panel.contentMinSize = .zero
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        toast = panel
    }

    private func hide() {
        toast?.orderOut(nil)
        toast = nil
    }
}

private struct PixelCheckbox: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack {
                Rectangle().fill(configuration.isOn ? mint : paper)
                Rectangle().strokeBorder(ink, lineWidth: 1)
                if configuration.isOn {
                    Path { path in
                        path.addRect(CGRect(x: 3, y: 6, width: 2, height: 2))
                        path.addRect(CGRect(x: 5, y: 7, width: 2, height: 2))
                        path.addRect(CGRect(x: 7, y: 5, width: 2, height: 2))
                        path.addRect(CGRect(x: 9, y: 3, width: 2, height: 2))
                    }.fill(paper)
                }
            }
            .frame(width: 13, height: 13)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox) }
    }
}

private struct PaperSheet: Shape {
    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: 0.5, dy: 0.5)
        let teeth = max(1, Int(rect.width / 7))
        let step = rect.width / CGFloat(teeth)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
        for tooth in (0..<teeth).reversed() {
            let x = rect.minX + CGFloat(tooth) * step
            path.addLine(to: CGPoint(x: x + step * 0.72, y: rect.maxY - 3))
            path.addLine(to: CGPoint(x: x + step * 0.72, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + step * 0.22, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + step * 0.22, y: rect.maxY - 3))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 3))
        path.closeSubpath()
        return path
    }
}

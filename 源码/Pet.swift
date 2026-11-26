import AppKit
import SwiftUI

final class DesktopPet:NSView {
    static let pixelSize = 3
    static let padding = 5
    static let intakeWidth = CGFloat(13 * pixelSize)
    static let intakeDepth = CGFloat(padding + 9 * pixelSize)
    static let checklistDepth = CGFloat(padding) + 6.5 * CGFloat(pixelSize) - 10
    static let size = NSSize(width: 29 * pixelSize + 2 * padding,
                             height: 25 * pixelSize + 2 * padding)
    static let paperFadeDepth: CGFloat = 10
    static let particleOverflow: CGFloat = 23
    static let paperFallDuration: TimeInterval = 1.30
    var dropped:((URL)->Void)?
    var clicked:(()->Void)?
    var checklistPaper: NSImage?
    var checklistVisible = false { didSet { if oldValue != checklistVisible { needsDisplay = true } } }
    var feedingChecklist = false { didSet { needsDisplay = true } }
    var busy = false { didSet { if oldValue != busy { restartAnimation() } } }
    var cutting = false { didSet { if oldValue != cutting { restartAnimation() } } }
    private var highlight = false { didSet { if oldValue != highlight { restartAnimation() } } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    private var timer: Timer?
    private var animationStart = ProcessInfo.processInfo.systemUptime
    private var mouseDownLocation: NSPoint?
    private var didDrag = false
    override var isFlipped:Bool { true }
    override init(frame:NSRect){
        super.init(frame:frame)
        registerForDraggedTypes([.fileURL])
        toolTip="拖动机身可移动，拖入项目或应用可扫描，右键退出"
        let m=NSMenu()
        m.addItem(withTitle:"选择项目…",action:#selector(pick),keyEquivalent:"").target=self
        m.addItem(.separator())
        m.addItem(withTitle:"退出 Little Del",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q").target=NSApp
        menu=m
    }
    required init?(coder:NSCoder){fatalError()}
    @objc func pick(){guard !busy else{return}; let p=NSOpenPanel();p.canChooseDirectories=true;p.canChooseFiles=true
        if p.runModal() == .OK,let u=p.url{dropped?(u)}}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}
    override func mouseDown(with event: NSEvent) {
        guard !feedingChecklist else { return }
        mouseDownLocation = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, let window else { return }
        let location = event.locationInWindow
        let dx = location.x - start.x
        let dy = location.y - start.y
        guard didDrag || hypot(dx, dy) >= 3 else { return }
        didDrag = true
        window.setFrameOrigin(NSPoint(x: window.frame.minX + dx, y: window.frame.minY + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownLocation = nil }
        guard let start = mouseDownLocation, !didDrag else { return }
        let location = event.locationInWindow
        if hypot(location.x - start.x, location.y - start.y) < 3 {
            clicked?()
        }
    }
    func urls(_ info:NSDraggingInfo)->[URL] {
        (info.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation{highlight = !busy && urls(sender).count==1;return highlight ? .copy:[]}
    override func draggingExited(_ sender:NSDraggingInfo?){highlight=false}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool{highlight=false;guard !busy,let u=urls(sender).first else{return false};dropped?(u);return true}
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restartAnimation()
    }

    private func restartAnimation() {
        timer?.invalidate()
        timer = nil
        animationStart = ProcessInfo.processInfo.systemUptime
        needsDisplay = true
        guard window != nil else { return }
        let frameRate = highlight || busy ? 30.0 : 8.0
        let animation = Timer(timeInterval: 1.0 / frameRate, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.needsDisplay = true
        }
        RunLoop.main.add(animation, forMode: .common)
        timer = animation
    }

    override func draw(_ dirtyRect:NSRect){
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let elapsed = ProcessInfo.processInfo.systemUptime - animationStart
        let frame = reducedMotion ? 0 : Int(elapsed * 8)
        let hoverOpensLid = hovering && !checklistVisible
        let lidIsOpen = hoverOpensLid || highlight || busy
        let scannerActive = highlight || (busy && !cutting && !feedingChecklist && checklistPaper == nil)
        let lifted = !reducedMotion && !lidIsOpen && !checklistVisible && frame % 24 >= 10 && frame % 24 < 15
        let lift: CGFloat = lifted ? -0.5 : 0

        func pixel(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: UInt32) {
            NSColor(srgbRed: CGFloat((color >> 16) & 255) / 255,
                    green: CGFloat((color >> 8) & 255) / 255,
                    blue: CGFloat(color & 255) / 255, alpha: 1).setFill()
            let unit = CGFloat(Self.pixelSize)
            let padding = CGFloat(Self.padding)
            NSBezierPath(rect: NSRect(x: padding + x * unit, y: padding + (y + lift) * unit,
                                      width: width * unit, height: height * unit)).fill()
        }

        let outline: UInt32 = 0x11121b
        let body: UInt32 = 0x252631
        let edge: UInt32 = 0x383e52
        let steel: UInt32 = hoverOpensLid || highlight ? 0x65799c : 0x4d5a76
        let gold: UInt32 = hoverOpensLid || highlight ? 0xffda67 : 0xf9b937
        let mint: UInt32 = hoverOpensLid || highlight ? 0x9cf6d7 : 0x61d8ba

        // Step the casing and bevels in half-cell increments.
        pixel(3, 9, 23, 12, outline)
        pixel(2.5, 10, 24, 10, outline)
        pixel(3.5, 20, 22, 1.5, outline)
        pixel(4.5, 21, 20, 1, outline)
        pixel(3.5, 10, 22, 10.5, body)
        pixel(4, 20.5, 21, 0.5, edge)
        pixel(4.5, 21, 20, 0.5, 0x464f66)
        pixel(3, 11, 0.5, 8, 0x78849d)
        pixel(25.5, 11, 0.5, 8, 0x606d88)
        pixel(3.5, 11.5, 0.5, 7.5, edge)
        pixel(25, 11.5, 0.5, 7.5, edge)

        pixel(5, 14, 17, 4.5, edge)
        pixel(5.5, 14.5, 16, 3.5, outline)
        pixel(6, 15, 15, 2.5, 0x10111a)
        pixel(6, 17.5, 15, 0.5, 0x52617b)
        pixel(6.5, 15, 14, 0.5, 0x090a0f)

        if lidIsOpen {
            pixel(4, 6.5, 21, 3.5, outline)
            pixel(4, 6.5, 2, 2.5, edge)
            pixel(23, 6.5, 2, 2.5, edge)
            pixel(4.5, 7, 0.5, 2, steel)
            pixel(24, 7, 0.5, 2, steel)
        }

        func lid(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: UInt32) {
            pixel(x, y - (lidIsOpen ? 2.5 : 0), width, height, color)
        }
        lid(5.5, 6.5, 18, 0.5, outline)
        lid(4.5, 7, 20, 0.5, outline)
        lid(4, 7.5, 21, 1, steel)
        lid(3.5, 8, 22, 1.5, steel)
        lid(3, 9, 23, 1, steel)
        lid(3.5, 9.5, 22, 0.5, 0x657592)
        lid(4.5, 8, 2, 0.5, 0x8193b3)
        lid(5, 7.5, 2, 0.5, 0x697d9e)
        lid(23, 8, 1.5, 0.5, 0x8193b3)
        lid(22, 7.5, 2, 0.5, 0x697d9e)
        lid(4, 8.5, 1, 0.5, 0x9baed1)
        lid(24, 8.5, 1, 0.5, 0x9baed1)
        pixel(4, 10, 21, 1.5, body)
        pixel(4.5, 11.5, 20, 0.5, edge)

        pixel(7.5, 8, 14, 2, scannerActive ? 0x296b55 : 0x343b4b)
        pixel(8, 8.5, 13, 0.5, 0x121820)
        pixel(8, 9, 13, 0.5, scannerActive ? 0x42dba3 : 0x596781)
        if scannerActive {
            let phase = elapsed.truncatingRemainder(dividingBy: 0.90) / 0.90
            let sweep = reducedMotion ? 0.5 : 1 - abs(phase * 2 - 1)
            let start = 8 + (sweep * 18).rounded() / 2
            pixel(start, 8.5, 4, 1.5, 0x68f7b3)
            pixel(start + 0.5, 9, 3, 0.5, 0xe0ffec)
        }

        pixel(22.5, 13, 2, 2.5, outline)
        pixel(23, 13.5, 1, 1.5, gold)
        pixel(23.5, 13.5, 0.5, 0.5, 0xffedaa)
        pixel(23, 16.5, 1.5, 3, outline)
        pixel(23.5, 17, 0.5, 2, busy ? mint : gold)

        if cutting && feedingChecklist && !reducedMotion, let checklistPaper {
            drawShreddedPaper(checklistPaper, elapsed: elapsed)
        }
    }

    private func drawShreddedPaper(_ sheet: NSImage, elapsed: TimeInterval) {
        let count = 9
        let crossCuts = 4
        let height: CGFloat = 27
        let pieceHeight = height / CGFloat(crossCuts)
        let width = Self.intakeWidth / CGFloat(count)
        let outlet = CGFloat(Self.padding + 16 * Self.pixelSize)
        let firstX = bounds.midX - Self.intakeWidth / 2
        let sourceWidth = sheet.size.width / CGFloat(count)
        let sourceHeight = sheet.size.height / CGFloat(crossCuts)
        let pieceRadius = hypot(width, pieceHeight) / 2
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: NSRect(x: 0, y: outlet, width: bounds.width,
                                  height: bounds.maxY - outlet)).addClip()
        for strip in 0..<count {
            let spacingDelay = Double((strip * 7) % count) * 0.011
            let spread = CGFloat(strip - count / 2) / CGFloat(count / 2)
            let x = firstX + CGFloat(strip) * width + width / 2

            for segment in 0..<crossCuts {
                let row = CGFloat(segment)
                let release = spacingDelay + Double((row + 0.5) * pieceHeight) / 64
                let age = elapsed - release
                let variant = Double((strip * 5 + segment * 3) % 8)
                let lifetime = 0.59 + variant * 0.03
                guard age > -Double(pieceRadius) / 64, age < lifetime else { continue }

                let progress = CGFloat(max(0, age / lifetime))
                let spin = CGFloat((strip * 3 + segment * 5) % 7 - 3) / 3
                let landing = Self.size.height + Self.paperFadeDepth + CGFloat(variant - 3.5) * 1.15
                let descent = progress * (1.45 - 0.45 * progress)
                let fall = age < 0 ? outlet + CGFloat(age * 64) : outlet + (landing - outlet) * descent
                let flutter = CGFloat(sin(age * 12 + Double(strip + segment))) * progress * 2.5
                let fadeStart = 0.24 + variant * 0.017
                let fade = CGFloat(min(1, max(0, (age / lifetime - fadeStart) / (1 - fadeStart))))
                let opacity = 1 - fade * fade * (3 - 2 * fade)

                NSGraphicsContext.saveGraphicsState()
                let motion = NSAffineTransform()
                motion.translateX(by: x + (spread * 8 + spin * 5) * progress + flutter, yBy: fall)
                motion.rotate(byRadians: (spread * -0.23 + spin * 0.55) * progress + flutter * 0.035)
                motion.concat()

                let piece = NSRect(x: -width / 2, y: -pieceHeight / 2,
                                   width: width - 0.55, height: pieceHeight - 1.1)
                context.setAlpha(opacity)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                let shadow = NSShadow()
                shadow.shadowColor = NSColor(white: 0, alpha: 0.32)
                shadow.shadowBlurRadius = 1.2
                shadow.shadowOffset = NSSize(width: 0.5, height: -0.5)
                shadow.set()
                NSColor(srgbRed: 0.99, green: 0.96, blue: 0.90, alpha: 1).setFill()
                NSBezierPath(rect: piece).fill()
                sheet.draw(in: piece, from: NSRect(x: CGFloat(strip) * sourceWidth, y: row * sourceHeight,
                                                 width: sourceWidth, height: sourceHeight),
                           operation: .sourceOver, fraction: 1, respectFlipped: true,
                           hints: [.interpolation: NSImageInterpolation.high])
                context.endTransparencyLayer()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

private final class ChecklistWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Host: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let pet = DesktopPet(frame: NSRect(origin: .zero, size: DesktopPet.size))
    let resultSize = NSSize(width: 139, height: 254)
    var window: NSPanel!
    var results: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSPanel(contentRect: pet.bounds, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = pet
        window.delegate = self
        let screen = NSScreen.main?.visibleFrame ?? .zero
        window.setFrameOrigin(NSPoint(x: screen.maxX - pet.bounds.width - 39, y: screen.minY + 55))
        window.orderFrontRegardless()
        pet.dropped = { [weak self] url in self?.show(url) }
        pet.clicked = { [weak self] in
            guard let self, !pet.busy else { return }
            if results?.isVisible == true { hideResults() }
            else if results != nil { present() }
            else { pet.pick() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let window else { return true }
        window.orderFrontRegardless()
        if results?.isVisible == true { results?.orderFrontRegardless() }
        return false
    }

    func windowDidMove(_ notification: Notification) {
        positionResults()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        positionResults()
    }

    private func positionResults() {
        guard !pet.feedingChecklist, let results, let screen = window.screen ?? NSScreen.main else { return }
        let petFrame = window.frame
        let visible = screen.visibleFrame
        let gap: CGFloat = 8
        let size = results.frame.size
        let left = petFrame.minX - gap - size.width
        let right = petFrame.maxX + gap
        let alignedY = min(max(petFrame.midY - size.height / 2, visible.minY), visible.maxY - size.height)
        let alignedX = min(max(petFrame.midX - size.width / 2, visible.minX), visible.maxX - size.width)
        let above = petFrame.maxY - DesktopPet.checklistDepth
        let below = petFrame.minY - gap - size.height
        let origin: NSPoint
        if above + size.height <= visible.maxY {
            origin = NSPoint(x: alignedX, y: above)
        } else if left >= visible.minX {
            origin = NSPoint(x: left, y: alignedY)
        } else if right + size.width <= visible.maxX {
            origin = NSPoint(x: right, y: alignedY)
        } else if below >= visible.minY {
            origin = NSPoint(x: alignedX, y: below)
        } else {
            // Keep the two windows apart even in unusually small screen layouts.
            origin = NSPoint(x: petFrame.minX - visible.minX >= visible.maxX - petFrame.maxX ? left : right,
                             y: alignedY)
        }
        results.setFrameOrigin(origin)
    }

    private func captureSheet() {
        guard let view = results?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        pet.checklistPaper = image
    }

    private func beginFeed() {
        guard let results else { return }
        pet.feedingChecklist = true
        setParticleOverflow(DesktopPet.particleOverflow)
        let intake = NSPoint(x: window.frame.midX, y: window.frame.maxY - DesktopPet.intakeDepth)
        let origin = NSPoint(x: intake.x - results.frame.width / 2, y: intake.y)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.allowsImplicitAnimation = true
            results.animator().setFrame(NSRect(origin: origin, size: results.frame.size), display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard let self, pet.feedingChecklist else { return }
            pet.cutting = true
        }
    }

    private func setParticleOverflow(_ extraHeight: CGFloat) {
        var frame = window.frame
        let top = frame.maxY
        frame.size.height = DesktopPet.size.height + extraHeight
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true)
    }

    private func endFeed() {
        guard pet.feedingChecklist else { return }
        pet.cutting = false
        setParticleOverflow(0)
        pet.feedingChecklist = false
        pet.checklistPaper = nil
        positionResults()
    }

    private func hideResults() {
        results?.orderOut(nil)
        pet.checklistVisible = false
    }

    private func present() {
        pet.checklistVisible = true
        results?.orderFrontRegardless()
        positionResults()
    }

    func show(_ url: URL) {
        guard !pet.busy else { return }
        if results == nil {
            let panel = ChecklistWindow(contentRect: NSRect(origin: .zero, size: resultSize),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = "清理清单"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.isMovable = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            results = panel
        }
        results?.contentViewController = NSHostingController(rootView: Panel(initial: url, petState: { [weak self] busy, cutting in
            self?.pet.busy = busy
            self?.pet.cutting = cutting
        }, hide: { [weak self] in
            self?.hideResults()
        }, captureSheet: { [weak self] in
            self?.captureSheet()
        }, beginFeed: { [weak self] in
            self?.beginFeed()
        }, endFeed: { [weak self] in
            self?.endFeed()
        }))
        results?.setContentSize(resultSize)
        present()
    }
}
@main struct Entry {
    static func main(){let app=NSApplication.shared;let host=Host();app.setActivationPolicy(.regular);app.delegate=host;withExtendedLifetime(host){app.run()}}
}

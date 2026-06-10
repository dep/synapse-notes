import SwiftUI
import AppKit

struct InlineImageMatch {
    let id: String
    let range: NSRange
    let paragraphRange: NSRange
    let source: String
    let caption: String
}

struct InlineEmbedMatch {
    let id: String
    let range: NSRange
    let paragraphRange: NSRange
    let noteName: String
    let content: String?
    let noteURL: URL?
}

// MARK: - Embedded Notes Data Model

/// Information about an embedded note for the side panel
struct EmbeddedNoteInfo: Identifiable, Equatable {
    let id: String
    let noteName: String
    let content: String?
    let noteURL: URL?
    let isUnresolved: Bool

    static func == (lhs: EmbeddedNoteInfo, rhs: EmbeddedNoteInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.noteName == rhs.noteName &&
        lhs.content == rhs.content &&
        lhs.noteURL == rhs.noteURL &&
        lhs.isUnresolved == rhs.isUnresolved
    }
}

// MARK: - Unified Sidebar Embed Model

/// The type of content embedded in the sidebar
enum SidebarEmbedType {
    case note
    case image
}

/// Unified information about any embed (note or image) for the sidebar
struct SidebarEmbedInfo: Identifiable, Equatable {
    let id: String
    let type: SidebarEmbedType
    let title: String?       // For notes (note name)
    let caption: String?     // For images (caption text)
    let content: String?     // For notes (note content)
    let source: String?      // For images (URL/path string)
    let resolvedURL: URL?    // Resolved URL for both notes and images
    let isUnresolved: Bool
    let range: NSRange      // Position in document for sorting

    /// Creates a SidebarEmbedInfo from an InlineEmbedMatch (note embed)
    static func fromEmbedMatch(_ match: InlineEmbedMatch) -> SidebarEmbedInfo {
        SidebarEmbedInfo(
            id: match.id,
            type: .note,
            title: match.noteName,
            caption: nil,
            content: match.content,
            source: nil,
            resolvedURL: match.noteURL,
            isUnresolved: match.noteURL == nil,
            range: match.range
        )
    }

    /// Creates a SidebarEmbedInfo from an InlineImageMatch (image embed)
    static func fromImageMatch(_ match: InlineImageMatch, relativeTo noteURL: URL?) -> SidebarEmbedInfo {
        let resolved = resolvedSidebarImageURL(for: match.source, relativeTo: noteURL)
        return SidebarEmbedInfo(
            id: match.id,
            type: .image,
            title: nil,
            caption: match.caption.isEmpty ? nil : match.caption,
            content: nil,
            source: match.source,
            resolvedURL: resolved,
            isUnresolved: resolved == nil,
            range: match.range
        )
    }
}

/// Resolves an image source string to a URL for sidebar display
func resolvedSidebarImageURL(for source: String, relativeTo noteURL: URL?) -> URL? {
    let cleanedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedSource.isEmpty else { return nil }

    // Handle web URLs
    if cleanedSource.hasPrefix("http://") || cleanedSource.hasPrefix("https://") {
        return URL(string: cleanedSource)
    }

    // Handle file:// URLs
    if cleanedSource.hasPrefix("file://") {
        return URL(string: cleanedSource)
    }

    // Handle absolute paths
    if cleanedSource.hasPrefix("/") {
        return URL(fileURLWithPath: cleanedSource)
    }

    // Handle relative paths
    guard let noteURL = noteURL else { return nil }
    let baseURL = noteURL.deletingLastPathComponent()
    return URL(fileURLWithPath: cleanedSource, relativeTo: baseURL).standardizedFileURL
}

// MARK: - Embedded Notes Side Panel

struct EmbeddedNotesPanel: NSViewRepresentable {
    let notes: [SidebarEmbedInfo]
    let allFiles: [URL]
    let selectedEmbedID: String?
    let onOpenFile: (URL, Bool) -> Void // (url, openInNewTab)
    let onScrollToEmbed: ((NSRange) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SynapseTheme.editorBackground

        let documentView = FlippedNSView()
        documentView.autoresizingMask = [.width]
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = SynapseTheme.editorBackground.cgColor
        scrollView.documentView = documentView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let documentView = scrollView.documentView else { return }

        scrollView.drawsBackground = true
        scrollView.backgroundColor = SynapseTheme.editorBackground
        scrollView.contentView.backgroundColor = SynapseTheme.editorBackground
        scrollView.documentView?.wantsLayer = true
        scrollView.documentView?.layer?.backgroundColor = SynapseTheme.editorBackground.cgColor

        let width: CGFloat = 304 // 320 - 16 padding
        let spacing: CGFloat = 12
        var currentY: CGFloat = 8
        var selectedView: NSView?
        var selectedViewY: CGFloat = 0

        // Track which embed IDs we've processed
        var processedIDs = Set<String>()

        for embed in notes {
            processedIDs.insert(embed.id)
            let isSelected = embed.id == selectedEmbedID

            // Find existing view for this embed ID
            let existingView = documentView.subviews.first { $0.identifier?.rawValue == embed.id }

            switch embed.type {
            case .note:
                let embedView: EmbeddedNoteView
                if let existing = existingView as? EmbeddedNoteView {
                    embedView = existing
                } else {
                    embedView = EmbeddedNoteView()
                    embedView.identifier = NSUserInterfaceItemIdentifier(embed.id)
                    embedView.onOpenNote = { url, openInNewTab in
                        onOpenFile(url, openInNewTab)
                    }
                    documentView.addSubview(embedView)
                }

                embedView.configure(
                    noteName: embed.title ?? "Note",
                    content: embed.content,
                    noteURL: embed.resolvedURL,
                    isUnresolved: embed.isUnresolved
                )

                // Calculate height
                let preferredSize = embedView.preferredSize(for: embed.content)
                let height = min(preferredSize.height, 400)

                embedView.frame = NSRect(x: 0, y: currentY, width: width, height: height)

                if isSelected {
                    selectedView = embedView
                    selectedViewY = currentY
                }

                currentY += height + spacing

            case .image:
                let imageView: EmbeddedImageView
                if let existing = existingView as? EmbeddedImageView {
                    imageView = existing
                } else {
                    imageView = EmbeddedImageView()
                    imageView.identifier = NSUserInterfaceItemIdentifier(embed.id)
                    imageView.onScrollToMarkdown = { [range = embed.range] in
                        onScrollToEmbed?(range)
                    }
                    documentView.addSubview(imageView)
                }

                imageView.configure(
                    caption: embed.caption,
                    imageURL: embed.resolvedURL,
                    isUnresolved: embed.isUnresolved,
                    isSelected: isSelected
                )

                let height: CGFloat = embed.caption != nil ? 246 : 228
                imageView.frame = NSRect(x: 0, y: currentY, width: width, height: height)

                if isSelected {
                    selectedView = imageView
                    selectedViewY = currentY
                }

                currentY += height + spacing
            }
        }

        // Remove views that are no longer needed
        documentView.subviews.forEach { view in
            if let id = view.identifier?.rawValue, !processedIDs.contains(id) {
                view.removeFromSuperview()
            }
        }

        // Set document view size
        let totalHeight = max(currentY - spacing + 8, scrollView.bounds.height)
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)

        // Scroll selected view into view
        if let selectedView = selectedView {
            let visibleRect = NSRect(
                x: 0,
                y: selectedViewY,
                width: width,
                height: selectedView.frame.height
            )
            scrollView.contentView.scrollToVisible(visibleRect)
        }
    }
}

// NSView subclass with flipped coordinate system so (0,0) is at top-left
final class FlippedNSView: NSView {
    override var isFlipped: Bool { true }
}

final class EmbeddedNoteView: NSView {
    private let contentScrollView = NSScrollView()
    private let contentTextView = NSTextView()
    private let titleField = NSTextField(labelWithString: "")
    private let borderView = NSView()
    private let openButton = NSButton()
    private var targetURL: URL?
    var onOpenNote: ((URL, Bool) -> Void)? // (url, openInNewTab)

    // Fixed dimensions for the right-aligned panel
    private let panelWidth: CGFloat = 280
    private let maxPanelHeight: CGFloat = 400
    private let minPanelHeight: CGFloat = 120

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(noteName: String, content: String?, noteURL: URL?, isUnresolved: Bool) {
        targetURL = noteURL
        titleField.stringValue = isUnresolved ? "Note not found: \(noteName)" : noteName

        if isUnresolved {
            contentTextView.string = ""
            contentScrollView.isHidden = true
            borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor
            borderView.layer?.borderColor = SynapseTheme.nsError.cgColor
        } else if let content = content {
            let styledContent = styleMarkdownContent(content, fontSize: 11)
            contentTextView.textStorage?.setAttributedString(styledContent)
            contentScrollView.isHidden = false
            borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor
            borderView.layer?.borderColor = SynapseTheme.nsBorder.cgColor
        }

        openButton.isHidden = (noteURL == nil)
        updateColors()
    }

    /// Re-applies all theme-dependent colors. Safe to call any time the theme changes.
    func updateColors() {
        borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor
        titleField.textColor = SynapseTheme.nsTextPrimary
        contentTextView.backgroundColor = SynapseTheme.editorCodeBackground
        contentTextView.textColor = SynapseTheme.nsTextSecondary
        contentScrollView.backgroundColor = SynapseTheme.editorCodeBackground
        // Re-style markdown content with the new theme colors
        if let text = contentTextView.string.isEmpty ? nil : contentTextView.string {
            let styledContent = styleMarkdownContent(text, fontSize: 11)
            contentTextView.textStorage?.setAttributedString(styledContent)
        }
    }

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        let padding: CGFloat = 12
        let buttonHeight: CGFloat = 28
        let titleHeight: CGFloat = 20
        let spacing: CGFloat = 8

        // Border view fills the entire frame
        borderView.frame = bounds

        // Title at top
        titleField.frame = NSRect(
            x: padding,
            y: bounds.height - padding - titleHeight,
            width: bounds.width - padding * 2,
            height: titleHeight
        )

        // Open button at bottom
        openButton.frame = NSRect(
            x: bounds.width - padding - 80,
            y: padding,
            width: 80,
            height: buttonHeight
        )

        // Content scroll view fills the middle area
        if !contentScrollView.isHidden {
            let contentY = buttonHeight + padding + spacing
            let contentHeight = bounds.height - contentY - titleHeight - spacing * 2
            contentScrollView.frame = NSRect(
                x: padding,
                y: contentY,
                width: bounds.width - padding * 2,
                height: max(0, contentHeight)
            )
        }
    }

    @objc private func openNote() {
        guard let url = targetURL else { return }
        // Check if Command key is held (for opening in new tab)
        let openInNewTab = NSEvent.modifierFlags.contains(.command)
        onOpenNote?(url, openInNewTab)
    }

    private func setup() {
        // Border view
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 6
        borderView.layer?.masksToBounds = true
        borderView.layer?.borderWidth = 1
        borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor
        borderView.layer?.borderColor = SynapseTheme.nsBorder.cgColor
        borderView.autoresizingMask = [.width, .height]
        addSubview(borderView)

        // Title field
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = SynapseTheme.nsTextPrimary
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)

        // Content text view (read-only)
        contentTextView.isEditable = false
        contentTextView.isSelectable = true
        contentTextView.isRichText = false
        contentTextView.backgroundColor = SynapseTheme.editorCodeBackground
        contentTextView.textContainerInset = NSSize(width: 8, height: 8)
        contentTextView.font = .systemFont(ofSize: 11)
        contentTextView.textColor = SynapseTheme.nsTextSecondary

        // Content scroll view
        contentScrollView.documentView = contentTextView
        contentScrollView.hasVerticalScroller = true
        contentScrollView.autohidesScrollers = true
        contentScrollView.borderType = .bezelBorder
        contentScrollView.backgroundColor = SynapseTheme.editorCodeBackground
        contentScrollView.isHidden = true
        addSubview(contentScrollView)

        // Open button
        openButton.title = "Open"
        openButton.target = self
        openButton.action = #selector(openNote)
        openButton.bezelStyle = .rounded
        openButton.font = .systemFont(ofSize: 11, weight: .medium)
        addSubview(openButton)
    }

    // Return the preferred size for this panel
    func preferredSize(for content: String?) -> NSSize {
        let padding: CGFloat = 12
        let buttonHeight: CGFloat = 28
        let titleHeight: CGFloat = 20
        let spacing: CGFloat = 8

        if content == nil {
            // Unresolved: just title + button
            return NSSize(width: panelWidth, height: minPanelHeight)
        }

        // Calculate content height based on text
        let textStorage = NSTextStorage(string: content!)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(width: panelWidth - padding * 2 - 20, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let contentHeight = layoutManager.usedRect(for: textContainer).height + 16 // +16 for insets
        let totalHeight = padding + buttonHeight + spacing + min(contentHeight, 300) + spacing + titleHeight + padding

        return NSSize(width: panelWidth, height: min(max(totalHeight, minPanelHeight), maxPanelHeight))
    }
}

// MARK: - Embedded Image View

final class EmbeddedImageView: NSView {
    private let imageView = NSImageView()
    private let captionField = NSTextField(labelWithString: "")
    private let borderView = NSView()
    private let previewBackgroundView = NSView()
    private let openButton = NSButton()
    private var targetURL: URL?
    private var isSelected: Bool = false
    var onScrollToMarkdown: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(caption: String?, imageURL: URL?, isUnresolved: Bool, isSelected: Bool = false) {
        targetURL = imageURL
        self.isSelected = isSelected
        openButton.isHidden = imageURL == nil || isUnresolved

        if isUnresolved {
            captionField.stringValue = caption ?? "Image not found"
            imageView.image = nil
        } else {
            captionField.stringValue = caption ?? ""
            // Load image asynchronously
            if let imageURL = imageURL {
                loadImage(from: imageURL)
            }
        }

        captionField.isHidden = (caption == nil || caption?.isEmpty == true)

        // Update border color based on selection state
        updateBorderAppearance()
        updateColors()
    }

    private func updateBorderAppearance() {
        borderView.layer?.borderWidth = isSelected ? 3 : 1
        borderView.layer?.borderColor = isSelected
            ? NSColor(SynapseTheme.accent).cgColor
            : NSColor(SynapseTheme.border).cgColor
    }

    /// Re-applies all theme-dependent colors. Safe to call any time the theme changes.
    func updateColors() {
        borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor
        previewBackgroundView.layer?.backgroundColor = SynapseTheme.editorCodeBackground.cgColor
        updateBorderAppearance()
        captionField.textColor = NSColor(SynapseTheme.textSecondary)
    }

    private func loadImage(from url: URL) {
        // Load image in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = NSImage(contentsOf: url) else { return }
            DispatchQueue.main.async {
                self?.imageView.image = image
                self?.needsLayout = true
            }
        }
    }

    override func layout() {
        super.layout()

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        // Update border frame and appearance
        borderView.frame = bounds
        updateBorderAppearance()

        let padding: CGFloat = 12
        let spacing: CGFloat = 10
        let buttonHeight: CGFloat = openButton.isHidden ? 0 : 24
        let captionHeight: CGFloat = captionField.isHidden ? 0 : 20

        let buttonY = padding
        let previewBottom = buttonY + buttonHeight + (openButton.isHidden ? 0 : spacing)
        let previewTop = bounds.height - padding - captionHeight - (captionField.isHidden ? 0 : spacing)
        let previewRect = NSRect(
            x: padding,
            y: previewBottom,
            width: bounds.width - padding * 2,
            height: max(120, previewTop - previewBottom)
        )

        previewBackgroundView.frame = previewRect

        let contentRect = previewRect.insetBy(dx: 8, dy: 8)
        if let image = imageView.image, image.size.width > 0, image.size.height > 0 {
            let widthRatio = contentRect.width / image.size.width
            let heightRatio = contentRect.height / image.size.height
            let scale = min(widthRatio, heightRatio)
            let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = NSRect(
                x: round(contentRect.midX - drawSize.width / 2),
                y: round(contentRect.midY - drawSize.height / 2),
                width: round(drawSize.width),
                height: round(drawSize.height)
            )
        } else {
            imageView.frame = contentRect
        }
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = nil

        // Caption label
        if !captionField.isHidden {
            captionField.frame = NSRect(
                x: padding,
                y: bounds.height - padding - captionHeight,
                width: bounds.width - padding * 2,
                height: captionHeight
            )
            captionField.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            captionField.textColor = NSColor(SynapseTheme.textSecondary)
            captionField.lineBreakMode = .byTruncatingMiddle
            captionField.alignment = .left
        }

        let buttonWidth = min(124, bounds.width - padding * 2)
        openButton.frame = NSRect(
            x: round((bounds.width - buttonWidth) / 2),
            y: padding,
            width: buttonWidth,
            height: buttonHeight
        )
        openButton.bezelStyle = .rounded
        openButton.font = .systemFont(ofSize: 11, weight: .semibold)
    }

    private var imageViewerController: ImageViewerWindowController?

    @objc private func openImage() {
        guard let targetURL = targetURL else { return }

        let viewer = ImageViewerWindowController(imageURL: targetURL, caption: captionField.stringValue.isEmpty ? nil : captionField.stringValue)
        imageViewerController = viewer // retain strongly so it isn't deallocated before image loads
        viewer.showFullScreen()
    }

    private func setup() {
        // Setup border view layer properties
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 6
        borderView.layer?.masksToBounds = true
        borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor

        addSubview(borderView)
        previewBackgroundView.wantsLayer = true
        previewBackgroundView.layer?.cornerRadius = 8
        previewBackgroundView.layer?.masksToBounds = true
        previewBackgroundView.layer?.backgroundColor = SynapseTheme.editorCodeBackground.cgColor
        previewBackgroundView.layer?.borderWidth = 0
        addSubview(previewBackgroundView)
        addSubview(imageView)
        addSubview(captionField)

        openButton.title = "Open"
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openImage)
        addSubview(openButton)

        // Click on image thumbnail scrolls editor to the markdown
        let click = NSClickGestureRecognizer(target: self, action: #selector(thumbnailClicked))
        imageView.addGestureRecognizer(click)

        // Initial border appearance
        updateBorderAppearance()
    }

    @objc private func thumbnailClicked() {
        onScrollToMarkdown?()
    }
}

// MARK: - Full Screen Image Viewer

/// A full-screen window for viewing images with zoom and pan support
final class ImageViewerWindowController: NSWindowController {
    private let imageView = NSImageView()
    private let imageContainerView = NSView()
    private var imageURL: URL?
    private var localMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollView: NSScrollView!
    private var currentZoom: CGFloat = 1.0
    private var minZoom: CGFloat = 0.1
    private var maxZoom: CGFloat = 5.0
    private var imageSize: NSSize = .zero
    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    private var gestureStartZoom: CGFloat = 1.0

    init(imageURL: URL, caption: String?) {
        let window = NSWindow(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = caption ?? imageURL.lastPathComponent
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = true

        super.init(window: window)

        self.imageURL = imageURL
        setupContentView()
        setupImageView()
        setupCloseButton()
        setupEscapeHandler()
        loadImage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupContentView() {
        guard let window = window else { return }

        scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = false
        scrollView.backgroundColor = .black
        scrollView.drawsBackground = true

        window.contentView = scrollView
    }

    private func setupImageView() {
        imageContainerView.wantsLayer = true
        imageContainerView.layer?.backgroundColor = NSColor.black.cgColor
        imageContainerView.frame = scrollView.bounds

        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        imageContainerView.addSubview(imageView)
        imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: 100)
        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 100)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: imageContainerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageContainerView.centerYAnchor),
            imageWidthConstraint!,
            imageHeightConstraint!
        ])

        scrollView.documentView = imageContainerView

        setupGestureRecognizers()
        setupScrollWheelZoom()
    }

    private func setupScrollWheelZoom() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, let window = self.window else { return event }

            if NSApp.keyWindow == window && event.modifierFlags.contains(.control) {
                let delta = event.scrollingDeltaY
                let zoomFactor = pow(1.01, delta * 0.35)
                let newZoom = self.currentZoom * zoomFactor
                self.setZoom(newZoom, animated: false)
                return nil
            }
            return event
        }
    }

    private func setupGestureRecognizers() {
        let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClickGesture.numberOfClicksRequired = 2
        imageView.addGestureRecognizer(doubleClickGesture)

        let magnifyGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        imageView.addGestureRecognizer(magnifyGesture)
    }

    @objc private func handleDoubleClick() {
        // Toggle between fit-to-screen and 100% zoom
        if currentZoom != 1.0 {
            setZoom(1.0, animated: true)
        } else {
            fitImageToScreen()
        }
    }

    @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        switch gesture.state {
        case .began:
            gestureStartZoom = currentZoom
        case .changed:
            let newZoom = gestureStartZoom * (1 + gesture.magnification)
            setZoom(newZoom, animated: false)
        default:
            break
        }
    }

    private func setZoom(_ zoom: CGFloat, animated: Bool) {
        let clampedZoom = max(minZoom, min(maxZoom, zoom))
        currentZoom = clampedZoom

        let applyLayout = { self.layoutImage(centerViewport: true) }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                applyLayout()
            }
        } else {
            applyLayout()
        }
    }

    private func fitImageToScreen() {
        guard imageSize != .zero, let window = window else { return }

        let visibleFrame = window.contentView?.bounds ?? window.frame
        let titleBarHeight: CGFloat = 28
        let availableHeight = visibleFrame.height - titleBarHeight - 40
        let availableWidth = visibleFrame.width - 40

        let widthRatio = availableWidth / imageSize.width
        let heightRatio = availableHeight / imageSize.height
        currentZoom = min(widthRatio, heightRatio, 1.0)
        layoutImage(centerViewport: true)
    }

    private func layoutImage(centerViewport: Bool) {
        guard imageSize != .zero else { return }

        let visibleSize = scrollView.contentView.bounds.size
        let scaledSize = NSSize(width: imageSize.width * currentZoom, height: imageSize.height * currentZoom)
        let containerSize = NSSize(
            width: max(visibleSize.width, scaledSize.width),
            height: max(visibleSize.height, scaledSize.height)
        )

        imageContainerView.frame = NSRect(origin: .zero, size: containerSize)
        imageWidthConstraint?.constant = scaledSize.width
        imageHeightConstraint?.constant = scaledSize.height
        imageContainerView.layoutSubtreeIfNeeded()

        if centerViewport {
            let centeredOrigin = NSPoint(
                x: max(0, (containerSize.width - visibleSize.width) / 2),
                y: max(0, (containerSize.height - visibleSize.height) / 2)
            )
            scrollView.contentView.scroll(to: centeredOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func setupCloseButton() {
        // Native window close button (traffic light) is sufficient
    }

    private func setupEscapeHandler() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let window = self.window else { return event }

            if NSApp.keyWindow == window && event.keyCode == 53 {
                self.closeWindow()
                return nil
            }
            return event
        }
    }

    private func loadImage() {
        guard let imageURL = imageURL else { return }

        // Handle remote URLs (http/https)
        if imageURL.scheme?.lowercased() == "http" || imageURL.scheme?.lowercased() == "https" {
            downloadRemoteImage(from: imageURL)
            return
        }

        // Handle local file URLs
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imageURL.path) {
            print("Image file does not exist at: \(imageURL.path)")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = NSImage(contentsOf: imageURL) else {
                print("Failed to load image from: \(imageURL.path)")
                return
            }

            DispatchQueue.main.async {
                self?.imageSize = image.size
                self?.imageView.image = image
                self?.updateImageViewSize()
                self?.fitImageToScreen()
                print("Image loaded successfully: \(image.size.width)x\(image.size.height)")
            }
        }
    }

    private func downloadRemoteImage(from url: URL) {
        print("Downloading remote image from: \(url.absoluteString)")

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                print("Failed to download image: \(error.localizedDescription)")
                return
            }

            guard let data = data, let image = NSImage(data: data) else {
                print("Failed to create image from downloaded data")
                return
            }

            DispatchQueue.main.async {
                self?.imageSize = image.size
                self?.imageView.image = image
                self?.updateImageViewSize()
                self?.fitImageToScreen()
                print("Remote image loaded successfully: \(image.size.width)x\(image.size.height)")
            }
        }

        task.resume()
    }

    private func updateImageViewSize() {
        layoutImage(centerViewport: true)
    }

    @objc private func closeWindow() {
        window?.close()
    }

    func showFullScreen() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)

        // Make it nearly full screen but keep title bar
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let padding: CGFloat = 40
            let newFrame = NSRect(
                x: screenFrame.origin.x + padding,
                y: screenFrame.origin.y + padding,
                width: screenFrame.width - (padding * 2),
                height: screenFrame.height - (padding * 2)
            )
            window?.setFrame(newFrame, display: true, animate: true)
        }
    }
}

final class YouTubePreviewView: NSView {
    private let thumbnailView = NSImageView()
    private let overlay = NSView()
    private let playIcon = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private var targetURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(SynapseTheme.border).cgColor
        layer?.backgroundColor = SynapseTheme.editorCodeBackground.cgColor

        thumbnailView.frame = bounds
        overlay.frame = bounds
        actionButton.frame = bounds

        let iconSize: CGFloat = 54
        playIcon.frame = NSRect(x: 20, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize)

        let textX = playIcon.frame.maxX + 18
        let textWidth = max(160, bounds.width - textX - 20)
        titleField.frame = NSRect(x: textX, y: bounds.midY + 2, width: textWidth, height: 28)
        subtitleField.frame = NSRect(x: textX, y: bounds.midY - 28, width: textWidth, height: 44)
    }

    @objc private func openVideo() {
        guard let targetURL else { return }
        NSWorkspace.shared.open(targetURL)
    }

    private func setup() {
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.imageAlignment = .alignCenter
        thumbnailView.autoresizingMask = [.width, .height]
        addSubview(thumbnailView)

        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)

        if let image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil) {
            playIcon.image = image
        }
        playIcon.contentTintColor = .white
        addSubview(playIcon)

        titleField.font = .systemFont(ofSize: 20, weight: .bold)
        titleField.textColor = NSColor(SynapseTheme.textPrimary)
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)

        subtitleField.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleField.textColor = NSColor(SynapseTheme.textSecondary)
        subtitleField.lineBreakMode = .byTruncatingMiddle
        addSubview(subtitleField)

        actionButton.isBordered = false
        actionButton.title = ""
        actionButton.target = self
        actionButton.action = #selector(openVideo)
        actionButton.autoresizingMask = [.width, .height]
        addSubview(actionButton)
    }
}

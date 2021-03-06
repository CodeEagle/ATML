//
//  ATML.swift
//  ATML
//
//  Created by Lincoln Law on 2017/5/24.
//  Copyright © 2017年 Lincoln Law. All rights reserved.
//

import Foundation
import WebKit
import Kingfisher
import KVOBlock

// MARK: - ATML
public final class ATML: NSObject, NSLayoutManagerDelegate {
    public typealias ATMLAttachmentMap = (Attachment) -> UIView?
    typealias TextStorageEnumerateFilter = (Any?, NSRange, UnsafeMutablePointer<ObjCBool>) -> Void
    public weak var base: UITextView?
    public var enableAutoLoadAttachment = true
    public var preloadAttachmentCount = Int.max {
        didSet {
            _currentPreloadAttachmentCount = preloadAttachmentCount
        }
    }
    public var preloadRect = CGRect.zero {
        didSet {
            _currentPreloadRect = preloadRect
        }
    }
    
    fileprivate var _currentPreloadAttachmentCount = Int.max
    fileprivate var _currentPreloadRect = CGRect.zero
    fileprivate var _lastY: CGFloat = 0

    fileprivate lazy var _defaultAttachmentMap: ATMLAttachmentMap = {[unowned self] attachment in
        let tag = attachment.tagName
        let src = attachment.src
        let isRemote = src.hasPrefix("http") || src.hasPrefix("ftp")
        if tag == Attachment.Tag.image.rawValue, isRemote {
            var size = attachment.size
            let width = UIScreen.main.bounds.width
            if size != .zero, size.height != 0 {
                let ratio = size.width / size.height
                if size.width > width {
                    size.width = width
                    size.height = width / ratio
                }
                attachment.maxSize = size
            }
            let imageView: UIImageView = UIImageView(frame: CGRect(origin: .zero, size: size))
            var handler: CompletionHandler?
            
            if size.width == 0 || size.height == 0 {
                handler = {[weak self] obj in
                    guard let image = obj.0, let sself = self else { return }
                    var imgSize = image.size
                    let ratio = imgSize.width / imgSize.height
                    if size.width != 0 {
                        imgSize.width = size.width
                        imgSize.height = imgSize.width / ratio
                    }
                    if imgSize.width > width {
                        imgSize.width = width
                        imgSize.height = width / ratio
                    }
                    attachment.size = imgSize
                    attachment.maxSize = imgSize
                    imageView.frame.size = imgSize
                    DispatchQueue.main.async {
                        sself.layoutAttachments()
                    }
                }
            }
            if let link = attachment.link {
                let tag = attachment.identifier.hashValue
                self._imageInfo[tag] = link
                imageView.tag = tag
                let tap = UITapGestureRecognizer(target: self, action: #selector(ATML.imageTap(tap:)))
                imageView.addGestureRecognizer(tap)
                imageView.isUserInteractionEnabled = true
            }
            imageView.contentMode = .scaleAspectFit
            imageView.kf.setImage(with: URL(string: src), options: [.transition(ImageTransition.fade(1))], completionHandler: handler)
            
            return imageView
        }
        if tag == Attachment.Tag.iframe.rawValue, let url = URL(string: src) {
            var size = attachment.size
            let ratio = size.width / size.height
            let width = UIScreen.main.bounds.width
            if size.width > width {
                size.width = width
                size.height = size.width / ratio
            }
            attachment.maxSize = size
            let web: WKWebView = WKWebView(frame: CGRect(origin: .zero, size: size))
            web.scrollView.scrollsToTop = false
            web.scrollView.isScrollEnabled = false
            web.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))
            return web
        }
        if tag == Attachment.Tag.blockquote.rawValue {
            guard let html = attachment.html else { return nil }
            let view = BlockQuoteView(with: html, font: self._font, completion: {[weak self] (h) in
                var size = attachment.size
                let width = UIScreen.main.bounds.width
                if size.width > width {
                    size.width = width
                }
                size.height = h
                attachment.maxSize = size
                attachment.size = size
                DispatchQueue.main.async {
                    self?.layoutAttachments()
                }
            })
            attachment.maxSize = view.bounds.size
            attachment.size = view.bounds.size
            return view
        }
        if tag == Attachment.Tag.seperator.rawValue {
            let view = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 0.5))
            view.backgroundColor = UIColor.darkGray
            attachment.maxSize = view.bounds.size
            attachment.size = view.bounds.size
            view.isUserInteractionEnabled = false
            return view
        }
        return nil
    }

    public var attachmentMap: ATMLAttachmentMap?

    public var attachments: [Attachment] = []

    private var _imageInfo: [Int: String] = [:]
    fileprivate var _font: FontInfo = FontInfo()
    fileprivate var _needAddToSuperviewIds: [String] = []
    fileprivate var _attachmentInfoMap: [String: AttachmentInfo] = [:]
    fileprivate let _kvoAttributedTextKey = "attributedText"
    fileprivate static var Store = "ATML.Store"
    private var _lastRange: NSRange?
    private var _lastFrame: CGRect?
    
    var layoutManager: NSLayoutManager? { return base?.layoutManager }
    
    public init(_ base: UITextView) {
        self.base = base
        super.init()
        base.observeKeyPath(_kvoAttributedTextKey) { [unowned self] _, _, _ in
            guard self.base != nil else { return }
            self.resetAttachments()
        }
        base.observeKeyPath("contentSize") { target, _, _ in
            guard let view = target as? UITextView else { return }
            print(view.contentSize.height)
        }
        layoutManager?.delegate = self
    }

    func display(html: String, documentAttributes: [String: Any]? = nil, done: @escaping () -> ()) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = self.emhanceImageWithLink(for: html)
            var att: NSAttributedString?
            if #available(iOS 9.0, *) {
                att = text.attributedString(withDocumentAttributes: documentAttributes)
            }
            DispatchQueue.main.async {
                if #available(iOS 9.0, *) { } else {
                    att = text.attributedString(withDocumentAttributes: documentAttributes)
                }
                self._currentPreloadRect = self.preloadRect
                self._currentPreloadAttachmentCount = self.preloadAttachmentCount
                self.base?.attributedText = att
                done()
            }
        }
    }
   
    @objc private func imageTap(tap: UITapGestureRecognizer) {
        guard let tag = tap.view?.tag, let info = _imageInfo[tag], let url = URL(string: info), let tv = base else { return }
        guard tv.delegate?.textView?(tv, shouldInteractWith: url, in: NSMakeRange(0, 0)) == nil else { return }
        if #available(iOS 10.0, *) {
            _ = tv.delegate?.textView?(tv, shouldInteractWith: url, in: NSMakeRange(0, 0), interaction: .invokeDefaultAction)
        }
    }

    private func emhanceImageWithLink(for text: String) -> String {
        
        let linkRegex = ATML.Attachment.Tag.link.regex
        let results = linkRegex.matches(in: text, options: [], range: NSMakeRange(0, text.characters.count))
        var placeholders = [String : String]()
        var raw = text as NSString
        for (i, result) in results.enumerated() {
            let id = "placeholder\(i)"
            let sub = (text as NSString).substring(with: result.range)
            raw = raw.replacingOccurrences(of: sub, with: id) as NSString
            placeholders[id] = sub
        }
        let parser = ATML.ATMLXMLParser()
        for (key, value) in placeholders {
            let subimages = images(within: value)
            parser.parse(value)
            var copy = value
            if subimages.count > 0, let href = parser.tagAttributes["a"]?["href"]  {
                for image in subimages {
                    let target = image.replacingOccurrences(of: "src=", with: "link=\"\(href)\" src=")
                    copy = copy.replacingOccurrences(of: image, with: target)
                }
            }
            raw = raw.replacingOccurrences(of: key, with: copy) as NSString
        }
        return raw as String
    }
    
    
    private func images(within text: String) -> [String] {
        let imageRegex = ATML.Attachment.Tag.image.regex
        let results = imageRegex.matches(in: text, options: [], range: NSMakeRange(0, text.characters.count))
        var final = [String]()
        let raw = text as NSString
        for result in results {
            let sub = raw.substring(with: result.range)
            final.append(sub)
        }
        return final
    }
    
    public func viewForAttachment(_ attachment: Attachment) -> UIView? {
        return _attachmentInfoMap[attachment.identifier]?.view
    }

    public func assignView(_ view: UIView, for attachment: Attachment) {
        if let info = _attachmentInfoMap[attachment.identifier] {
            info.view.removeFromSuperview()
            info.view = view
        } else {
            let i = AttachmentInfo(id: attachment.identifier, view: view)
            _attachmentInfoMap[attachment.identifier] = i
        }
        base?.addSubview(view)
        resize(attachment: attachment, to: base?.textContainer.size)
        layoutAttachments()
    }

    public func layoutAttachments() {
        guard let textStorage = layoutManager?.textStorage else { return }
        var exclusionPaths = base?.textContainer.exclusionPaths
        for (_, info) in _attachmentInfoMap {
            guard let path = info.exclusionPath, let idx = exclusionPaths?.index(of: path) else { continue }
            exclusionPaths?.remove(at: idx)
        }
        if let path = exclusionPaths { base?.textContainer.exclusionPaths = path }
        if let container = base?.textContainer { layoutManager?.ensureLayout(for: container) }
        let filter: TextStorageEnumerateFilter = {[unowned self] object, range, _ in
            guard let attachment = object as? Attachment else { return }
            self.layout(attachment, atRange: range)
        }
        textStorage.enumerateAttribute(NSAttachmentAttributeName, in: textStorage.wholeRange, options: [], using: filter)
    }
    
    public func loadLeftAttachments() {
        _lastY = 0
        _currentPreloadRect = .zero
        _currentPreloadAttachmentCount = Int.max
        for id in _needAddToSuperviewIds {
            guard let view = _attachmentInfoMap[id]?.view else { continue }
            self.base?.addSubview(view)
        }
        _needAddToSuperviewIds.removeAll()
        resetAttachments()
    }
    
    private func reset() {
        guard let textContainer = base?.textContainer else { return }
        for (_, info) in _attachmentInfoMap {
            info.view.removeFromSuperview()
            guard let path = info.exclusionPath, let idx = textContainer.exclusionPaths.index(of: path) else { return }
            textContainer.exclusionPaths.remove(at: idx)
        }
        _needAddToSuperviewIds.removeAll()
        _attachmentInfoMap.removeAll()
        attachments.removeAll()
    }

    private func resetAttachments() {
        reset()
        guard let textStorage = layoutManager?.textStorage else { return }
        let filter: TextStorageEnumerateFilter = { [unowned self] (object: Any?, _, _) in
            guard let attachment = object as? Attachment else { return }
            
            func doAdd(toSuperview: Bool) {
                self.attachments.append(attachment)
                var targetView = self.attachmentMap?(attachment)
                if targetView == nil, self.enableAutoLoadAttachment {
                    targetView = self._defaultAttachmentMap(attachment)
                    if attachment.tagName != Attachment.Tag.seperator.rawValue {
                        targetView?.backgroundColor = self.base?.backgroundColor
                    }
                    targetView?.isOpaque = true
                }
                guard let view = targetView else { return }
                self._attachmentInfoMap[attachment.identifier] = AttachmentInfo(id: attachment.identifier, view: view)
                self.resize(attachment: attachment, to: self.base?.textContainer.size)
                if toSuperview {
                    self.base?.addSubview(view)
                } else {
                    self._needAddToSuperviewIds.append(attachment.identifier)
                }
            }
            if self._currentPreloadRect != .zero {
                guard let manager = self.base?.layoutManager, let container = self.base?.textContainer else { return }
                let range = NSMakeRange(attachment.location, 1)
                var glyphRange = NSRange()
                manager.characterRange(forGlyphRange: range, actualGlyphRange: &glyphRange)
                let rect = manager.boundingRect(forGlyphRange: glyphRange, in: container)
                
                if self._lastY > self._currentPreloadRect.maxY {
//                    doAdd(toSuperview: false)
                    return
                }
                if rect.minY < self._currentPreloadRect.maxY {
                    doAdd(toSuperview: true)
                }
                self._lastY = rect.maxY
            } else if attachment.index + 1 <= self._currentPreloadAttachmentCount {
                doAdd(toSuperview: true)
            } else {
//                doAdd(toSuperview: false)
            }
        }
        layoutManager?.textStorage?.enumerateAttribute(NSAttachmentAttributeName,
                                                       in: NSMakeRange(0, textStorage.length),
                                                       options: [],
                                                       using: filter)
        layoutAttachments()
    }

    private func layout(_ attachment: Attachment, atRange range: NSRange) {
        
        guard let info = _attachmentInfoMap[attachment.identifier] else { return }

        var exclusionPaths: [UIBezierPath] = base?.textContainer.exclusionPaths ?? []

        let attachmentFrame = rect(for: info.view.bounds.size, attachment: attachment, at: range)

        var exclusionFrame = attachmentFrame
        if attachment.align == .none {
            exclusionFrame = CGRect(x: 0.0, y: ceil(attachmentFrame.minY), width: base?.frame.width ?? 0, height: ceil(attachmentFrame.height))
        }
        exclusionFrame.origin.y -= base?.textContainerInset.top ?? 0

        let newExclusionPath = UIBezierPath(rect: exclusionFrame)
        exclusionPaths.append(newExclusionPath)

        info.exclusionPath = newExclusionPath
        info.view.frame = attachmentFrame
        base?.textContainer.exclusionPaths = exclusionPaths
        if let container = base?.textContainer { layoutManager?.ensureLayout(for: container) }
    }

    private func resize(attachment: Attachment, to size: CGSize?) {
        let final = size ?? .zero
        guard let info = _attachmentInfoMap[attachment.identifier] else { return }
        let view = info.view
        let orgHeight = info.view.bounds.height
        if view.frame.height == 0 { return }
        let ratio = view.frame.size.width / view.frame.size.height
        if attachment.maxSize.width == 0.0 || attachment.maxSize.width > final.width {
            view.frame.size.width = floor(final.width)
            view.frame.size.height = floor(final.width / ratio)
        } else {
            view.frame.size.width = attachment.maxSize.width
            view.frame.size.height = attachment.maxSize.height
        }
        if view.frame.height == 0 {
            view.frame.size.height = orgHeight
        }
    }

    private func rect(for size: CGSize, attachment: Attachment, at range: NSRange) -> CGRect {
        guard
            let glyphRange = layoutManager?.glyphRange(forCharacterRange: range, actualCharacterRange: nil),
            let textContainer = layoutManager?.textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil),
            let glyphBoundingRect = layoutManager?.boundingRect(forGlyphRange: glyphRange, in: textContainer),
            let lineFragmentRect = layoutManager?.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        else { return .zero }
        var y = lineFragmentRect.minY
        if attachment.align == .none {
            y = glyphBoundingRect.minX == lineFragmentRect.minX ? lineFragmentRect.minY : lineFragmentRect.maxY
        }
        var frame = CGRect(origin: .zero, size: size)
        let width = base?.textContainer.size.width ?? 0
        if size.width > width {
            frame.size.width = width
        }
        let topLinePadding: CGFloat = 4.0
        let offset = (base?.textContainerInset.left ?? 0)
        frame.origin.y = y + (base?.textContainerInset.top ?? 0) + topLinePadding
        
        switch attachment.align {
        case .none: frame.origin.x =  (width) / 2.0 - (frame.size.width / 2.0) + offset
        case .left: frame.origin.x = 0.0
        case .right: frame.origin.x = width - frame.size.width
        case .center: frame.origin.x = width / 2.0 - (frame.size.width / 2.0) + offset
        }
        if let lastRange = _lastRange, lastRange.location + lastRange.length + 1 == range.location, let lastFrame = _lastFrame {
            frame.origin.y += lastFrame.height
        }
        _lastRange = range
        _lastFrame = frame
        return frame
    }

    // MARK: NSLayoutManagerDelegate
    public func layoutManager(_ layoutManager: NSLayoutManager, textContainer _: NSTextContainer, didChangeGeometryFrom _: CGSize) {
        guard let textStorage = layoutManager.textStorage else { return }
        let filter: TextStorageEnumerateFilter = { [unowned self] object, _, _ in
            guard let attachment = object as? Attachment else { return }
            self.resize(attachment: attachment, to: self.base?.textContainer.size)
        }
        layoutManager.textStorage?.enumerateAttribute(NSAttachmentAttributeName, in: textStorage.wholeRange,options: [], using: filter)
        layoutAttachments()
    }
    
    public struct FontInfo {
        public let fontFamily: String
        public let fontSize: CGFloat
        public let fontColor: String
        public init(fontFamily: String = "PingFangSC-Light", fontSize: CGFloat = 12, fontColor: String = "#4d4d4d") {
            self.fontFamily = fontFamily
            self.fontSize = fontSize
            self.fontColor = fontColor
        }
    }
}




// MARK: - Blockquote view
final class BlockQuoteView: WKWebView, WKNavigationDelegate {
    var loadingdone: (CGFloat) -> Void = { _ in }
    
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    convenience init(with content: String, font: ATML.FontInfo, completion: @escaping (CGFloat) -> Void) {
        let conf = WKWebViewConfiguration()
        self.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 1), configuration: conf)
        loadingdone = completion
        let final = "<html><head><meta charSet=\"utf-8\" /><title></title><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no\" /><style>  body, html{width: 100%;height: 100%;background: #fff;margin: 0;            padding: 0;} \nblockquote { padding: 15px; margin: 20px; color: #666; border-left: 4px solid #eee;} \np {font-family: \(font.fontFamily); font-size: \(font.fontSize)px; color:(font.fontColor) }</style></head><body>\(content)</body></html>"
        loadHTMLString(final, baseURL: nil)
        navigationDelegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.scrollsToTop = false
        scrollView.isScrollEnabled = false
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.body.scrollHeight") {[unowned self] (obj, _) -> Void in
            guard let h = obj as? CGFloat else { return }
            self.frame.size.height = h
            self.loadingdone(h)
        }
    }
}


// MARK: - UITextView extension
extension UITextView {
    
    public var atml: ATML {
        var value: ATML! = objc_getAssociatedObject(self, &ATML.Store) as? ATML
        if value == nil { value = ATML(self) }
        objc_setAssociatedObject(self, &ATML.Store, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return value
    }
    
    public func display(html: String, font: ATML.FontInfo = ATML.FontInfo(), documentAttributes: [String: Any]? = nil, enableAutoLoadAttachment: Bool = true, done: @escaping () -> () = {}) {
        atml._font = font
        atml.enableAutoLoadAttachment = enableAutoLoadAttachment
        atml.display(html: html, documentAttributes: documentAttributes, done: done)
    }
    
}

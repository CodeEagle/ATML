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

    fileprivate lazy var _defaultAttachmentMap: ATMLAttachmentMap = {[unowned self] attachment in
        let tag = attachment.tagName
        let src = attachment.src
        let isRemote = src.hasPrefix("http") || src.hasPrefix("ftp")
        if tag == Attachment.Tag.image.rawValue, isRemote {
            var size = attachment.size
            let ratio = size.width / size.height
            let width = UIScreen.main.bounds.width
            if size.width > width {
                size.width = width
                size.height = width / ratio
            }
            attachment.maxSize = size
            let imageView: UIImageView = UIImageView(frame: CGRect(origin: .zero, size: size))
            var handler: CompletionHandler?
            if size == .zero {
                handler = {[weak self] obj in
                    guard let image = obj.0, let sself = self else { return }
                    var imgSize = image.size
                    let ratio = imgSize.width / imgSize.height
                    let width = UIScreen.main.bounds.width
                    if imgSize.width > width {
                        imgSize.width = width
                        imgSize.height = width / ratio
                    }
                    attachment.maxSize = imgSize
                    imageView.frame.size = imgSize
                    DispatchQueue.main.async {
                        sself.layoutAttachments()
                    }
                }
            }
            imageView.contentMode = .scaleAspectFit
            imageView.kf.setImage(with: URL(string: src), options: [.transition(ImageTransition.fade(1))], completionHandler: handler)
            return imageView
        }
        if tag == Attachment.Tag.iframe.rawValue, let url = URL(string: src) {
            let size = attachment.size
            attachment.maxSize = size
            let web: WKWebView = WKWebView(frame: CGRect(origin: .zero, size: size))
            web.scrollView.scrollsToTop = false
            web.scrollView.isScrollEnabled = false
            web.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))
            return web
        }
        return nil
    }

    public var attachmentMap: ATMLAttachmentMap?

    public var attachments: [Attachment] = []

    fileprivate var _attachmentInfoMap: [String: AttachmentInfo] = [:]
    fileprivate let _kvoAttributedTextKey = "attributedText"
    fileprivate static var Store = "ATML.Store"

    var layoutManager: NSLayoutManager? { return base?.layoutManager }
    
    public init(_ base: UITextView) {
        self.base = base
        super.init()
        base.observeKeyPath(_kvoAttributedTextKey) { [unowned self] _, _, _ in
            guard self.base != nil else { return }
            self.resetAttachments()
        }
        layoutManager?.delegate = self
        
    }

    func display(html: String, documentAttributes: [String: Any]? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let att = html.attributedString(withDocumentAttributes: documentAttributes)
            DispatchQueue.main.async {
                self.base?.attributedText = att
            }
        }
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
    
    private func reset() {
        guard let textContainer = base?.textContainer else { return }
        for (_, info) in _attachmentInfoMap {
            info.view.removeFromSuperview()
            guard let path = info.exclusionPath, let idx = textContainer.exclusionPaths.index(of: path) else { return }
            textContainer.exclusionPaths.remove(at: idx)
        }
        _attachmentInfoMap.removeAll()
        attachments.removeAll()
    }

    private func resetAttachments() {
        reset()
        guard let textStorage = layoutManager?.textStorage else { return }
        let filter: TextStorageEnumerateFilter = { [unowned self] (object: Any?, _, _) in
            guard let attachment = object as? Attachment else { return }
            self.attachments.append(attachment)
            var targetView = self.attachmentMap?(attachment)
            if targetView == nil, self.enableAutoLoadAttachment {
                targetView = self._defaultAttachmentMap(attachment)
                targetView?.backgroundColor = self.base?.backgroundColor
                targetView?.isOpaque = true
            }
            guard let view = targetView else { return }
            self._attachmentInfoMap[attachment.identifier] = AttachmentInfo(id: attachment.identifier, view: view)
            self.resize(attachment: attachment, to: self.base?.textContainer.size)
            self.base?.addSubview(view)
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

        let attachmentFrame = rect(for: info, attachment: attachment, at: range)

        var exclusionFrame = attachmentFrame
        if attachment.align == .none {
            exclusionFrame = CGRect(x: 0.0, y: attachmentFrame.minY, width: base?.frame.width ?? 0, height: attachmentFrame.height)
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
        if view.frame.height == 0 { return }
        let ratio = view.frame.size.width / view.frame.size.height
        if attachment.maxSize.width == 0.0 || attachment.maxSize.width > final.width {
            view.frame.size.width = floor(final.width)
            view.frame.size.height = floor(final.width / ratio)
        } else {
            view.frame.size.width = attachment.maxSize.width
            view.frame.size.height = attachment.maxSize.height
        }
    }

    private func rect(for info: AttachmentInfo, attachment: Attachment, at range: NSRange) -> CGRect {
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
        var frame = info.view.frame
        let width = base?.textContainer.size.width ?? 0
        let topLinePadding: CGFloat = 4.0
        frame.origin.y = y + (base?.textContainerInset.top ?? 0) + topLinePadding
        switch attachment.align {
        case .none: frame.origin.x =  width / 2.0 - (info.view.frame.width / 2.0)
        case .left: frame.origin.x = 0.0
        case .right: frame.origin.x = width - info.view.frame.width
        case .center: frame.origin.x = width / 2.0 - (info.view.frame.width / 2.0)
        }
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
}


// MARK: - UITextView extension
extension UITextView {

    public var atml: ATML {
        var value: ATML! = objc_getAssociatedObject(self, &ATML.Store) as? ATML
        if value == nil { value = ATML(self) }
        objc_setAssociatedObject(self, &ATML.Store, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return value
    }

    public func display(html: String, documentAttributes: [String: Any]? = nil, enableAutoLoadAttachment: Bool = true) {
        atml.enableAutoLoadAttachment = enableAutoLoadAttachment
        atml.display(html: html, documentAttributes: documentAttributes)
    }
}

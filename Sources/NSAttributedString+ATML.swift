//
//  NSAttributedString+ATML.swift
//  ATML
//
//  Created by Lincoln Law on 2017/5/24.
//  Copyright © 2017年 Lincoln Law. All rights reserved.
//

import Foundation

private let _defaultIdentifier = "ATML.Attachment.default.identifier"
private let MediaTypes = "wav,aac,mp3,mov,mp4,m4v"

extension String {
    
    typealias Result = (processedString: String, attachments: [ATML.Attachment])
    
    internal func attributedString(withDocumentAttributes attrs: [String: Any]? = nil) -> NSAttributedString? {
        let finalParagraph = "<p></p>"
        let parsed = parsing(tags: [.image, .embed, .iframe, .audio, .video])
        let parsedString = "\(parsed.processedString)\(finalParagraph)"
        let attachments = parsed.attachments
        
        guard let data = parsedString.data(using: String.Encoding.utf8) else { return nil }
        
        var options: [String: Any] = [
            NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
            NSCharacterEncodingDocumentAttribute: String.Encoding.utf8.rawValue,
            ]
        
        if let attr = attrs { options[NSDefaultAttributesDocumentAttribute] = attr }
        guard let attrString = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else { return nil }
        for attachment in attachments {
            let raw = attrString.string
            guard let r = raw.range(of: attachment.identifier) else { continue }
            let range = raw.nsRange(from: r)
            let attachmentString = NSAttributedString(attachment: attachment)
            attrString.replaceCharacters(in: range, with: attachmentString)
        }
        return NSAttributedString(attributedString: attrString)
    }
    
    private func parsing(tags: [ATML.Attachment.Tag]) -> Result {
        var dataToProcess = self
        var attachments: [ATML.Attachment] = []
        for tag in tags {
            let result = dataToProcess.extract(tag)
            dataToProcess = result.processedString
            attachments.append(contentsOf: result.attachments)
        }
        return (dataToProcess, attachments)
    }
    
    private func extract(_ tag: ATML.Attachment.Tag) -> Result {
        let tagName = tag.rawValue
        var attachments: [ATML.Attachment] = []
        let mString = NSMutableString(string: self)
        let results = tag.regex.matches(in: self, options: .reportCompletion, range: NSMakeRange(0, self.characters.count))
        let closingTag = "</\(tagName)>"
        var counter = 0
        let parser = ATML.ATMLXMLParser()
        for result in results.reversed() {
            counter += 1
            let identifier = "\(_defaultIdentifier)\(tagName)\(counter)"
            let matchedString = mString.substring(with: result.range)
            
            var xml = matchedString
            if matchedString.hasSuffix(closingTag) == false {
                xml = "\(matchedString)\(closingTag)"
            }
            parser.parse(xml)
            if let desc = parser.error?.localizedDescription { print("parsing error:\(desc)") }
            guard parser.sources.count != 0, var src = parser.sources.first else { continue }
            if parser.sources.count > 1 && (tag == .video || tag == .audio) {
                for str in parser.sources where MediaTypes.contains(str) {
                    src = str
                    break
                }
            }
            let textAttachment = ATML.Attachment(tag: tagName, id: identifier, src: src)
            textAttachment.attributes = parser.attributes
            textAttachment.html = matchedString
            
            var size = CGSize.zero
            if let width = parser.attributes["width"], width.contains("%") == false {
                size.width = CGFloat(Int(width) ?? 0)
            }
            if let height = parser.attributes["height"], height.contains("%") == false {
                size.height = CGFloat(Int(height) ?? 0)
            }
            textAttachment.size = size
            
            if let align = parser.attributes["align"]?.alignment { textAttachment.align = align }
            
            mString.replaceCharacters(in: result.range, with: textAttachment.identifier)
            attachments.append(textAttachment)
        }
        return (mString as String, attachments)
    }
    
    private var alignment: ATML.Alignment? {
        return ATML.Alignment(rawValue: lowercased())
    }
}


// MARK: -
extension ATML {
    
    // MARK: Alignment
    public enum Alignment: String { case none = "", left = "left", right = "right", center = "center" }
    // MARK: Attachment
    public final class Attachment: NSTextAttachment {
        
        public let identifier: String
        public let tagName: String
        public let src: String
        public var maxSize = CGSize.zero
        public var align = Alignment.none
        public var attributes: [String: String]?
        public var html: String?
        public var size = CGSize.zero
        
        fileprivate enum Keys: String {
            case identifier
            case tagName
            case src
            case maxSize
            case align
            case attributes
            case html
            case size
        }
        
        public enum Tag: String {
            case image = "img"
            case iframe = "iframe"
            case embed = "embed"
            case video = "video"
            case audio = "audio"
            
            private static let imgRegex = try! NSRegularExpression(pattern: "<img\\s+.*?(?:src\\s*=\\s*'|\".*?'|\").*?>", options: .caseInsensitive)
            private static let embedRegex = try! NSRegularExpression(pattern: "<embed\\s+.*?(?:src\\s*=\\s*'|\".*?'|\").*?>", options: .caseInsensitive)
            private static let iframeRegex = try! NSRegularExpression(pattern: "<iframe[^>]*?>.*?</iframe>", options: .caseInsensitive)
            private static let audioRegex = try! NSRegularExpression(pattern: "<audio[^>]*?>.*?</audio>", options: .caseInsensitive)
            private static let videoRegex = try! NSRegularExpression(pattern: "<video[^>]*?>.*?</video>", options: .caseInsensitive)
            
            var regex: NSRegularExpression {
                switch self {
                case .image: return Tag.imgRegex
                case .iframe: return Tag.iframeRegex
                case .embed: return Tag.embedRegex
                case .video: return Tag.videoRegex
                case .audio: return Tag.audioRegex
                }
            }
        }
        
        public init(tag: String, id: String, src s: String) {
            identifier = id
            tagName = tag
            src = s
            super.init(data: nil, ofType: nil)
        }
        
        public required init?(coder aDecoder: NSCoder) {
            guard let id = aDecoder.decodeObject(forKey: Keys.identifier.rawValue) as? String,
                let tag = aDecoder.decodeObject(forKey: Keys.tagName.rawValue) as? String,
                let srcRaw = aDecoder.decodeObject(forKey: Keys.src.rawValue) as? String
                else { return nil }
            identifier = id
            tagName = tag
            src = srcRaw
            maxSize = aDecoder.decodeCGSize(forKey: Keys.maxSize.rawValue)
            if let raw = aDecoder.decodeObject(forKey: Keys.align.rawValue) as? String, let value = Alignment(rawValue: raw) {
                align = value
            }
            attributes = aDecoder.decodeObject(forKey: Keys.attributes.rawValue) as? [String: String]
            html = aDecoder.decodeObject(forKey: Keys.html.rawValue) as? String
            size = aDecoder.decodeCGSize(forKey: Keys.size.rawValue)
            super.init(coder: aDecoder)
        }
        
        public override func encode(with aCoder: NSCoder) {
            super.encode(with: aCoder)
            aCoder.encode(identifier, forKey: Keys.identifier.rawValue)
            aCoder.encode(tagName, forKey: Keys.tagName.rawValue)
            aCoder.encode(src, forKey: Keys.src.rawValue)
            aCoder.encode(maxSize, forKey: Keys.maxSize.rawValue)
            aCoder.encode(align.rawValue, forKey: Keys.align.rawValue)
            
            aCoder.encode(attributes, forKey: Keys.attributes.rawValue)
            aCoder.encode(html, forKey: Keys.html.rawValue)
            aCoder.encode(size, forKey: Keys.size.rawValue)
        }
        
        public override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
            if textContainer == nil || align != .none {
                return super.attachmentBounds(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
            }
            guard let container = textContainer else {
                return super.attachmentBounds(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
            }
            let width = (lineFrag.width - position.x) - (container.lineFragmentPadding * 2)
            let rect = CGRect(x: 20, y: 0.0, width: floor(width), height: 1.0)
            return rect
        }
    }
    
    // MARK: AttachmentInfo
    internal final class AttachmentInfo {
        let id: String
        var view: UIView
        var exclusionPath: UIBezierPath?
        init(id: String, view: UIView, path: UIBezierPath? = nil) {
            self.view = view
            self.id = id
            exclusionPath = path
        }
    }
    
    // MARK: XMLParser
    fileprivate final class ATMLXMLParser: NSObject, XMLParserDelegate {
        let srcAttributeName = "src"
        let sourceElementName = "source"
        
        var tag: String?
        var attributes: [String: String] = [:]
        var sources: [String] = []
        var error: Error?
        private func reset() {
            tag = nil
            attributes = [:]
            sources = []
            error = nil
        }
        
        func parse(_ xml: String) {
            reset()
            guard let data = xml.data(using: .utf8) else {
                print("bad xml file:\(xml)")
                return
            }
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.parse()
            if let src = attributes[srcAttributeName] {
                sources.append(src)
            }
        }
        
        func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String]) {
            if tag == sourceElementName, let src = attributeDict[srcAttributeName] {
                attributes[srcAttributeName] = src
                return
            }
            tag = elementName
            attributes = attributeDict
        }
        
        func parser(_: XMLParser, parseErrorOccurred parseError: Error) {
            error = parseError
        }
    }
}
extension NSTextStorage { internal var wholeRange: NSRange { return NSMakeRange(0, length) } }
extension String {
    func nsRange(from range: Range<String.Index>) -> NSRange {
        let utf16view = self.utf16
        let from = String.UTF16View.Index(range.lowerBound, within: utf16view)
        let end = String.UTF16View.Index(range.upperBound, within: utf16view)
        let location = utf16view.distance(from: utf16view.startIndex, to: from)
        let length = utf16view.distance(from: from, to: end)
        return NSMakeRange(location, length)
    }
}

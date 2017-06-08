//
//  NSAttributedString+ATML.swift
//  ATML
//
//  Created by Lincoln Law on 2017/5/24.
//  Copyright © 2017年 Lincoln Law. All rights reserved.
//

import Foundation

private let _defaultIdentifier = "ATMLAttachmentDefaultIdentifier"
private let MediaTypes = "wav,aac,mp3,mov,mp4,m4v"

extension String {
    
    typealias Result = (processedString: String, attachments: [ATML.Attachment])
    
    internal func attributedString(withDocumentAttributes attrs: [String: Any]? = nil) -> NSAttributedString? {
        let parsed = parsing(tags: [.image, .embed, .iframe, .audio, .video, .blockquote, .strong, .em, .i])
        let parsedString = parsed.processedString
        let attachments = parsed.attachments
        
        guard let data = parsedString.data(using: String.Encoding.utf8) else { return nil }
        
        var options: [String: Any] = [
            NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
            NSCharacterEncodingDocumentAttribute: String.Encoding.utf8.rawValue,
            ]
        
        if let attr = attrs { options[NSDefaultAttributesDocumentAttribute] = attr }
        guard let attrString = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else { return nil }
        let parsedAttributedString = dealWithStrongAndItalic(with: attrString)
        for attachment in attachments {
            let raw = parsedAttributedString.string
            guard let r = raw.range(of: attachment.identifier) else { continue }
            let range = raw.nsRange(from: r)
            let attachmentString = NSAttributedString(attachment: attachment)
            parsedAttributedString.replaceCharacters(in: range, with: attachmentString)
        }
        return NSAttributedString(attributedString: parsedAttributedString)
    }
    
    
    private func dealStrong(with att: NSAttributedString) -> NSMutableAttributedString {
        let mAttr = NSMutableAttributedString(attributedString: att)
        let start = "ATMLStrong"
        let end = "ATMLStrongEnd"
        let result = ATML.Attachment.Tag.atmlStrong.regex.firstMatch(in: mAttr.string, options: [], range: NSMakeRange(0, mAttr.string.characters.count))
        if let re = result {
            let strongAtt = NSMutableAttributedString(attributedString: mAttr.attributedSubstring(from: re.range))
            let att = mAttr.attributes(at: 0, longestEffectiveRange: nil, in: re.range)
            guard let startRange = strongAtt.string.range(of: start) else { return mAttr }
            let rStart = strongAtt.string.nsRange(from: startRange)
            strongAtt.replaceCharacters(in: rStart, with: "")
            guard let endRange = strongAtt.string.range(of: end) else { return mAttr }
            let rEnd = strongAtt.string.nsRange(from: endRange)
            strongAtt.replaceCharacters(in: rEnd, with: "")
            let range = NSMakeRange(rStart.location, rEnd.location)
            if let font = att[NSFontAttributeName] as? UIFont  {
                let desc = font.fontDescriptor
                let existingTraitsWithNewTrait = desc.symbolicTraits.rawValue | UIFontDescriptorSymbolicTraits.traitBold.rawValue
                let exist = UIFontDescriptorSymbolicTraits(rawValue: existingTraitsWithNewTrait)
                if let d = desc.withSymbolicTraits(exist) {
                    let finalFont = UIFont(descriptor: d, size: font.pointSize)
                    strongAtt.addAttributes([NSFontAttributeName : finalFont], range: NSMakeRange(0, strongAtt.string.characters.count))
                }
            }
            let sub = strongAtt.attributedSubstring(from: range)
            let final = dealItalic(with: sub)
            strongAtt.replaceCharacters(in: range, with: final)
            mAttr.replaceCharacters(in: re.range, with: strongAtt)
            return dealStrong(with: mAttr)
        } else {
            return mAttr
        }
    }
    
    private func dealItalic(with att: NSAttributedString) -> NSMutableAttributedString {
        let mAttr = NSMutableAttributedString(attributedString: att)
        let start = "ATMLEM"
        let end = "ATMLEMEnd"
        let regex = ATML.Attachment.Tag.atmlEM.regex
        let result = regex.firstMatch(in: mAttr.string, options: [], range: NSMakeRange(0, mAttr.string.characters.count))
        if let re = result {
            let emAtt = NSMutableAttributedString(attributedString: mAttr.attributedSubstring(from: re.range))
            let att = mAttr.attributes(at: 0, longestEffectiveRange: nil, in: re.range)
            guard let startRange = emAtt.string.range(of: start) else { return mAttr }
            let rStart = emAtt.string.nsRange(from: startRange)
            emAtt.replaceCharacters(in: rStart, with: "")
            guard let endRange = emAtt.string.range(of: end) else { return mAttr }
            let rEnd = emAtt.string.nsRange(from: endRange)
            emAtt.replaceCharacters(in: rEnd, with: "")
            if let font = att[NSFontAttributeName] as? UIFont  {
                let matrix =  __CGAffineTransformMake(1, 0, CGFloat(tanf(Float(15 * Double.pi / 180))), 1, 0, 0);
                let desc = UIFontDescriptor(name: font.fontName, matrix: matrix)
                let finalFont = UIFont(descriptor: desc, size: font.pointSize)
                emAtt.addAttributes([NSFontAttributeName : finalFont], range: NSMakeRange(0, emAtt.string.characters.count))
            }
            mAttr.replaceCharacters(in: re.range, with: emAtt)
            return dealItalic(with: mAttr)
        } else {
            return mAttr
        }
    }
    private func dealWithStrongAndItalic(with att: NSAttributedString) -> NSMutableAttributedString {
        var mAttr = NSMutableAttributedString(attributedString: att)
        mAttr = dealStrong(with: mAttr)
        mAttr = dealItalic(with: mAttr)
        return mAttr
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
            if tag == .blockquote {
                let final = xml.replacingOccurrences(of: "<blockquote>\n", with: "<blockquote>\n<k style=\"color:#ccc; font-size: 2em; font-family: 'Copperplate'\">“</k>")
                mString.replaceCharacters(in: result.range, with: "\(final)<br/>")
                continue
            }
            if tag == .em || tag == .i {
                let textAttachment = ATML.Attachment(tag: tagName, id: identifier, src: "")
                textAttachment.attributes = parser.attributes
                textAttachment.html = matchedString
                let start = "ATMLEM"
                let end = "ATMLEMEnd"
                mString.replaceCharacters(in: result.range, with: "\(start)\(xml)\(end)")
                continue
            }
            if tag == .strong {
                let textAttachment = ATML.Attachment(tag: tagName, id: identifier, src: "")
                textAttachment.attributes = parser.attributes
                textAttachment.html = matchedString
                let start = "ATMLStrong"
                let end = "ATMLStrongEnd"
                mString.replaceCharacters(in: result.range, with: "\(start)\(xml)\(end)")
                continue
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
            textAttachment.link = parser.link
            
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
        public var link: String?
        
        fileprivate enum Keys: String {
            case identifier = "identifier"
            case tagName = "tagName"
            case src = "src"
            case maxSize = "maxSize"
            case align = "align"
            case attributes = "attributes"
            case html = "html"
            case size = "size"
            case link = "link"
        }
        
        public enum Tag: String {
            case image = "img"
            case iframe = "iframe"
            case embed = "embed"
            case video = "video"
            case audio = "audio"
            case blockquote = "blockquote"
            case em = "em"
            case i = "i"
            case strong = "strong"
            case atmlEM = "ATMLTagEm"
            case atmlStrong = "ATMLStrong"
            case link = "link"
            
            private static let imgRegex = try! NSRegularExpression(pattern: "<img\\s+.*?(?:src\\s*=\\s*'|\".*?'|\").*?>", options: .caseInsensitive)
            private static let linkRegex = try! NSRegularExpression(pattern: "<a\\s+.*?(?:href\\s*=\\s*'|\".*?'|\").*?>([\\s\\S]+?)</a>", options: .caseInsensitive)
            private static let embedRegex = try! NSRegularExpression(pattern: "<embed\\s+.*?(?:src\\s*=\\s*'|\".*?'|\").*?>", options: .caseInsensitive)
            private static let iframeRegex = try! NSRegularExpression(pattern: "<iframe[^>]*?>.*?</iframe>", options: .caseInsensitive)
            private static let audioRegex = try! NSRegularExpression(pattern: "<audio[^>]*?>.*?</audio>", options: .caseInsensitive)
            private static let videoRegex = try! NSRegularExpression(pattern: "<video[^>]*?>.*?</video>", options: .caseInsensitive)
            private static let blockquoteRegex = try! NSRegularExpression(pattern: "(?:<blockquote[^>]*?>)([\\s\\S]+?)(?:<\\/blockquote>)", options: .caseInsensitive)
            private static let emRegex = try! NSRegularExpression(pattern: "<em[^>]*?>.*?</em>", options: .caseInsensitive)
            private static let iRegex = try! NSRegularExpression(pattern: "<i[^>]*?>.*?</i>", options: .caseInsensitive)
            private static let strongRegex = try! NSRegularExpression(pattern: "(?:<strong[^>]*?>)([\\s\\S]+?)(?:<\\/strong>)", options: .caseInsensitive)
            
            private static let attEmRegex = try! NSRegularExpression(pattern: "ATMLEM(.*?)ATMLEMEnd", options: .caseInsensitive)
            private static let attStrongRegex = try! NSRegularExpression(pattern: "(?:ATMLStrong)(.*?)(?:ATMLStrongEnd)", options: .caseInsensitive)
            
            var regex: NSRegularExpression {
                switch self {
                case .image: return Tag.imgRegex
                case .iframe: return Tag.iframeRegex
                case .embed: return Tag.embedRegex
                case .video: return Tag.videoRegex
                case .audio: return Tag.audioRegex
                case .blockquote: return Tag.blockquoteRegex
                case .em: return Tag.emRegex
                case .i: return Tag.iRegex
                case .strong: return Tag.strongRegex
                case .atmlEM: return Tag.attEmRegex
                case .atmlStrong: return Tag.attStrongRegex
                case .link: return Tag.linkRegex
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
            link = aDecoder.decodeObject(forKey: Keys.link.rawValue) as? String
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
            aCoder.encode(link, forKey: Keys.link.rawValue)
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
    final class ATMLXMLParser: NSObject, XMLParserDelegate {
        let srcAttributeName = "src"
        let sourceElementName = "source"
        let linkElementName = "link"
        let hrefElementName = "href"
        
        var tag: String?
        var attributes: [String: String] = [:]
        var sources: [String] = []
        var error: Error?
        var link: String?
        var href: String?
        var tagAttributes: [String : [String : String]] = [:]
        private func reset() {
            tag = nil
            attributes = [:]
            sources = []
            error = nil
            link = nil
            href = nil
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
            tagAttributes[elementName] = attributeDict
            attributes = attributeDict
            link = attributeDict[linkElementName]
            href = attributeDict[hrefElementName]
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

//
//  ViewController.swift
//  Demo
//
//  Created by Lincoln Law on 2017/6/2.
//  Copyright © 2017年 Lincoln Law. All rights reserved.
//

import UIKit
import ATML
class ViewController: UIViewController, UITextViewDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        let path = Bundle.main.url(forResource: "File", withExtension: nil)!
        let content = try! String(contentsOf: path)
        let font = ATML.FontInfo(fontFamily: "PingFangSC-Light", fontSize: 14, fontColor: "#4d4d4d")
        let prefix = "<div style=\"font-family: \(font.fontFamily); font-size: \(font.fontSize)px; color:\(font.fontColor)\"><style> \n a { text-decoration:none; }</style><div></div>"
        let subfix = "</div>"
        let final = "\(prefix)\(content)\(subfix)"
        textView.display(html: final, font: font)
        textView.delegate = self
        textView.isEditable = false
        textView.textContainerInset = UIEdgeInsetsMake(0, 10, 0, 10)
        // Do any additional setup after loading the view, typically from a nib.
    }
    @IBOutlet weak var textView: UITextView!

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        print("wanna open \(URL)")
        return false
    }
}


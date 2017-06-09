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
        let font = UIFont.systemFont(ofSize: 14)
        let prefix = "<div style=\"font-family: PingFangSC-Light; font-size: \(font.pointSize)px; color:#4d4d4d\">"
        let subfix = "</div>"
        let final = "\(prefix)\(content)\(subfix)"
        textView.display(html: final)
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


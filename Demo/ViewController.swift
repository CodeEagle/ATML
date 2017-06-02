//
//  ViewController.swift
//  Demo
//
//  Created by Lincoln Law on 2017/6/2.
//  Copyright © 2017年 Lincoln Law. All rights reserved.
//

import UIKit
import ATML
class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        let path = Bundle.main.url(forResource: "File", withExtension: nil)!
        let content = try! String(contentsOf: path)
        textView.display(html: content)
        // Do any additional setup after loading the view, typically from a nib.
    }
    @IBOutlet weak var textView: UITextView!

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}


//
//  ViewController.swift
//  Demo
//
//  Created by LawLincoln on 16/6/2.
//  Copyright © 2016年 SelfStudio. All rights reserved.
//

import UIKit
import KVOBlock

class ViewController: UIViewController {

	override func viewDidLoad() {
		super.viewDidLoad()
		view.observeKeyPath("frame") { (target, old, new) in

		}
		// Do any additional setup after loading the view, typically from a nib.
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

}


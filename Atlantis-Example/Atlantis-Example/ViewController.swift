//
//  ViewController.swift
//  Atlantis-Example
//
//  Created by Nghia Tran on 10/22/20.
//  Copyright © 2020 Nghia Tran. All rights reserved.
//

import UIKit


class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        makeSimpleRequest()
    }

    func makeSimpleRequest() {
        let url = URL(string: "https://httpbin.org/get?name=proxyman&id=\(UUID().uuidString)&randon=\(Int.random(in: 0..<10000))")!
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            if let error = error {
                print(error)
                return
            }

            if let response = response as? HTTPURLResponse {
                print(response)

                if let data = data {
                    print("------ Body")
                    let dict = try! JSONSerialization.jsonObject(with: data, options: [])
                    print(dict)
                }
            }
        }
        task.resume()
    }

    @IBAction func sendMessageBtnOnTap(_ sender: Any) {
        makeSimpleRequest()
    }
}


//
//  ViewController.swift
//  Atlantis-Example-App
//
//  Created by Nghia Tran on 23/10/2021.
//

import UIKit
import Alamofire

final class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    // MARK: - IBActions

    @IBAction func getBtnOnTap(_ sender: Any) {
        let url = URL(string: "https://httpbin.org/get")!
        let query: [String: String] = ["name": "Proxyman",
                                       "id": "123"]
        let header: [String: String] = ["X-Proxyman-Data": "123",
                                        "X-Data": "JSON"]
        AF.request(url, method: HTTPMethod.get, parameters: query, headers: HTTPHeaders(header)).responseJSON { response in
            print(response)
        }
    }

    @IBAction func postJsonBtnOnTap(_ sender: Any) {
    }

    @IBAction func postUrlEncodedBtnOnTap(_ sender: Any) {
    }
    @IBAction func uploadMultipartFormBtnOnClick(_ sender: Any) {
    }

    @IBAction func deleteBtnOnTap(_ sender: Any) {
    }
}

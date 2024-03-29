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
        let url = URL(string: "https://httpbin.proxyman.app/get")!
        let query: [String: String] = ["name": "Proxyman",
                                       "id": "123"]
        let header: [String: String] = ["X-Proxyman-Data": "123",
                                        "X-Data": "JSON"]
        AF.request(url, method: HTTPMethod.get, parameters: query, headers: HTTPHeaders(header)).responseJSON { response in
            print(response)
        }
    }

    @IBAction func postJsonBtnOnTap(_ sender: Any) {
        let url = URL(string: "https://httpbin.proxyman.app/post")!
        let body: [String: String] = ["name": "Proxyman",
                                       "id": "123"]
        let header: [String: String] = ["X-Proxyman-Data": "123",
                                        "X-Data": "JSON"]
        AF.request(url, method: HTTPMethod.post, parameters: body, encoder: JSONParameterEncoder(), headers: HTTPHeaders(header)).responseJSON { response in
            print(response)
        }
    }

    @IBAction func postUrlEncodedBtnOnTap(_ sender: Any) {
        let url = URL(string: "https://httpbin.proxyman.app/post")!
        let body: [String: String] = ["name": "Proxyman",
                                       "id": "123"]
        let header: [String: String] = ["X-Proxyman-Data": "123",
                                        "X-Data": "JSON"]
        AF.request(url, method: HTTPMethod.post, parameters: body, encoder: URLEncodedFormParameterEncoder(), headers: HTTPHeaders(header)).responseJSON { response in
            print(response)
        }
    }

    @IBAction func uploadMultipartFormBtnOnClick(_ sender: Any) {
        let imageURL = Bundle.main.url(forResource: "image", withExtension: "jpg")!
        let url = URL(string: "https://httpbin.proxyman.app/post")!
        let data = MultipartFormData()
        data.append("Hello Word".data(using: .utf8)!, withName: "text")
        data.append(imageURL, withName: "image", fileName: "bigsur", mimeType: "jpg")
        AF.upload(multipartFormData: data, to: url).responseJSON { response in
            print(response)
        }
    }

    @IBAction func deleteBtnOnTap(_ sender: Any) {
        let url = URL(string: "https://httpbin.proxyman.app/delete")!
        let body: [String: String] = ["name": "Proxyman",
                                       "id": "123"]
        let header: [String: String] = ["X-Proxyman-Data": "123",
                                        "X-Data": "JSON"]
        AF.request(url, method: HTTPMethod.delete, parameters: body, encoder: JSONParameterEncoder(), headers: HTTPHeaders(header)).responseJSON { response in
            print(response)
        }
    }

    @IBAction func uploadTaskBtnOnTap(_ sender: Any) {
        let imageURL = Bundle.main.url(forResource: "image", withExtension: "jpg")!
        let imageData = try! Data(contentsOf: imageURL)
        let url = URL(string: "https://httpbin.proxyman.app/post")!
        var request = URLRequest(url: url)
        request.method = .post

        let task = URLSession.shared.uploadTask(with: request, from: imageData) { _, response, _ in
            guard let response = response else {
                return
            }
            print(response)
        }
        task.resume()
    }

    @IBAction func cameraBtnOnTap(_ sender: Any) {
        let controller = UIImagePickerController()
        controller.sourceType = UIImagePickerController.SourceType.camera
        show(controller, sender: self)
    }

    @IBAction func uploadBtnOnTap(_ sender: Any) {
        var request = URLRequest(url: URL(string: "https://httpbin.proxyman.app/put")!)
        request.method = .put
        let data = "123 Hello World".data(using: .utf8)!

        let task = URLSession.shared.uploadTask(with: request, from: data) { data, _, error in
            if let error = error {
                print(error)
                return
            }
            print("Upload success!")
        }
        task.resume()
    }
}

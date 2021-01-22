//
//  MasterViewController.swift
//
//  Copyright (c) 2014-2018 Alamofire Software Foundation (http://alamofire.org/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Alamofire
import UIKit
import Atlantis

class MasterViewController: UITableViewController {
    // MARK: - Properties

    @IBOutlet var titleImageView: UIImageView!

    var detailViewController: DetailViewController?

    private var reachability: NetworkReachabilityManager!

    private lazy var session: Session = {
        let config = URLSessionConfiguration.ephemeral
        return Session(configuration: config)
    }()

    // MARK: - View Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()

        navigationItem.titleView = titleImageView
        clearsSelectionOnViewWillAppear = true

        reachability = NetworkReachabilityManager.default
        monitorReachability()
    }

    // MARK: - UIStoryboardSegue

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if
            let navigationController = segue.destination as? UINavigationController,
            let detailViewController = navigationController.topViewController as? DetailViewController {
            func requestForSegue(_ segue: UIStoryboardSegue) -> Alamofire.Request? {
                switch segue.identifier! {
                case "GET":
                    detailViewController.segueIdentifier = "GET"
                    return session.request("https://httpbin.org/get")
                case "POST":
                    detailViewController.segueIdentifier = "POST"
                    let message = """
                    {
                      "args": {},
                      "data": "data:application/octet-stream;base64,CMYNEhdSZWFsbHkgSW50ZXJlc3RpbmcgQm9vaxoKSmFuZSBTbWl0aA==",
                      "files": {},
                      "form": {},
                      "headers": {
                        "Accept": "*/*",
                        "Content-Length": "40",
                        "Content-Type": "application/protobuf-x",
                        "Host": "httpbin.org",
                        "User-Agent": "insomnia/2020.4.2",
                        "X-Amzn-Trace-Id": "Root=1-5fc1fdfb-156285fd0bd7d8161e3fabe5"
                      },
                      "json": null,
                      "origin": "116.102.129.87",
                      "url": "https://httpbin.org/post"
                    }
                    """
                    let parameters: [String: String] = ["name": "Nghia",
                                               "text": message]
                    return AF.request("https://httpbin.org/post", method: .post, parameters: parameters, encoder: JSONParameterEncoder.default)

                case "PUT":
                    detailViewController.segueIdentifier = "PUT"
                    return AF.request("https://httpbin.org/put", method: .put)
                case "DELETE":
                    detailViewController.segueIdentifier = "DELETE"
                    return AF.request("https://httpbin.org/delete", method: .delete)
                case "DOWNLOAD":
                    detailViewController.segueIdentifier = "DOWNLOAD"
                    let destination = DownloadRequest.suggestedDownloadDestination(for: .cachesDirectory,
                                                                                   in: .userDomainMask)
                    return AF.download("https://httpbin.org/stream/1", to: destination)
                default:
                    return nil
                }
            }

            if let request = requestForSegue(segue) {
                detailViewController.request = request
            }
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 3 && indexPath.row == 0 {
            print("Reachability Status: \(reachability.status)")
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }

    // MARK: - Private - Reachability

    private func monitorReachability() {
        reachability.startListening { status in
            print("Reachability Status Changed: \(status)")
        }
    }

    @IBAction func getManualBtnOnClick(_ sender: Any) {
        let header = Header(key: "X-Data", value: "Nghia")
        let jsonType = Header(key: "Content-Type", value: "application/json")
        let jsonObj: [String: Any] = ["key": "nghia", "country": "Singapore"]
        let data = try! JSONSerialization.data(withJSONObject: jsonObj, options: [])
        let request = Request(url: "https://proxyman.io/get/data", method: "GET", headers: [header, jsonType], body: data)
        let response = Response(statusCode: 200, headers: [Header(key: "X-Response", value: "Internal Error server"), jsonType])

        let responseObj: [String: Any] = ["error_response": "Not FOund"]
        let responseData = try! JSONSerialization.data(withJSONObject: responseObj, options: [])
        Atlantis.add(request: request, response: response, responseBody: responseData)
    }
    
    @IBAction func addGRPCBtnOnTap(_ sender: Any) {
        Atlantis.addGRPC(url: "https://proxyman.io/grpc/data",
                         requestObject: Person(name: "Nghia", job: "IT"),
                         responseObject: ResponseMessage(message: "OK", house: House(name: "Home", address: "Q7")),
                         success: true,
                         statusCode: 1,
                         statusMessage: "OK")
    }

    @IBAction func downloadTaskBtnOnTap(_ sender: Any) {
        let url = URL(string: "https://proxyman.io/img/background/proxyman-dashboard-home.png")!
        let task = URLSession.shared.downloadTask(with: url) { (_, response, error) in
            if let error = error {
                print(error)
                return
            }
            if let response = response as? HTTPURLResponse {
                print(response)
            }
        }
        task.resume()
    }

    @IBAction func downloadFileBtnOnClick(_ sender: Any) {
        if let url = Bundle.main.url(forResource: "Info", withExtension: "plist") {
          let task = URLSession.shared.downloadTask(with: url)
          task.resume()
        }
    }

    @IBAction func downloadLocalImageOnTap(_ sender: Any) {
        if let url = Bundle.main.url(forResource: "image", withExtension: "png") {
          let task = URLSession.shared.downloadTask(with: url)
          task.resume()
        }
    }

    @IBAction func uploadVideoBtnOnTap(_ sender: Any) {
        let fileURL = Bundle.main.url(forResource: "small_image", withExtension: "png")!
        AF.upload(fileURL, to: "https://httpbin.org/post").response { (data) in
            print("-- Upload done!")
            print("Data Response count = \(data.data?.count ?? 0)")
        }
        AF.upload(try! Data(contentsOf: fileURL), with: URLRequest(url: URL(string: "https://httpbin.org/post")!)).responseData { (response) in
            print(response)
        }
    }

    @IBAction func uploadFileWithComplete(_ sender: Any) {
        print("uploadFileWithComplete")
        let fileURL = Bundle.main.url(forResource: "small_image", withExtension: "png")!
        let request = try! URLRequest(url: "https://httpbin.org/post", method: .post)
        let task = URLSession.shared.uploadTask(with: request, fromFile: fileURL) { (_, response, _) in
            print(response as Any)
        }
        task.resume()
    }

    @IBAction func uploadFile(_ sender: Any) {
        print("uploadFile")
        let fileURL = Bundle.main.url(forResource: "small_image", withExtension: "png")!
        let request = try! URLRequest(url: "https://httpbin.org/post", method: .post)
        let task = URLSession.shared.uploadTask(with: request, fromFile: fileURL)
        task.resume()
    }

    @IBAction func uploadVideoFromDataComplete(_ sender: Any) {
        print("uploadVideoFromDataComplete")
        let fileURL = Bundle.main.url(forResource: "small_image", withExtension: "png")!
        let data = try! Data(contentsOf: fileURL)
        let request = try! URLRequest(url: "https://httpbin.org/post", method: .post)
        let task = URLSession.shared.uploadTask(with: request, from: data) { (_, response, _) in
            print(response as Any)
        }
        task.resume()
    }

    @IBAction func uploadVideoFromData(_ sender: Any) {
        print("uploadVideoFromData")
        let fileURL = Bundle.main.url(forResource: "small_image", withExtension: "png")!
        let data = try! Data(contentsOf: fileURL)
        let request = try! URLRequest(url: "https://httpbin.org/post", method: .post)
        let task = URLSession.shared.uploadTask(with: request, from: data)
        task.resume()
    }

    @IBAction func afUploadMultiplePartOnTap(_ sender: Any) {
        AF.upload(multipartFormData: { multipartFormData in
            multipartFormData.append(Data("one".utf8), withName: "one")
            multipartFormData.append(Data("two".utf8), withName: "two")
        }, to: "https://httpbin.org/post")
        .responseData { (response) in
            print(response)
        }
    }
}

struct Person: Codable {

    let name: String
    let job: String
}

struct House: Codable {
    let name: String
    let address: String
}

struct ResponseMessage: Codable {

    let message: String
    let house: House?
}

//
//  AutofillEmailUserScriptTests.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
import WebKit
@testable import BrowserServicesKit

class AutofillEmailUserScriptTests: XCTestCase {

    let userScript = AutofillUserScript(encrypter: MockEncrypter())
    let userContentController = WKUserContentController()

    var encryptedMessagingParams: [String: Any] {
        return [
            "messageHandling": [
                "iv": Array(repeating: UInt8(1), count: 32),
                "key": Array(repeating: UInt8(1), count: 32),
                "secret": userScript.generatedSecret,
                "methodName": "test-methodName"
            ]
        ]
    }

    func testWhenReplyIsReturnedFromMessageHandlerThenIsEncrypted() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "emailHandlerGetAddresses", body: encryptedMessagingParams, webView: mockWebView)
        userScript.userContentController(userContentController, didReceive: message)

        let expectedReply = "reply".data(using: .utf8)?.withUnsafeBytes {
            $0.map { String($0) }
        }.joined(separator: ",")

        XCTAssertEqual(mockWebView.javaScriptString?.contains(expectedReply!), true)
    }

    func testWhenRunningOnModernWebkit_ThenInjectsAPIFlag() {
        if #available(iOS 14, macOS 11, *) {
            XCTAssertTrue(AutofillUserScript().source.contains("hasModernWebkitAPI = true"))
        } else {
            XCTFail("Expected to run on at least iOS 14 or macOS 11")
        }
    }

    func testWhenReceivesStoreTokenMessageThenCallsDelegateMethodWithCorrectTokenAndUsername() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock
        
        let token = "testToken"
        let username = "testUsername"
                
        let expect = expectation(description: "testWhenReceivesStoreTokenMessageThenCallsDelegateMethod")
        mock.requestStoreTokenCallback = { callbackToken, callbackUsername in
            XCTAssertEqual(token, callbackToken)
            XCTAssertEqual(username, callbackUsername)
            expect.fulfill()
        }

        var body = encryptedMessagingParams
        body["token"] = "testToken"
        body["username"] = "testUsername"
        let message = MockWKScriptMessage(name: "emailHandlerStoreToken", body: body)
        userScript.userContentController(userContentController, didReceive: message)

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testWhenReceivesCheckSignedInMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let expect = expectation(description: "testWhenReceivesCheckSignedInMessageThenCallsDelegateMethod")
        mock.signedInCallback = {
            expect.fulfill()
        }

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "emailHandlerCheckAppSignedInStatus", body: encryptedMessagingParams, webView: mockWebView)
        userScript.userContentController(userContentController, didReceive: message)

        XCTAssertEqual(mockWebView.javaScriptString?.contains("window.test-methodName("), true)

        waitForExpectations(timeout: 1.0, handler: nil)
    }
   
    func testWhenReceivesGetAliasMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock
        
        let expect = expectation(description: "testWhenReceivesGetAliasMessageThenCallsDelegateMethod")
        mock.requestAliasCallback = {
            expect.fulfill()
        }

        var body = encryptedMessagingParams
        body["requiresUserPermission"] = false
        body["shouldConsumeAliasIfProvided"] = false
        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "emailHandlerGetAlias", body: body, webView: mockWebView)
        userScript.userContentController(userContentController, didReceive: message)

        waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertNotNil(mockWebView.javaScriptString)
    }
    
    func testWhenReceivesRefreshAliasMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock
        
        let expect = expectation(description: "testWhenReceivesRefreshAliasMessageThenCallsDelegateMethod")
        mock.refreshAliasCallback = {
            expect.fulfill()
        }

        let message = MockWKScriptMessage(name: "emailHandlerRefreshAlias", body: encryptedMessagingParams)
        userScript.userContentController(userContentController, didReceive: message)

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testWhenReceivesEmailGetAddressesMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let expect = expectation(description: "testWhenReceivesRequestUsernameAndAliasMessageThenCallsDelegateMethod")
        mock.requestUsernameAndAliasCallback = {
            expect.fulfill()
        }

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "emailHandlerGetAddresses", body: encryptedMessagingParams, webView: mockWebView)
        userScript.userContentController(userContentController, didReceive: message)

        waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertNotNil(mockWebView.javaScriptString)
    }

    func testWhenUnknownMessageReceivedThenNoProblem() {
        let message = MockWKScriptMessage(name: "unknownmessage", body: "")
        userScript.userContentController(userContentController, didReceive: message)
    }

}

class MockWKScriptMessage: WKScriptMessage {
    
    let mockedName: String
    let mockedBody: Any
    let mockedWebView: WKWebView?
    
    override var name: String {
        return mockedName
    }
    
    override var body: Any {
        return mockedBody
    }

    override var webView: WKWebView? {
        return mockedWebView
    }
    
    init(name: String, body: Any, webView: WKWebView? = nil) {
        self.mockedName = name
        self.mockedBody = body
        self.mockedWebView = webView
        super.init()
    }
}

class MockAutofillEmailDelegate: AutofillEmailDelegate {

    var signedInCallback: (() -> Void)?
    var requestAliasCallback: (() -> Void)?
    var requestStoreTokenCallback: ((String, String) -> Void)?
    var refreshAliasCallback: (() -> Void)?
    var requestUsernameAndAliasCallback: (() -> Void)?

    func autofillUserScriptDidRequestSignedInStatus(_: AutofillUserScript) -> Bool {
        signedInCallback?()
        return false
    }
    
    func autofillUserScript(_: AutofillUserScript,
                            didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                            shouldConsumeAliasIfProvided: Bool,
                            completionHandler: @escaping AliasCompletion) {
        requestAliasCallback?()
        completionHandler("alias", nil)
    }
    
    func autofillUserScriptDidRequestRefreshAlias(_ : AutofillUserScript) {
        refreshAliasCallback?()
    }
    
    func autofillUserScript(_ : AutofillUserScript, didRequestStoreToken token: String, username: String) {
        requestStoreTokenCallback!(token, username)
    }

    func autofillUserScriptDidRequestUsernameAndAlias(_: AutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion) {
        requestUsernameAndAliasCallback?()
        completionHandler("username", "alias", nil)
    }

}

class MockWebView: WKWebView {

    var javaScriptString: String?

    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        self.javaScriptString = javaScriptString
    }

}

struct MockEncrypter: AutofillEncrypter {

    var authenticationData: Data = Data()

    func encryptReply(_ reply: String, key: [UInt8], iv: [UInt8]) throws -> (ciphertext: Data, tag: Data) {
        return ("reply".data(using: .utf8)!, Data())
    }

}
//
//  ALCenter.swift
//  Center
//
//  Created by CavanSu on 2020/2/11.
//  Copyright © 2020 CavanSu. All rights reserved.
//

import UIKit
import RxSwift
import RxRelay
import AlamoClient

class ALCenter: NSObject {
    static let instance = ALCenter()
    static func shared() -> ALCenter {
        return instance
    }
    
    var isWorkNormally = BehaviorRelay(value: false)
    
    // Abstractions
    private var files = FilesGroup()
    
    private(set) var current: CurrentUser?
    
    lazy var appAssistant = AppAssistant()
    var liveSession: LiveSession?
    
    // Commons
    private let log = LogTube()
    private lazy var mediaKit = MediaKit(log: log)
    
    private lazy var alamo = AlamoClient(delegate: nil,
                                         logTube: self)
    
    private lazy var rtm = RTMClient(logTube: log)
    private lazy var userDataHelper = UserDataHelper()
}

extension ALCenter {
    func registerAndLogin() {
        if let current = CurrentUser.local() {
            self.current = current
            self.login(userId: current.info.userId) {
                self.isWorkNormally.accept(true)
            }
            return
        }
        
        register { [unowned self] (info: BasicUserInfo) in
            self.login(userId: info.userId) { [unowned self] in
                self.current = CurrentUser(info: info)
                self.isWorkNormally.accept(true)
            }
        }
    }
    
    func reinitAgoraServe() {
        mediaKit.reinitRTC()
        rtm = RTMClient(logTube: log)
    }
}

private extension ALCenter {
    func register(success: ((BasicUserInfo) -> Void)?) {
        let url = URLGroup.userRegister
        let event = RequestEvent(name: "user-register")
        let name = "Uknow"
        let parameters = ["userName": name]
        let task = RequestTask(event: event,
                               type: .http(.post, url: url),
                               timeout: .low,
                               parameters: parameters)
        
        let successCallback: DicEXCompletion = { (json: ([String: Any])) throws in
            let object = try json.getDataObject()
            let userId = try object.getStringValue(of: "userId")
            let info = BasicUserInfo(userId: userId,
                                     name: name,
                                     headURL: "local")
            
            if let success = success {
                success(info)
            }
        }
        let response = ACResponse.json(successCallback)
        
        let retry: ACErrorRetryCompletion = { (error: Error) -> RetryOptions in
            return .retry(after: 1)
        }
        
        alamo.request(task: task, success: response, failRetry: retry)
    }
    
    func login(userId: String, success: Completion) {
        let url = URLGroup.userLogin
        let event = RequestEvent(name: "user-login")
        let task = RequestTask(event: event,
                               type: .http(.post, url: url),
                               timeout: .low,
                               parameters: ["userId": userId])
        
        let successCallback: DicEXCompletion = { (json: ([String: Any])) throws in
            let object = try json.getDataObject()
            let userToken = try object.getStringValue(of: "userToken")
            let rtmToken = try object.getStringValue(of: "rtmToken")
            let uid = try object.getIntValue(of: "uid")
            ALKeys.ALUserToken = userToken
            ALKeys.AgoraRtmToken = rtmToken
            
            // RTM Login
            try? self.rtm.connect(rtmId: "\(uid)", token: rtmToken, success: {
                if let success = success {
                    success()
                }
            }) { (error) -> RetryOptions in
                return .retry(after: 0.5)
            }
        }
        let response = ACResponse.json(successCallback)
        
        let retry: ACErrorRetryCompletion = { (error: Error) -> RetryOptions in
            return .retry(after: 1)
        }
        
        alamo.request(task: task, success: response, failRetry: retry)
    }
}

extension ALCenter: CenterHelper {
    func centerProvideRequestHelper() -> AlamoClient {
        return alamo
    }
    
    func centerProvideImagesHelper() -> ImageFiles {
        return files.images
    }
    
    func centerProvideMediaHelper() -> MediaKit {
        return mediaKit
    }
    
    func centerProvideFilesGroup() -> FilesGroup {
        return self.files
    }
    
    func centerProvideRTMHelper() -> RTMClient {
        return self.rtm
    }
    
    func centerProvideLogTubeHelper() -> LogTube {
        return self.log
    }
    
    func centerProvideUserDataHelper() -> UserDataHelper {
        return userDataHelper
    }
}

extension ALCenter: ACLogTube {
    func log(from: AnyClass, info: String, extral: String?, funcName: String) {
        let fromatter = AGELogFormatter(type: .info(info),
                                        className: NSStringFromClass(from),
                                        funcName: funcName,
                                        extra: extral)
        log.logFromClass(formatter: fromatter)
    }
    
    func log(from: AnyClass, warning: String, extral: String?, funcName: String) {
        let fromatter = AGELogFormatter(type: .warning(warning),
                                        className: NSStringFromClass(from),
                                        funcName: funcName,
                                        extra: extral)
        log.logFromClass(formatter: fromatter)
    }
    
    func log(from: AnyClass, error: Error, extral: String?, funcName: String) {
        let fromatter = AGELogFormatter(type: .error(error.localizedDescription),
                                        className: NSStringFromClass(from),
                                        funcName: funcName,
                                        extra: extral)
        log.logFromClass(formatter: fromatter)
    }
}

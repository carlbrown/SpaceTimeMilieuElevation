import Foundation
import SpaceTimeMilieuModel
import Kitura
import Dispatch
import LoggerAPI
import HeliumLogger
import SwiftyJSON

private let Default_APIKey="Get one from https://algorithmia.com"

#if os(Linux)
    import Glibc
#endif

let ourLogger = HeliumLogger(.info)
ourLogger.dateFormat = "YYYY/MM/dd-HH:mm:ss.SSS"
ourLogger.format = "(%type): (%date) - (%msg)"
ourLogger.details = false
Log.logger = ourLogger

let myCertPath = "./cert.pem"
let myKeyPath = "./key.pem"
let myChainPath = "./chain.pem"

guard let remoteURL = URL(string: "https://api.algorithmia.com/v1/algo/Gaploid/Elevation/0.3.6") else {
    fatalError("Failed to create URL from hardcoded string")
}

//Enable Core Dumps on Linux
#if os(Linux)
    
let unlimited = rlimit.init(rlim_cur: rlim_t(INT32_MAX), rlim_max: rlim_t(INT32_MAX))
    
let corelimit = UnsafeMutablePointer<rlimit>.allocate(capacity: 1)
corelimit.initialize(to: unlimited)
    
let coreType = Int32(RLIMIT_CORE.rawValue)
    
let status = setrlimit(coreType, corelimit)
if (status != 0) {
    print("\(errno)")
}
    
corelimit.deallocate(capacity: 1)
#endif

let mySSLConfig =  SSLConfig(withCACertificateFilePath: myChainPath, usingCertificateFile: myCertPath, withKeyFile: myKeyPath, usingSelfSignedCerts: false)

let APIKey: String
let rawAPIKey = getenv("APIKEY")
if let key = rawAPIKey, let keyString = String(utf8String: key) {
    APIKey = keyString
} else {
    APIKey = Default_APIKey
}

let router = Router()

//Log page responses
router.all { (request, response, next) in
    var previousOnEndInvoked: LifecycleHandler? = nil
    let onEndInvoked: LifecycleHandler = { [weak response, weak request] in
        Log.info("\(response?.statusCode.rawValue ?? 0) \(request?.originalURL ?? "unknown")")
        previousOnEndInvoked?()
    }
    previousOnEndInvoked = response.setOnEndInvoked(onEndInvoked    )
    next()
}

router.all(middleware: BodyParser())

router.post("/api") { request, response, next in
    
    guard let body = request.body  else {
        Log.error("Could not find request body! Giving up!")
        response.headers["Content-Type"] = "text/plain; charset=utf-8"
        try? response.status(.preconditionFailed).send("Could not find request body! Giving up!").end()
        return
    }
    
    switch body {
        case .json(let jsonObj):
            let model: Point
            do {
                let bodyData = try jsonObj.rawData()
                guard let bodyPoint = Point(fromJSON:bodyData) else {
                    Log.error("Could not get Point from Body JSON! Giving up!")
                    response.headers["Content-Type"] = "text/plain; charset=utf-8"
                    try response.status(.preconditionFailed).send("Could not get Point from Body JSON! Giving up!").end()
                    return
                }
                model = bodyPoint
            } catch {
                Log.error("Could not get Point from Body JSON \(error)! Giving up!")
                response.headers["Content-Type"] = "text/plain; charset=utf-8"
                try? response.status(.preconditionFailed).send("Could not get Point from Body JSON \(error)! Giving up!").end()
                return
            }
            
            var request = URLRequest(url: remoteURL)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Simple \(APIKey)", forHTTPHeaderField: "Authorization")
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: ["lat":"\(model.latitudeDegrees)","lon":"\(model.longitudeDegrees)"])
            } catch {
                Log.error("Could not create remote JSON Payload \(error)! Giving up!")
                response.headers["Content-Type"] = "text/plain; charset=utf-8"
                try? response.status(.preconditionFailed).send("Could not create remote JSON Payload \(error)! Giving up!").end()
                return
            }

            let session = URLSession(configuration:URLSessionConfiguration.default)
            
            let task = session.dataTask(with: request){ fetchData,fetchResponse,fetchError in
                guard fetchError == nil else {
                    Log.error(fetchError?.localizedDescription ?? "Error with no description")
                    response.headers["Content-Type"] = "text/plain; charset=utf-8"
                    try? response.status(.preconditionFailed).send(fetchError?.localizedDescription ?? "Error with no description").end()
                    return
                }
                guard let fetchData = fetchData else {
                    Log.error("Nil fetched data with no error")
                    response.headers["Content-Type"] = "text/plain; charset=utf-8"
                    try? response.status(.preconditionFailed).send("Nil fetched data with no error").end()
                    return
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: fetchData, options: .mutableContainers)
                    
                    if let debug = getenv("DEBUG") { //debug
                        //OK to crash if debugging turned on
                        let jsonForPrinting = try! JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
                        let jsonToPrint = String(data: jsonForPrinting, encoding: .utf8)
                        print("result: \(jsonToPrint!)")
                    }
                    
                    if let parseJSON = json as? [String: Any],
                        let resultString:String = parseJSON["result"] as? String,
                        let resultData = resultString.data(using: .utf8),
                        let resultJSON = try? JSONSerialization.jsonObject(with:resultData) {
                        
                        if let resultValue:[String:String] = resultJSON as? [String:String] {
                            if let elevValue:String = resultValue["elev"] {
                                print("elevation: \(elevValue)")
                                response.headers["Content-Type"] = "application/json; charset=utf-8"
                                let resultToResend = try JSONSerialization.data(withJSONObject: resultValue)
                                response.status(.OK).send(data:resultToResend)
                                next()
                            }
                        }
                    } else {
                        Log.error("Could not parse JSON payload as Dictionary")
                        response.headers["Content-Type"] = "text/plain; charset=utf-8"
                        try response.status(.preconditionFailed).send("Could not parse JSON payload as Dictionary").end()
                        return
                    }
                } catch {
                    Log.error("Could not parse remote JSON Payload \(error)! Giving up!")
                    response.headers["Content-Type"] = "text/plain; charset=utf-8"
                    try? response.status(.preconditionFailed).send("Could not parse remote JSON Payload \(error)! Giving up!").end()
                }
            }
            task.resume()
    default:
        Log.error("Missing body")
        try? response.status(.preconditionFailed).send("Could not parse JSON request body! Giving up!").end()
        return

    }
    
}

// Handles any errors that get set
router.error { request, response, next in
    response.headers["Content-Type"] = "text/plain; charset=utf-8"
    let errorDescription: String
    if let error = response.error {
        errorDescription = "\(error)"
    } else {
        errorDescription = "Unknown error"
    }
    response.headers["Content-Type"] = "text/plain; charset=utf-8"
    try response.send("Caught the error: \(errorDescription)").end()
}

//MARK: /ping
router.get("/ping") { request, response, next in
    //Health check
    response.headers["Content-Type"] = "text/plain; charset=utf-8"
    try response.send("OK").end()
}

Kitura.addHTTPServer(onPort: 8090, with: router, withSSL: mySSLConfig)
Kitura.run()

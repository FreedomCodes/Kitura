import XCTest
import Dispatch
@testable import SwiftServerHttp
@testable import K2Spike

class ParameterParsingTests: XCTestCase {
    static var allTests = [
        ("testBodylessParameterParsing", testBodylessParameterParsing),
        ("testWithBodyParameterParsing", testWithBodyParameterParsing)
    ]

    func testBodylessParameterParsing() {
        let request = HTTPRequest(method: .GET, target: "/world?hello=world", httpVersion: (1, 1), headers: HTTPHeaders([("hello", "world")]))
        let resolver = TestResponseResolver(request: request, requestBody: Data())
        var router = Router()
        router.add(verb: .GET, path: "/{hello}", parameterType: NoBodyParameters.self, responseCreator: NoBodyResponse())
        let coordinator = RequestHandlingCoordinator(router: router)

        _ = coordinator.handle(req: request, res: resolver)
    }

    func testWithBodyParameterParsing() {
        let request = HTTPRequest(method: .GET, target: "/world?hello=world", httpVersion: (1, 1), headers: HTTPHeaders([("hello", "world")]))
        let resolver = TestResponseResolver(request: request, requestBody: Data())
        var router = Router()
        router.add(verb: .GET, path: "/{hello}", parameterType: WithBodyParameters.self, responseCreator: WithBodyResponse())
        let coordinator = RequestHandlingCoordinator(router: router)

        // Mock body processing
        switch coordinator.handle(req: request, res: resolver) {
        case .processBody(let handler):
            var stop = false
            let body = "hello=world"

            // Use Swift's implicit String -> UnsafePointer<UInt8> conversion to generate
            // UnsafeBufferPointer<UInt8>
            let bufferedPointer = UnsafeBufferPointer<UInt8>(start: body, count: body.lengthOfBytes(using: .utf8))
            let dispatchData = DispatchData(bytes: bufferedPointer)

            handler(.chunk(data: dispatchData, finishedProcessing: {}), &stop)
            handler(.end, &stop)
        default:
            XCTFail("Body not processed")
        }
    }
}

struct NoBodyParameters: BodylessParameterContaining {
    let headerParam: [String]
    let pathParam: String
    let queryParam: [URLQueryItem]

    init?(pathParameters: [String : String]?, queryParameters: [URLQueryItem]?, headers: HTTPHeaders) {
        guard let pathParam = pathParameters?["hello"],
            let queryParam = queryParameters?.filter({ $0.name == "hello" }) else {
            return nil
        }

        self.pathParam = pathParam
        self.headerParam = headers["hello"]
        self.queryParam = queryParam
    }
}

struct NoBodyResponse: BodylessParameterResponseCreating {
    func serve(request: HTTPRequest, context: RequestContext, parameters: BodylessParameterContaining, response: HTTPResponseWriter) -> HTTPBodyProcessing {
        guard let parameters = parameters as? NoBodyParameters else {
            XCTFail("Wrong parameter type")
            return .discardBody
        }

        XCTAssert(parameters.headerParam.count == 1)
        XCTAssert(parameters.headerParam[0] == "world")
        XCTAssert(parameters.pathParam == "world")
        XCTAssert(parameters.queryParam.count == 1)
        XCTAssert(parameters.queryParam[0].value == "world")

        return .discardBody
    }
}

struct WithBodyParameters: ParameterContaining {
    let headerParam: [String]
    let pathParam: String
    let queryParam: [URLQueryItem]
    let body: String

    init?(pathParameters: [String : String]?, queryParameters: [URLQueryItem]?, headers: HTTPHeaders, body: DispatchData) {
        guard let pathParam = pathParameters?["hello"],
            let queryParam = queryParameters?.filter({ $0.name == "hello" }),
            let body = String(data: Data(body), encoding: .utf8) else {
                return nil
        }

        self.pathParam = pathParam
        self.headerParam = headers["hello"]
        self.queryParam = queryParam
        self.body = body
    }
}

struct Response: ResponseObject {
    let body: String

    func toData() -> Data? {
        return body.data(using: .utf8)
    }
}

struct WithBodyResponse: ParameterResponseCreating {
    func serve(request: HTTPRequest, context: RequestContext, parameters: ParameterContaining, response: HTTPResponseWriter) -> (response: HTTPResponse, responseBody: ResponseObject) {
        guard let parameters = parameters as? WithBodyParameters else {
            XCTFail("Wrong parameter type")

            let httpResponse = HTTPResponse(httpVersion: request.httpVersion,
                                        status: .badRequest,
                                        transferEncoding: .chunked,
                                        headers: HTTPHeaders())

            return (response: httpResponse, responseBody: Response(body: "Error"))
        }

        XCTAssert(parameters.headerParam.count == 1)
        XCTAssert(parameters.headerParam[0] == "world")
        XCTAssert(parameters.pathParam == "world")
        XCTAssert(parameters.queryParam.count == 1)
        XCTAssert(parameters.queryParam[0].value == "world")
        XCTAssert(parameters.body == "hello=world")

        let httpResponse = HTTPResponse(httpVersion: request.httpVersion,
                                    status: .ok,
                                    transferEncoding: .chunked,
                                    headers: HTTPHeaders())
        return (response: httpResponse, responseBody: Response(body: "Pass"))
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2014 Thomas Visser
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import XCTest

class BrightFuturesTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testCompletedFuture() {
        let f = Future<Int>.succeeded(2)
        
        let completeExpectation = self.expectationWithDescription("immediate complete")
        
        f.onComplete { result in
            XCTAssert(!result.error)
            completeExpectation.fulfill()
        }
        
        let successExpectation = self.expectationWithDescription("immediate success")
        
        f.onSuccess { value in
            XCTAssert(value != nil)
            XCTAssert(value == 2, "Computation should be returned")
            successExpectation.fulfill()
        }
        
        f.onFailure { _ in
            XCTFail("failure block should not get called")
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testFailedFuture() {
        let error = NSError(domain: "test", code: 0, userInfo: nil)
        let f = Future<Bool>.failed(error)
        
        let completeExpectation = self.expectationWithDescription("immediate complete")
        
        f.onComplete { result in
            XCTAssert(!result.value)
            XCTAssert(result.error == error)
            completeExpectation.fulfill()
        }
        
        let failureExpectation = self.expectationWithDescription("immediate failure")
        
        f.onFailure { err in
            XCTAssert(err == error)
            failureExpectation.fulfill()
        }
        
        f.onSuccess { value in
            XCTFail("success should not be called")
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testControlFlowSyntax() {
        
        let f = future { _ in
            fibonacci(10)
        }
        
        let e = self.expectationWithDescription("the computation succeeds")
        
        f.onSuccess { value in
            XCTAssert(value == 55)
            e.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(10, handler: nil)
    }
    
    func testControlFlowSyntaxWithError() {
        
        let f : Future<String?> = future { error in
            error = NSError(domain: "NaN", code: 0, userInfo: nil)
            return nil
        }
        
        let failureExpectation = self.expectationWithDescription("failure expected")
        
        f.onFailure { error in
            XCTAssert(error.domain == "NaN")
            failureExpectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(3, handler: nil)
    }
    
    func testAutoClosure() {
        let names = ["Steve", "Tim"]
        
        let f = future(names.count)
        let e = self.expectationWithDescription("")
        
        f.onSuccess { value in
            XCTAssert(value == 2)
            e.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
        
        let e1 = self.expectationWithDescription("-")
        future(fibonacci(10)).onSuccess { value in
            XCTAssert(value == 55);
            e1.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testPromise() {
        let p = Promise<Int>()
        
        Queue.global.async {
            p.success(fibonacci(10))
        }
        
        let e = self.expectationWithDescription("complete expectation")
        
        p.future.onComplete { result in
            XCTAssert(result.value == 55)
            e.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testCustomExecutionContext() {
        let f = future(context: ImmediateExecutionContext()) { _ in
            fibonacci(10)
        }
        
        let e = self.expectationWithDescription("immediate success expectation")
        
        f.onSuccess(context: ImmediateExecutionContext()) { value in
            e.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0, handler: nil)
    }
    
    func testMainExecutionContext() {
        let e = self.expectationWithDescription("")
        
        future { _ -> Int in
            XCTAssert(!NSThread.isMainThread())
            return 1
        }.onSuccess(context: QueueExecutionContext.main) { value in
            XCTAssert(NSThread.isMainThread())
            e.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testMapSuccess() {
        let e = self.expectationWithDescription("")
        
        future { _ in
            fibonacci(10)
        }.map { value -> String in
            if value > 5 {
                return "large"
            }
            return "small"
        }.map { sizeString -> Bool in
            return sizeString == "large"
        }.onSuccess { numberIsLarge in
            XCTAssert(numberIsLarge)
            e.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testMapFailure() {
        
        let e = self.expectationWithDescription("")
        
        future { (inout error:NSError?) -> Int? in
            error = NSError(domain: "Tests", code: 123, userInfo: nil)
            return nil
        }.map { number in
            XCTAssert(false, "map should not be evaluated because of failure above")
        }.map { number in
            XCTAssert(false, "this map should also not be evaluated because of failure above")
        }.onFailure { error in
            XCTAssert(error.domain == "Tests")
            e.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testAndThen() {
        
        var answer = 10
        
        let e = self.expectationWithDescription("")
        
        let f = future(4)
        let f1 = f.andThen { result in
            answer *= result.value!
        }
        
        let f2 = f1.andThen { result in
            answer += 2
            e.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
        
        XCTAssertEqual(42, answer, "andThens should be executed in order")
        XCTAssertEqual(f.value!, f1.value!, "future value should be passed transparantly")
        XCTAssertEqual(f1.value!, f2.value!, "future value should be passed transparantly")
    }
    
    func testTransparentOnFailure() {
        let e = self.expectationWithDescription("")
        
        future { (inout error:NSError?) -> Int in
            return 3
        }.recover { _ in
            return 5
        }.onSuccess { value in
            XCTAssert(value == 3)
            e.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testDefaultOnFailure() {
        let e = self.expectationWithDescription("")
        
        future { (inout error:NSError?) -> Int? in
            error = NSError(domain: "NaN", code: 0, userInfo: nil)
            return nil
        }.recoverWith { _ in
            return future { _ in
                fibonacci(5)
            }
        }.onSuccess { value in
            XCTAssert(value == 5)
            e.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }

}

func fibonacci(n: Int) -> Int {
    switch n {
    case 0...1:
        return n
    default:
        return fibonacci(n - 1) + fibonacci(n - 2)
    }
}

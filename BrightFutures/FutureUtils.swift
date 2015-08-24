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

import Foundation
import Result

extension SequenceType {
    /// Turns a sequence of T's into an array of `Future<U>`'s by calling the given closure for each element in the sequence.
    /// If no context is provided, the given closure is executed on `Queue.global`
    public func traverse<U, E>(context: ExecutionContext = Queue.global.context, f: Generator.Element -> Future<U, E>) -> Future<[U], E> {
        return map(f).fold(context, zero: [U]()) { (list: [U], elem: U) -> [U] in
            return list + [elem]
        }
    }
}

extension SequenceType where Generator.Element: AsyncType {
    /// Returns a future that returns with the first future from the given sequence that completes
    /// (regardless of whether that future succeeds or fails)
    public func firstCompleted() -> Generator.Element {
        
        return Generator.Element { complete in
            for fut in self {
                fut.onComplete(Queue.global.context) { res in
                    do {
                        try complete(res)
                    } catch { }
                }
            }
        }
    }
}

extension SequenceType where Generator.Element: AsyncType, Generator.Element.Value: ResultType {
    
    //// The free functions in this file operate on sequences of Futures
    
    /// Performs the fold operation over a sequence of futures. The folding is performed
    /// on `Queue.global`.
    /// (The Swift compiler does not allow a context parameter with a default value
    /// so we define some functions twice)
    public func fold<R>(zero: R, f: (R, Generator.Element.Value.Value) -> R) -> Future<R, Generator.Element.Value.Error> {
        return fold(Queue.global.context, zero: zero, f: f)
    }
    
    /// Performs the fold operation over a sequence of futures. The folding is performed
    /// in the given context.
    public func fold<R>(context: ExecutionContext, zero: R, f: (R, Generator.Element.Value.Value) -> R) -> Future<R, Generator.Element.Value.Error> {
        return reduce(Future<R, Generator.Element.Value.Error>(value: zero)) { zero, elem in
            return zero.flatMap { zeroVal in
                elem.map(context) { elemVal in
                    return f(zeroVal, elemVal)
                }
            }
        }
    }
    
    /// Turns a sequence of `Future<T>`'s into a future with an array of T's (Future<[T]>)
    /// If one of the futures in the given sequence fails, the returned future will fail
    /// with the error of the first future that comes first in the list.
    public func sequence() -> Future<[Generator.Element.Value.Value], Generator.Element.Value.Error> {
        return traverse {
            // this is not nice at all, but I've been unable to solve it in a better way without crashing the compiler
            return $0 as! Future<Generator.Element.Value.Value, Generator.Element.Value.Error>
        }
    }

    /// See `find<S: SequenceType, T where S.Generator.Element == Future<T>>(seq: S, context c: ExecutionContext, p: T -> Bool) -> Future<T>`
    public func find(p: Generator.Element.Value.Value -> Bool) -> Future<Generator.Element.Value.Value, BrightFuturesError<Generator.Element.Value.Error>> {
        return find(Queue.global.context, p: p)
    }

    /// Returns a future that succeeds with the value from the first future in the given
    /// sequence that passes the test `p`.
    /// If any of the futures in the given sequence fail, the returned future fails with the
    /// error of the first failed future in the sequence.
    /// If no futures in the sequence pass the test, a future with an error with NoSuchElement is returned.
    public func find(context: ExecutionContext, p: Generator.Element.Value.Value -> Bool) -> Future<Generator.Element.Value.Value, BrightFuturesError<Generator.Element.Value.Error>> {
        return sequence().mapError { error in
            return BrightFuturesError(external: error)
        }.flatMap(context) { val -> Result<Generator.Element.Value.Value, BrightFuturesError<Generator.Element.Value.Error>> in
            for elem in val {
                if (p(elem)) {
                    return Result(value: elem)
                }
            }
            return Result(error: .NoSuchElement)
        }
    }
}

/// Enables the chaining of two failable operations where the second operation is asynchronous and
/// represented by a future. 
/// Like map, the given closure (that performs the second operation) is only executed
/// if the first operation result is a .Success
/// If a regular `map` was used, the result would be `Result<Future<U>>`.
/// The implementation of this function uses `map`, but then flattens the result before returning it.
public func flatMap<T,U, E>(result: Result<T,E>, @noescape f: T -> Future<U, E>) -> Future<U, E> {
    return flatten(result.map(f))
}

/// Returns a .Failure with the error from the outer or inner result if either of the two failed
/// or a .Success with the success value from the inner Result
public func flatten<T, E>(result: Result<Result<T,E>,E>) -> Result<T,E> {
    return result.analysis(ifSuccess: { $0 }, ifFailure: { Result(error: $0) })
}

/// Returns the inner future if the outer result succeeded or a failed future
/// with the error from the outer result otherwise
public func flatten<T, E>(result: Result<Future<T, E>,E>) -> Future<T, E> {
    return result.analysis(ifSuccess: { $0 }, ifFailure: { Future(error: $0) })
}

/// Turns a sequence of `Result<T>`'s into a Result with an array of T's (`Result<[T]>`)
/// If one of the results in the given sequence is a .Failure, the returned result is a .Failure with the
/// error from the first failed result from the sequence.
public func sequence<S: SequenceType, T, E where S.Generator.Element == Result<T, E>>(seq: S) -> Result<[T], E> {
    return seq.reduce(Result(value: [])) { (res, elem) -> Result<[T], E> in
        switch res {
        case .Success(let resultSequence):
            switch elem {
            case .Success(let elemValue):
                let newSeq = resultSequence + [elemValue]
                return Result<[T], E>(value: newSeq)
            case .Failure(let elemError):
                return Result<[T], E>(error: elemError)
            }
        case .Failure(_):
            return res
        }
    }
}

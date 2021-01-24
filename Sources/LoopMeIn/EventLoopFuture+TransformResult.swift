import AsyncKit

public extension EventLoopFuture {
  func mapAlways<NewValue>(
    file: StaticString = #file, line: UInt = #line,
    _ callback: @escaping (Result<Value, Error>) -> Result<NewValue, Error>
  ) -> EventLoopFuture<NewValue> {
    let promise = self.eventLoop.makePromise(of: NewValue.self, file: file, line: line)
    self.whenComplete { result in promise.completeWith(callback(result)) }
    return promise.futureResult
  }
}

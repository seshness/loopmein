import Fluent
import FluentSQLiteDriver
import NIO
import Foundation
import Vapor

let logger = Logger(label: "LoopMeIn.application")

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let threadPool = NIOThreadPool.init(numberOfThreads: System.coreCount)
threadPool.start()
let dbs = Databases(threadPool: threadPool, on: eventLoopGroup)
dbs.use(.sqlite(.file("loopmein.db")), as: .sqlite)
defer {
  dbs.shutdown()
  try! threadPool.syncShutdownGracefully()
  try! eventLoopGroup.syncShutdownGracefully()
}

let migrations = Migrations()
migrations.add(CreateChannelListeners())
migrations.add(CreateChannels())
let migrator = Migrator(
  databases: dbs,
  migrations: migrations,
  logger: logger,
  on: eventLoopGroup.next())

try migrator.setupIfNeeded().wait()
try migrator.prepareBatch().wait()

let db = dbs.database(logger: logger, on: eventLoopGroup.next())!
let channelListeners = try ChannelListener.query(on: db).all().wait()
for channelListener in channelListeners {
  print("\(channelListener.slackUser) -> \(channelListener.regex)")
}

guard let slackAppToken = ProcessInfo.processInfo.environment["SLACK_APP_TOKEN"] else {
  logger.critical("No API token found! Define an environment variable SLACK_APP_TOKEN.")
  exit(1)
}
var appAuthHeaders = HTTPHeaders()
appAuthHeaders.bearerAuthorization = .init(token: slackAppToken)

guard let slackBotToken = ProcessInfo.processInfo.environment["SLACK_BOT_TOKEN"] else {
  logger.critical("No API token found! Define an environment variable SLACK_BOT_TOKEN.")
  exit(1)
}
var botAuthHeaders = HTTPHeaders()
botAuthHeaders.bearerAuthorization = .init(token: slackBotToken)
botAuthHeaders.contentType = .json

let client = HTTPClient.init(eventLoopGroupProvider: .shared(eventLoopGroup))
//var request = try HTTPClient.Request(url: "https://slack.com/api/conversations.list", method: .GET)
var request = try HTTPClient.Request(url: "https://slack.com/api/apps.connections.open", method: .POST)
request.headers = appAuthHeaders

func getData(_ response: HTTPClient.Response) -> Data {
  response.body?.getData(at: 0, length: response.body?.readableBytes ?? 0) ?? Data()
}

public enum SlackAppError : Error, LocalizedError {
  case networkError(_ message: String)
  case unexpectedHTTPResponseError(code: UInt)
  case notJson
  case slackError(_ message: String)

  public var errorDescription: String? {
    switch self {
    case let .networkError(message):
      return message
    case let .slackError(message):
      return message
    case .notJson:
      return "Not JSON!"
    case let .unexpectedHTTPResponseError(code):
      return "Unexpeected HTTP response: \(code)"
    }
  }
}

let mainEventLoop = eventLoopGroup.next()
var eventLoopQueue = EventLoopFutureQueue(eventLoop: mainEventLoop)

func runLoop(eventLoop: EventLoop) -> EventLoopFuture<Void> {
  let websocketUrlFuture = getWebsocketUrl()
  return websocketUrlFuture.flatMapAlways { result in
    if case let .failure(error) = result {
      logger.critical("\(error.localizedDescription)")
      // Wait 10s before trying again
      DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        let _ = eventLoopQueue.append(runLoop(eventLoop: eventLoop))
      }
      return eventLoop.future(error: error)
    }
    let websocketUrl = try! result.get()
    
    logger.info("Received websocket URL: \(websocketUrl)")

    let websocketFuture = makeWebsocketConnection(websocketUrl: websocketUrl)
    let _ = websocketFuture.whenComplete { (result: Result<Void, Error>) in
      let _ = eventLoopQueue.append(runLoop(eventLoop: eventLoop))
    }
    return websocketFuture
  }
}
let _ = eventLoopQueue.append(runLoop(eventLoop: mainEventLoop))

updateChannelsPeriodically()

RunLoop.current.run()

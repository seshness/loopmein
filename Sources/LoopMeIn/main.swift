import Fluent
import FluentSQLiteDriver
import NIO
import Foundation
import AsyncHTTPClient
import Vapor

print("Hello, world!")

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

func getWebsocketUrl() -> EventLoopFuture<String> {
  let execution = client.execute(request: request, logger: logger)
  return execution.mapAlways { openSocketResult in
    switch openSocketResult {
    case .failure(let error):
      return .failure(SlackAppError.networkError(error.localizedDescription))
    case .success(let response):
      if response.status != .ok {
        return .failure(SlackAppError.unexpectedHTTPResponseError(code: response.status.code))
      }
      guard let connectionOpenResponse = try? JSONDecoder().decode(SlackAppsConnectionsOpenResponse.self, from: getData(response)) else {
        return .failure(SlackAppError.notJson)
      }

      if !connectionOpenResponse.ok {
        return .failure(SlackAppError.slackError(connectionOpenResponse.error ?? "\"ok\": false, but no error provided"))
      }

      guard let url = connectionOpenResponse.url else {
        return .failure(SlackAppError.slackError("no url provided!"))
      }
      return .success(url)
    }
  }
}

var websocketUrl: String = ""
do {
  websocketUrl = try getWebsocketUrl().wait()
} catch {
  logger.critical("\(error.localizedDescription)")
}

print(websocketUrl)

let websocketClient = WebSocketClient.init(eventLoopGroupProvider: .shared(eventLoopGroup))
guard let url = URL(string: websocketUrl) else {
  logger.critical("invalid url: \(websocketUrl)")
  exit(1)
}

// TODO: make this a pool of websocket connections
func makeWebsocketConnection() -> EventLoopFuture<Void> {
  let websocketConnect = websocketClient.connect(scheme: url.scheme ?? "wss", host: url.host!, port: 443 /*url.port ?? 443*/, path: "\(url.path)/?\(url.query!)") { webSocket in
    
    let slackEventsHandler = SlackEventsHandler(acknowledger: { acknowledgement in
      webSocket.send(
        String(data: acknowledgement, encoding: .utf8)!)
      }, logger: logger)

    webSocket.onText { _, event in
      slackEventsHandler.handleEvent(eventAsText: event)
    }
    
    webSocket.onClose.whenComplete { _ in
      // Reconnect when closed
      logger.info("Websocket connection closed, creating a new one.")
      let _ = makeWebsocketConnection()
    }
  }
  return websocketConnect
}

let _ = makeWebsocketConnection()
updateChannelsPeriodically()

RunLoop.current.run()

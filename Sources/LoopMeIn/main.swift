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

let client = HTTPClient.init(eventLoopGroupProvider: .shared(eventLoopGroup))
var request = try HTTPClient.Request(url: "https://slack.com/api/conversations.list", method: .GET)
guard let slackApiToken = ProcessInfo.processInfo.environment["SLACK_BOT_TOKEN"] else {
  logger.critical("No API token found! Define an environment variable SLACK_BOT_TOKEN.")
  exit(1)
}
request.headers.bearerAuthorization = .init(token: slackApiToken)
//HTTPClient.Request(url: "https://slack.com/api/apps.connections.open")
let execution = client.execute(request: request, logger: logger)
execution.whenComplete { result in
  switch result {
  case .failure(let error):
    logger.error("\(error.localizedDescription)")
  case .success(let response):
    if response.status != .ok {
      logger.warning("bad response: \(response.status.code) \(response.status.reasonPhrase)")
    }
    //let clientResponse = ClientResponse(status: response.status, headers: response.headers, body: response.body)
    let jsonObject = try! JSONSerialization.jsonObject(with: response.body?.getData(at: 0, length: response.body?.readableBytes ?? 0) ?? Data(), options: [])
    if let root = jsonObject as? [String: Any] {
      if let channels = root["channels"] as? [Any] {
        for channelObjectRaw in channels {
          if let channelObject = channelObjectRaw as? [String: Any] {
            if let channelName = channelObject["name"] as? String {
              print(channelName)
            }
          }
        }
      }
    }
  }
}

try execution.wait()

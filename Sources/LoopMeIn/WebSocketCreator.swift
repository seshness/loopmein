import Foundation
import AsyncKit
import AsyncHTTPClient
import WebSocketKit

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

// TODO: make this a pool of websocket connections
func makeWebsocketConnection(websocketUrl: String) -> EventLoopFuture<Void> {
  let websocketClient = WebSocketClient.init(eventLoopGroupProvider: .shared(eventLoopGroup))
  guard let url = URL(string: websocketUrl) else {
    logger.critical("invalid url: \(websocketUrl)")
    exit(1)
  }

  let eventLoop = eventLoopGroup.next()
  let websocketDone = eventLoop.makePromise(of: Void.self)

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
      logger.info("Websocket connection \(websocketUrl) closed.")
      websocketDone.succeed(Void())
    }
  }
  websocketConnect.cascadeFailure(to: websocketDone)
  return websocketDone.futureResult
}

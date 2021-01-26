import AsyncHTTPClient
import NIO
import Foundation
import FluentKit

func fetchConversationsList(cursor maybeCursor: String? = nil) -> EventLoopFuture<[Channel]> {
  var url = "https://slack.com/api/conversations.list?limit=1000&exclude_archived=true&types=public_channel"
  if let cursor = maybeCursor {
    url.append("&cursor=\(cursor)")
  }
  let requestResult = Result { try HTTPClient.Request(url: url, method: .GET, headers: botAuthHeaders) }
  if case let .failure(error) = requestResult {
    return eventLoopGroup.next().makeFailedFuture(error)
  }
  let request = try! requestResult.get()
  return client.execute(request: request, logger: logger)
    .flatMap { resp in
      let responseResult = Result { try JSONDecoder().decode(ConversationsListResponse.self, from: getData(resp)) }
      if case let .failure(error) = responseResult {
        logger.warning("Couldn't decode conversations.list response: \(String(data: getData(resp), encoding: .utf8) ?? "<couldn't read response>")")
        return eventLoopGroup.next().makeFailedFuture(error)
      }
      let response = try! responseResult.get()
      if !response.ok || response.channels == nil {
        return eventLoopGroup.next().makeFailedFuture(SlackAppError.slackError(response.error ?? "<no error provided>"))
      }
      if response.ok && (response.response_metadata?.next_cursor == nil || (response.response_metadata?.next_cursor?.isEmpty)!) {
        return eventLoopGroup.next().makeSucceededFuture(response.channels!)
      }
      guard let channels = response.channels else {
        return eventLoopGroup.next().makeFailedFuture(SlackAppError.slackError("no channels provided"))
      }
      return fetchConversationsList(cursor: response.response_metadata!.next_cursor!).map { nextChannels -> [Channel] in
        return channels + nextChannels
      }
    }
}

func addChannelsToDb(
  channels: ArraySlice<Channel>,
  db: FluentKit.Database,
  overallResult: EventLoopPromise<Void>,
  eventLoop: EventLoop
) {
  if channels.endIndex - channels.startIndex == 0 {
    return overallResult.succeed(())
  }
  let endIndex = min(channels.endIndex, channels.startIndex + 100)
  let channelsToAdd = channels[(channels.startIndex)..<(endIndex)]
  let remainingChannels = endIndex == channels.endIndex ? [] : channels[(endIndex)...]
  channelsToAdd.create(on: db).map { _ in
    addChannelsToDb(channels: remainingChannels, db: db, overallResult: overallResult, eventLoop: eventLoop)
  }.whenFailure { error in
    overallResult.fail(error)
  }
}

func updateChannelsPeriodically() {
  let eventLoop = eventLoopGroup.next()
  eventLoop.scheduleRepeatedTask(initialDelay: .zero, delay: .minutes(30)) { repeatedTask in
    let _ = fetchConversationsList().flatMap { channels -> EventLoopFuture<Void> in
      return db.transaction { conn -> EventLoopFuture<Void> in
        let promise = eventLoop.makePromise(of: Void.self)
        addChannelsToDb(channels: channels[...], db: conn, overallResult: promise, eventLoop: eventLoop)
        return promise.futureResult.map {
          logger.info("Updated channels list with \(channels.count) channels.")
          return
        }
      }
    }.whenFailure { error in
      logger.error("Error updating channels: \(error)")
    }
  }
}

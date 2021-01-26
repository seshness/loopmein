import Foundation
import Logging
import AsyncKit
import AsyncHTTPClient
import Regex
import Fluent

class SlackEventsHandler {
  let acknowledger: (Data) -> Void
  let logger: Logger
  
  init(acknowledger: @escaping (Data) -> Void, logger: Logger) {
    self.acknowledger = acknowledger
    self.logger = logger
  }

  @discardableResult func makeSlackApiPostRequest<Contentable>(
    url: String, for content: Contentable) -> EventLoopFuture<HTTPClient.Response>
  where Contentable: Encodable {
    let request = try! HTTPClient.Request(
      url: url,
      method: .POST,
      headers: botAuthHeaders,
      body: HTTPClient.Body.data(try! JSONEncoder().encode(content)))
    return makeSlackApiRequest(request)
  }

  @discardableResult func makeSlackApiRequest(_ request: HTTPClient.Request) -> EventLoopFuture<HTTPClient.Response> {
    let execution = client.execute(request: request, logger: logger)
    execution.whenFailure { error in
      self.logger.error("Failed to make network request to \(request.method.string) \(request.url): \(error.localizedDescription)")
    }
    execution.whenSuccess { response in
      guard response.status == .ok else {
        self.logger.error("Unexpected response from Slack API: \(response.status). Response data: \(String(data: getData(response), encoding: .utf8) ?? "<could not parse response data>")")
        return
      }
      self.logger.debug("Successful response from \(request.method.string) \(request.url)")
    }
    return execution
  }

  func getListeners(userId: String) -> EventLoopFuture<[ChannelListener]> {
    return ChannelListener.query(on: db).filter(\.$slackUser == userId).all()
  }
  
  @discardableResult func publishHomeView(userId: String) -> EventLoopFuture<HTTPClient.Response> {
    let fetchAllChannels = Channel.query(on: db).all()
    return getListeners(userId: userId)
      .and(fetchAllChannels)
      .flatMap { (channelListeners, allChannels) -> EventLoopFuture<HTTPClient.Response> in
        let homeView = ViewsPublish(user_id: userId, view: makeAppHome(channelListeners, channels: allChannels))
        let publishAppHomeRequest = try! HTTPClient.Request(
          url: "https://slack.com/api/views.publish",
          method: .POST,
          headers: botAuthHeaders,
          body: HTTPClient.Body.data(try! JSONEncoder().encode(homeView)))
        return self.makeSlackApiRequest(publishAppHomeRequest)
    }
  }

  func handleEvent(eventAsText: String) {
    guard let eventAsData = eventAsText.data(using: .utf8) else {
      return
    }
    let slackEventResult = Result { try JSONDecoder().decode(SlackEvent.self, from: eventAsData) }
    if case let .failure(error) = slackEventResult {
      logger.warning("Bad response parsing: \(error)")
      return
    }
    let slackEvent = try! slackEventResult.get()

    var acknowledgementPayload: Dictionary<String, Any>? = nil

    if slackEvent.type == "events_api" && slackEvent.payload?.type == "event_callback" && slackEvent.payload?.event?.type == "app_home_opened" {
      publishHomeView(userId: slackEvent.payload!.event!.user!)
    }
    
    if slackEvent.type == "interactive" && slackEvent.payload?.type == "block_actions" && !(slackEvent.payload?.actions?.isEmpty ?? true) {
      for action in slackEvent.payload!.actions! {
        if action.action_id == "new-regex-view" {
          guard let triggerId = slackEvent.payload?.trigger_id else {
            logger.warning("No trigger_id on Slack event: \(eventAsText)")
            return
          }
          // show modal
          let modalView = ViewsOpen(trigger_id: triggerId, view: makeNewRegexModal())
          let openViewRequest = try! HTTPClient.Request(
            url: "https://slack.com/api/views.open",
            method: .POST,
            headers: botAuthHeaders,
            body: HTTPClient.Body.data(try! JSONEncoder().encode(modalView))
          )
          makeSlackApiRequest(openViewRequest)
        }
      }
    }
    
    if slackEvent.type == "interactive" && slackEvent.payload?.type == "view_submission" && slackEvent.payload?.view?.callback_id == "new-regex-modal" {
      guard let state = slackEvent.payload?.view?.state else {
        logger.warning("Expected state, didn't get it")
        return
      }
      guard let regex = state.values["new-regex-input-block"]?["new-regex-input"]?["value"] else {
        logger.warning("Expected regex in state values, didn't get it")
        return
      }
      let regexTestResult = Result { try Regex(string: regex) }
      if case let .failure(error) = regexTestResult {
        acknowledgementPayload = [
          "response_action": "errors",
          "errors": [
            "new-regex-input-block": "This regex seems faulty: \(error)"
          ]
        ]
      } else {
        if let userId = slackEvent.payload?.user?.id {
          let newListener = ChannelListener(id: UUID(), slackUser: userId, regex: regex)
          newListener.create(on: db).whenSuccess {
            self.publishHomeView(userId: userId)
          }
        }
      }
    }

    if slackEvent.type == "events_api" && slackEvent.payload?.type == "event_callback" && slackEvent.payload?.event?.type == "channel_created", let channel = slackEvent.payload?.event?.channel {
      channel.save(on: db).whenSuccess({ return })
      let fetchListeners = ChannelListener.query(on: db).all()
      fetchListeners.whenFailure({ error in
        self.logger.warning("Error fetching channel listeners, giving up on updates for new channel \(channel.name). Error: \(error)")
      })
      fetchListeners.whenSuccess { channelListeners in
        let activatedListeners = channelListeners.filter { channelListener -> Bool in
          guard let r = try? Regex(string: channelListener.regex, options: .ignoreCase) else {
            return false
          }
          return r.matches(channel.name)
        }
        let usersToInvite = Array(Set(activatedListeners.map({ listener in listener.slackUser })))

        if usersToInvite.isEmpty {
          return
        }

        let conversationsJoin = ConversationsJoin(channel: channel.id!)
        let _ = self.makeSlackApiPostRequest(
          url: "https://slack.com/api/conversations.join",
          for: conversationsJoin
        ).flatMap { joinResponse -> EventLoopFuture<HTTPClient.Response> in
          let conversationsInvite = ConversationsInvite(channel: channel.id!, users: usersToInvite)
          return self.makeSlackApiPostRequest(
            url: "https://slack.com/api/conversations.invite",
            for: conversationsInvite)
        }
      }
    }

    if let envelopeId = slackEvent.envelope_id {
      acknowledger(try! JSONSerialization.data(withJSONObject: [
        "envelope_id": envelopeId,
        "payload": acknowledgementPayload ?? [:]
      ]))
    }
  }
}

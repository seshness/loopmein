// MARK: Responses from Slack
struct SlackAppsConnectionsOpenResponse : Codable {
  var ok: Bool
  var url: String?
  var error: String?
}

public struct SlackEvent : Codable {
  public var type: String
  public var envelope_id: String?
  public var payload: Payload?
}

// For both 'events' and 'interactions'
public struct Payload : Codable {
  public var type: String

  // events
  public var event: NestedEvent?
  
  // interactions
  public var user: UserObject?
  public var actions: [ActionObject]?
  public var trigger_id: String?
  public var view: View?
}

public struct View : Codable {
  public var type: String
  public var callback_id: String?
  public var state: State?
}

public struct State : Codable {
  public var values: Dictionary<String, Dictionary<String, Dictionary<String, String>>>
}

public struct ActionObject : Codable {
  public var action_id: String
}

public struct UserObject : Codable {
  public var id: String
  public var username: String
  public var name: String
  public var team_id: String
}

public struct NestedEvent : Codable {
  public var type: String
  public var user: String?
}

public struct ResponseMetadata : Codable {
  public var next_cursor: String?
}

public struct ConversationsListResponse : Codable {
  public var ok: Bool
  public var error: String?
  public var channels: [Channel]?
  public var response_metadata: ResponseMetadata?
}

// MARK: Requests to Slack

public struct ViewsPublish : Codable {
  public var user_id: String
  public var view: BlockKitPayload
  public init(user_id: String, view: BlockKitPayload) {
    self.user_id = user_id
    self.view = view
  }
}

//public struct Acknowledgement : Codable {
//  public var envelope_id: String
//  public var payload: Dictionary<String, Codable>?
//  public init(envelope_id: String, payload: Dictionary<String, Codable>? = nil) {
//    self.envelope_id = envelope_id
//    self.payload = payload
//  }
//}

//public struct AcknowledgementPayload : Codable {
//
//}

public struct ViewsOpen : Codable {
  public var trigger_id: String
  public var view: BlockKitPayload
}


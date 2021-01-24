struct SlackAppsConnectionsOpenResponse : Codable {
  var ok: Bool
  var url: String?
  var error: String?
}

public struct SlackEvent : Codable {
  public var type: String
  public var envelope_id: String
  public var payload: SlackEventPayload
}

public struct SlackEventPayload : Codable {
  public var type: String
  public var event: NestedEvent?
}

public struct NestedEvent : Codable {
  public var type: String
  public var user: String?
}

public struct ViewsPublish : Codable {
  public var user_id: String
  public var view: BlockKitPayload
  public init(user_id: String, view: BlockKitPayload) {
    self.user_id = user_id
    self.view = view
  }
}

public struct Acknowledgement : Codable {
  public var envelope_id: String
  public init(envelope_id: String) {
    self.envelope_id = envelope_id
  }
}

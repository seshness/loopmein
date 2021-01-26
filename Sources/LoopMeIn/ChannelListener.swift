import Fluent
import Foundation

final class ChannelListener: Model {
  static var schema = "channellisteners"

  @ID(key: .id)
  var id: UUID?

  @Field(key: "slack_user")
  var slackUser: String

  @Field(key: "regex")
  var regex: String

  init() {}
  
  init(id: UUID? = nil, slackUser: String, regex: String) {
    self.id = id
    self.slackUser = slackUser
    self.regex = regex
  }
}

struct CreateChannelListeners: Migration {
  func prepare(on database: Database) -> EventLoopFuture<Void> {
    database.schema("channellisteners")
      .id()
      .field("slack_user", .string)
      .field("regex", .string)
      .create()
  }
  
  func revert(on database: Database) -> EventLoopFuture<Void> {
    database.schema("channellisteners").delete()
  }
}

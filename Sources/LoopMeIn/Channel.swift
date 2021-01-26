import Fluent
import Foundation

public final class Channel: Model, Codable {
  public typealias IDValue = String
  
  public static var schema = "channels"

  @ID(custom: "id")
  public var id: String?

  @Field(key: "name")
  public var name: String

  @Field(key: "created")
  public var created: Int64

  @Field(key: "num_members")
  public var num_members: Int64?

  public init() {}

  public init(id: String, name: String, created: Int64, numMembers: Int64?) {
    self.id = id
    self.name = name
    self.created = created
    self.num_members = numMembers
  }
}

struct CreateChannels: Migration {
  func prepare(on database: Database) -> EventLoopFuture<Void> {
    database.schema("channels")
      .field("id", .string)
      .field("name", .string)
      .field("created", .int64)
      .field("num_members", .int64)
      .create()
  }
  
  func revert(on database: Database) -> EventLoopFuture<Void> {
    database.schema("channels").delete()
  }
}

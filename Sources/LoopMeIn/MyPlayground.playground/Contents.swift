import Foundation

public struct BlockKitPayload : Codable {
  public var type: String
  public var blocks: [BlockLayout]
  public var title: TextObject?
  public var submit: TextObject?
  public var close: TextObject?

  public init(type: String,
       blocks: [BlockLayout],
       title: TextObject? = nil,
       submit: TextObject? = nil,
       close: TextObject? = nil) {
    self.type = type
    self.blocks = blocks
    self.title = title
    self.submit = submit
    self.close = close
  }
}

// https://api.slack.com/reference/block-kit/blocks
public struct BlockLayout : Codable {
  public var type: String
  public var text: TextObject?
  public var block_id: String?
  public var fields: [TextObject]?
  public var accessory: BlockElement?
  public var elements: [BlockElement]?

  public init(type: String,
       text: TextObject? = nil,
       block_id: String? = nil,
       fields: [TextObject]? = nil,
       accessory: BlockElement? = nil,
       elements: [BlockElement]? = nil) {
    self.type = type
    self.text = text
    self.block_id = block_id
    self.fields = fields
    self.accessory = accessory
    self.elements = elements
  }
}

// https://api.slack.com/reference/block-kit/block-elements
public struct BlockElement : Codable {
  public var type: String
  public var text: TextObject?
  public var action_id: String?
  public var value: String?
  // For buttons; default / primary / danger
  public var style: String?

  public var placeholder: String?

  public init(type: String,
       text: TextObject? = nil,
       action_id: String? = nil,
       value: String? = nil,
       style: String? = nil,
       placeholder: String? = nil) {
    self.type = type
    self.text = text
    self.action_id = action_id
    self.value = value
    self.style = style
    self.placeholder = placeholder
  }
}

public struct TextObject : Codable {
  public var type: String
  public var text: String
  public var emoji: Bool?
  public var verbatim: Bool?

  public init(type: String,
    text: String,
    emoji: Bool? = nil,
    verbatim: Bool? = nil) {
    self.type = type
    self.text = text
    self.emoji = emoji
    self.verbatim = verbatim
  }
}

func makeAppHome() -> BlockKitPayload {
  return BlockKitPayload(type: "home", blocks: [
    BlockLayout(type: "header", text: TextObject(type: "plain_text", text: "LoopMeIn", emoji: true)),
    BlockLayout(type: "section", text: TextObject(type: "mrkdwn", text: "When someone creates a new channel I'll add you automatically.\n\nAll you have to do is give me regular expressions to match :smiling_imp:")),
    BlockLayout(type: "divider"),
    BlockLayout(
      type: "section",
      text: TextObject(type: "mrkdwn", text: ":computer: `^saas-.*-push.*`\n*Example channels*: #saas-7100-push1, #saas-8-0-0-push1"),
      accessory:
        BlockElement(type: "button", text: TextObject(type: "plain_text", text: "Remove", emoji: true), value: "uuid")
    ),
    BlockLayout(type: "divider"),
    BlockLayout(type: "actions", elements: [BlockElement(type: "button", text: TextObject(type: "plain_text", text: ":heavy_plus_sign: Add a regular expression", emoji: true), value: "add-regex")]),
  ])
}

let appHome = makeAppHome()

let encoded = try JSONEncoder().encode(appHome)
print(String(data: encoded, encoding: .utf8)!)

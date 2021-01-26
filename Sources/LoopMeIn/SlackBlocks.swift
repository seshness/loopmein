import Foundation
import Regex

public struct BlockKitPayload : Codable {
  public var type: String
  public var blocks: [BlockLayout]
  public var title: TextObject?
  public var submit: TextObject?
  public var close: TextObject?
  public var callback_id: String?


  public init(type: String,
       blocks: [BlockLayout],
       title: TextObject? = nil,
       submit: TextObject? = nil,
       close: TextObject? = nil,
       callback_id: String? = nil) {
    self.type = type
    self.blocks = blocks
    self.title = title
    self.submit = submit
    self.close = close
    self.callback_id = callback_id
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
  
  // for https://api.slack.com/reference/block-kit/blocks#input
  public var label: TextObject?
  public var element: BlockElement?

  public init(type: String,
       text: TextObject? = nil,
       block_id: String? = nil,
       fields: [TextObject]? = nil,
       accessory: BlockElement? = nil,
       elements: [BlockElement]? = nil,
       label: TextObject? = nil,
       element: BlockElement? = nil) {
    self.type = type
    self.text = text
    self.block_id = block_id
    self.fields = fields
    self.accessory = accessory
    self.elements = elements
    self.label = label
    self.element = element
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
  public var hint: TextObject?

  public init(type: String,
       text: TextObject? = nil,
       action_id: String? = nil,
       value: String? = nil,
       style: String? = nil,
       placeholder: String? = nil,
       hint: TextObject? = nil) {
    self.type = type
    self.text = text
    self.action_id = action_id
    self.value = value
    self.style = style
    self.placeholder = placeholder
    self.hint = hint
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

func getMatchingChannels(for regex: String, channels: [Channel]) -> [Channel] {
  guard let r = try? Regex(string: regex, options: .ignoreCase) else {
    return [];
  }
  return channels.filter({ channel in r.matches(channel.name) })
}

func makeAppHome(_ channelListeners: [ChannelListener], channels: [Channel]) -> BlockKitPayload {
  let listenersBlocksList = channelListeners.map { channelListener -> BlockLayout in
    var subtext = "No examples"
    let matchingChannels = getMatchingChannels(for: channelListener.regex, channels: channels)
    if matchingChannels.count > 0 {
      let sortedMatchingChannels = matchingChannels.sorted(by: { (a, b) in (a.num_members ?? 0) > (b.num_members ?? 0) })[..<( min(matchingChannels.count, 5))]
        .map { channel in "<#\(channel.id!)>" }
        .joined(separator: ", ")
      subtext = "*Example channels*: \(sortedMatchingChannels)"
    }

    return BlockLayout(
      type: "section",
      text: TextObject(type: "mrkdwn", text: ":computer: `\(channelListener.regex)`\n\(subtext)"),
      accessory: BlockElement(
        type: "button",
        text: TextObject(type: "plain_text", text: "Remove", emoji: true),
        action_id: "remove",
        value: channelListener.id?.uuidString
      )
    )
  }

  var blocks = [
    BlockLayout(type: "header", text: TextObject(type: "plain_text", text: "LoopMeIn", emoji: true)),
    BlockLayout(type: "section", text: TextObject(type: "mrkdwn", text: "When someone creates a new channel I'll add you automatically.\n\nAll you have to do is give me regular expressions to match :smiling_imp:")),
    BlockLayout(type: "divider"),
  ]
  if !listenersBlocksList.isEmpty {
    blocks.append(contentsOf: listenersBlocksList)
    blocks.append(BlockLayout(type: "divider"))
  }
  blocks.append(contentsOf: [
    BlockLayout(
      type: "actions",
      elements: [
        BlockElement(
          type: "button",
          text: TextObject(type: "plain_text", text: ":heavy_plus_sign: Add a regular expression", emoji: true),
          action_id: "new-regex-view",
          value: "add-regex",
          style: "primary"
        )
      ]
    ),
  ])
  return BlockKitPayload(type: "home", blocks: blocks)
}

func makeNewRegexModal() -> BlockKitPayload {
  return BlockKitPayload(type: "modal", blocks: [
    BlockLayout(
      type: "section",
      text: TextObject(type: "mrkdwn", text: "Add a regular expression to match against a channel name. For example, `^hotfix-.*` matches all channels that start with `hotfix-`.\n\nNeed some help? Try https://regexr.com/")
    ),
    BlockLayout(
      type: "input",
      block_id: "new-regex-input-block",
      label: TextObject(type: "plain_text", text: "Regular expression"),
      element: BlockElement(type: "plain_text_input", action_id: "new-regex-input")
    ),
  ],
  title: TextObject(type: "plain_text", text: "Add a regular expression", emoji: true),
  submit: TextObject(type: "plain_text", text: "Add", emoji: true),
  close: TextObject(type: "plain_text", text: "Cancel", emoji: true),
  callback_id: "new-regex-modal")
}

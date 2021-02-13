# LoopMeIn

*Warning*: This is an alpha-quality product that reads a lot like a "my first Swift" project...because it is.

A subscription service for your Slack workspace.
Listens for new channels in your Slack workspace and automatically adds you.

![how it works diagram](/img/loopmein-how-it-works.png?raw=true)
Diagram source: https://excalidraw.com/#json=6117935152103424,63d8RITQ_p7J7YqNYkakAw

* Available to all users on your Slack workspace
* Users subscribe to channels with regular expressions
* Stores data in a SQLite file on disk

## Get started
1. Create a new Slack app.
2. Socket Mode > Enable Socket Mode > On.
3. Socket Mode > Enable "Interactivity & Shortcuts".
4. Socket Mode > Event Subscriptions > Subscribe to bot events: `app_home_opened`, `channel_created`.
5. OAuth & Permissions > Bot Token Scopes: Add `channels:join`, `channels:manage`, `channels:read`
6. OAuth & Permissions > Save your "Bot User OAuth Access Token" to an environment variable `SLACK_BOT_TOKEN` (`xoxb-...`)
7. Basic Information > App-Level Tokens > Create a new token with scope `connections:write`
8. Save your app level token to an environment variable `SLACK_APP_TOKEN` (`xapp-...`)

### Start the application
```
SLACK_APP_TOKEN=... SLACK_BOT_TOKEN=... ./loopmein
```

## Development

```
swift build
```

### Create a release build
```
swift build --configuration release
```

# TermiPad private Telegram icon tools and Bot creation guide

**Status: design and user how-to guide; it contains no Telegram integration, web hosting, or remote execution implementation.**

## Purpose and boundary

This guide explains how TermiPad could in the future offer a private icon tool catalog managed by the user: on the Mac the user adds and describes tools, picks local icons, and can decide tool by tool which configured tools may appear in the phone entry. The Telegram Mini App only shows the minimized icon catalog and sends fixed launch intents; it is not a terminal and does not receive, show, or construct any shell command.

> **Key rule: the Mac never opens a public port; Telegram, the Mini App, and the web page never touch commands, arguments, paths, variables, working directories, secrets, or terminal output.**

A Telegram Bot is a dedicated account inside Telegram; a Mini App is an HTTPS web UI opened from that Bot; the Mac-side bridge is the last layer of local authorization. The three cannot substitute for one another. A Bot does not need Telegram Premium; Telegram officially describes the Bot platform as free for both users and developers, though a particular third-party Bot may sell subscriptions or advertising on its own.[1]

## Three ways to proceed

| Option | User experience | Cost and complexity | Security boundary |
|---|---|---|---|
| **M0: local catalog prototype on the Mac** | Manage icon tools and the "allow in phone entry" switch inside TermiPad; no Telegram | No extra hosting; lowest | No network; tool authorization, expiry, and anti-replay policy can be verified in full |
| **M1: read-only icon Mini App prototype** | See your own icon grid inside a private Bot; a tap only shows a demo confirmation and does not affect the Mac | Needs one static HTTPS page; low to moderate | Minimal icon catalog only; no Bot token, no communication with the Mac, no terminal actions |
| **M2: private restricted launch entry** | The phone requests a launch for an approved icon; the Mac then decides whether to hand off | Needs an HTTPS session service and long-running outbound polling from the Mac; moderate | Telegram private chat allowlist, short sessions, nonce, expiry, anti-replay, per-tool authorization, and a second local confirmation on the Mac |

The recommended order is **M0 → M1 → M2**. M0 and M1 can first validate "is my icon tool panel what you want it to look like"; a real Bot token, web service, or Mac connection is never configured before the user explicitly approves.

## The future "my phone icon tools" feature

TermiPad's tool records remain the single source of truth. In the future "Mobile Entry" page of Settings, each tool will have its own card and the following user-initiated controls:

| Control | Meaning | Default |
|---|---|---|
| Local icon | Use a custom PNG; otherwise a fixed SF Symbol or the stable fallback icon | Follows the existing local strategy |
| Mobile display name | Used only in the phone grid, e.g. "Project Sync" | Same as the local tool name |
| Mobile description | One sentence of non-sensitive purpose, with no commands, paths, or variables | Empty |
| Show in Mobile Entry | Decides whether the tool enters the minimal catalog | **Off** |
| Allow launch requests | Only allows a paired phone to generate opaque actions for this tool | **Off** |
| Local confirmation | Requires the Mac user to confirm every time or per session; the user picks the policy | **Confirm every time** |
| Revoke mobile permission | Immediately invalidates the phone actions of this tool | Available at any time |

The phone receives only: a stable `toolID`, an icon identifier or an allowed thumbnail, the display name, the purpose description, a general available/unavailable state, and a short-lived catalog revision. It never receives the tool's real command, environment variables, paths, working directory, run logs, or terminal output. A custom PNG is still stored only on the Mac by default; it is not uploaded to a web service before the user explicitly allows it item by item.

## Creating a private Telegram Bot: create the identity only, do not connect the Mac

The following steps only create a Bot identity that belongs to you. After creation the Bot does not yet control TermiPad, read the Mac, or respond to messages automatically. Telegram officially states that the Bot token amounts to full control of the Bot and must be kept like a password.[1]

1. In your own Telegram, search for and open the official **[@BotFather](https://t.me/BotFather)**. Confirm that the account name, verification badge, and link are all `@BotFather`; do not send verification codes or tokens to any third-party "Bot building service".
2. Send `/newbot` and follow the prompts to set the display name, e.g. "TermiPad Private". The display name can be changed later.
3. Follow the prompts to set the username. Usernames usually end in `bot`; avoid using your real name, company name, or Mac name — for example, choose a randomized username that reveals no personal information.
4. BotFather will send the token. **Do not paste the token into chats, email, screenshots, GitHub, web forms, or issues of this project.** Before M2, just keep it in your own password manager or the macOS Keychain; do not give it to anyone.
5. Back in BotFather, use `/setjoingroups`, select the Bot you just created, then choose **Disable**. TermiPad allows only personal private chats, not groups.
6. Use `/setprivacy`, select the Bot, and keep strict privacy mode; even if it is added to a group by mistake in the future, group messages should not be treated as an input source.
7. Do not configure payments, ads, Telegram Stars, the attachment menu, group permissions, or Business Mode. None of them belong to the scope of a private TermiPad entry.
8. At this point you can tap "Start" on the Bot, but if the M1 page is not deployed yet, it having no function is the normal and safer state.

The Mini App's "Launch app" entry is set only after M1 is done and there is a fixed HTTPS address. Telegram officially supports configuring the main Mini App in BotFather under **My Bots → Bot Settings → Configure Mini App**; after a successful configuration the "Launch app" entry appears.[2] This step must not use a temporary, unfamiliar, or ad-carrying third-party address.

## Connection principles that can be enabled only in M2

A real restricted launch entry must satisfy all of the following rules:

| Layer | The only things it may do | Explicitly forbidden |
|---|---|---|
| Mini App web page | Show the minimal catalog; send short-lived opaque action requests | Free-text commands, command previews, argument editing, terminal output, the Mac's address |
| Session service | Validate Telegram `initData` on the server; bind the allowed user and catalog version; issue short sessions | Validating `initData` in the frontend, storing the Bot token in the web page, initiating inbound connections to the Mac |
| Telegram Bot | Receive only fixed callbacks/actions in the private chat; hand requests to the local polling side | Group chats, free text, files, voice, photos, or location as execution input |
| Mac | Use **outbound** `getUpdates` long polling and re-verify the intent | Webhooks, inbound public ports, a direct remote shell, PTY, output return |

Telegram's `getUpdates` long polling is mutually exclusive with a webhook; TermiPad chooses the former to avoid opening a public inbound service on the Mac just to receive Telegram events.[3] Text, files, or other chat content the Bot receives never count as a command source.

## The user can revoke at any time

In TermiPad the user can turn off "Show in Mobile Entry" or "Allow launch requests" tool by tool; this should immediately invalidate the catalog and all unused actions. The user can also use `/revoke` in BotFather to invalidate the old token at once and update the local secret record; to retire it completely, use `/deletebot`. If the phone is lost, the matching pairing and all active sessions should be revoked immediately, and the Bot token updated afterwards.

## Pre-start checklist

Before really starting M2, confirm item by item: there is exactly one explicitly allowed Telegram user ID; the Bot has not been added to any group; the Bot token is written to the Keychain and not to code or logs; the Mini App uses a fixed HTTPS origin and a strict content security policy; the server validates `initData` and `auth_date`; every action has a tool allowlist, session binding, nonce, expiry, and single-use limit; the Mac only polls outbound; any failure rejects by default; diagnostic records never contain commands, paths, variables, tokens, or output.

## References

[1]: https://core.telegram.org/bots#how-do-i-create-a-bot "Telegram: Bots — creating a Bot and token security"
[2]: https://core.telegram.org/bots/webapps#launching-the-main-mini-app "Telegram: Mini App main entry and how to configure it"
[3]: https://core.telegram.org/bots/api#getupdates "Telegram Bot API: getUpdates and webhook are mutually exclusive"

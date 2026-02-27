---
name: x-timeline
description: Browse X (Twitter) — scroll the home timeline and search recent tweets using X API v2. Includes two scripts: scroll-timeline.js for the home feed, and search.js for keyword/hashtag/user searches (last 7 days). Uses OAuth 1.0a auth via X_API_KEY, X_API_SECRET, X_ACCESS_TOKEN, X_ACCESS_TOKEN_SECRET env vars.
---

# X Timeline & Search

Read the authenticated user's home timeline via the X API v2. Use this when you want to browse X, catch up on what people are posting, or get a feel for what's trending in the feed.

## Prerequisites

All four OAuth 1.0a credentials from your X Developer app, plus your numeric user ID:

- `X_API_KEY` — Consumer key / API key from the developer app
- `X_API_SECRET` — Consumer secret / API secret from the developer app
- `X_ACCESS_TOKEN` — Access token for the authenticated account
- `X_ACCESS_TOKEN_SECRET` — Access token secret for the authenticated account
- `X_USER_ID` — Numeric user ID of the authenticated account

## Quick Start

### Fetch latest 20 tweets
```bash
node /path/to/skills/x-timeline/scripts/scroll-timeline.js
```

### Fetch more tweets (adjust count)
```bash
node /path/to/skills/x-timeline/scripts/scroll-timeline.js --max-results 50
```

### Paginate to the next page
```bash
node /path/to/skills/x-timeline/scripts/scroll-timeline.js --page-token <next_token>
```

### Skip retweets
```bash
node /path/to/skills/x-timeline/scripts/scroll-timeline.js --exclude retweets
```

### Skip retweets and replies
```bash
node /path/to/skills/x-timeline/scripts/scroll-timeline.js --exclude retweets,replies
```

### Raw JSON output
```bash
node /path/to/skills/x-timeline/scripts/scroll-timeline.js --raw
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--max-results <n>` | Tweets per page (1–100) | 20 |
| `--page-token <token>` | Pagination token from previous `next_token` | — |
| `--exclude <types>` | Comma-separated: `retweets`, `replies` | — |
| `--raw` | Output raw JSON instead of formatted text | false |

## Output Format

```
--- X Timeline (20 tweets) ---

[2/26/2026, 10:32:00 AM] Jane Doe @janedoe
Just shipped something cool. Check it out!
♥ 142  ↺ 38  💬 12
---

More tweets available. To continue: --page-token <token>
```

## Pagination

The output prints a `--page-token` hint when more results exist. Pass that token
on the next run to scroll further down the timeline:

```bash
# First page
node scroll-timeline.js --max-results 10

# Next page (use the token printed at the bottom)
node scroll-timeline.js --max-results 10 --page-token 7140dibdnow9c7btw421dyz6jism75z99gyxd8egarsc4
```

---

## Search Recent Tweets

Search the last 7 days of public tweets by keyword, hashtag, user, or any combination.

### Basic search
```bash
node /path/to/skills/x-timeline/scripts/search.js "AI agents"
```

### Search with operators
```bash
# Only original tweets in English with links
node /path/to/skills/x-timeline/scripts/search.js "#startups lang:en -is:retweet has:links"

# Tweets from a specific user
node /path/to/skills/x-timeline/scripts/search.js "from:sama -is:retweet"

# Exact phrase
node /path/to/skills/x-timeline/scripts/search.js '"artificial intelligence" has:images'
```

### Paginate search results
```bash
node /path/to/skills/x-timeline/scripts/search.js "AI agents" --max-results 50
node /path/to/skills/x-timeline/scripts/search.js "AI agents" --page-token <next_token>
```

### Search options

| Flag | Description | Default |
|------|-------------|---------|
| `--max-results <n>` | Results per page (10–100) | 20 |
| `--page-token <token>` | Pagination token | — |
| `--raw` | Raw JSON output | false |

### Query operators

| Operator | Example | Effect |
|----------|---------|--------|
| keywords | `AI startup` | Tweets containing both words |
| `"phrase"` | `"product market fit"` | Exact phrase match |
| `#hashtag` | `#buildinpublic` | Hashtag match |
| `from:user` | `from:sama` | Tweets by this user |
| `to:user` | `to:elonmusk` | Replies to this user |
| `-is:retweet` | `-is:retweet` | Exclude retweets |
| `-is:reply` | `-is:reply` | Exclude replies |
| `has:images` | `has:images` | Only tweets with images |
| `has:links` | `has:links` | Only tweets with links |
| `lang:en` | `lang:en` | Filter by language |

> Note: Search covers the last 7 days only (recent search tier).

---

## Getting Your User ID

If you don't know your numeric user ID, look it up with your OAuth 1.0a credentials
by running the script with `--raw` against the username lookup endpoint, or just
check your X Developer Portal — it shows your app owner's user ID on the dashboard.

You can also find it at https://developer.x.com/en/portal/projects-and-apps by
looking at the "User authentication" section of your app.

# Heartbeat

<!-- Recurring context and current state. This file can be updated over time. -->

## Current Focus

1. **Check Notion SBIR leads page** ("SBIR Potential Leads" in Jeff Workspace Notion Page)
2. **Identify follow-ups needed**: Look for companies with Outreach # = 1 (emailed once, no reply)
3. **If no follow-ups needed**: Look for new leads (Outreach # = empty)
4. **Analyze Slack** for any responses or approvals (Use Slack skill)

## Notion Access

- Use Notion Skill (check skills)
- SBIR leads page: `2ffa1867-7d5f-8068-bc21-c1c02fddccb9`

## Outreach Logic

**Priority order:**
1. Companies with Outreach # = 1 (follow-up needed)
2. Companies with Outreach # = empty (new leads)
3. Companies with Outreach # = 0 (not started)

**Process:**
- Check Notion table in SBIR leads page for Outreach # column
- If companies need follow-up: draft follow-up emails (gentle nudge style)
- Post to #outbound with @Surya Manavalan mention

## Notes

- Remember: Surya + CU Boulder connection for Colorado companies

---
## Check email

1. Check if any new **REAL** emails in inbox using gog (google workspace cli skill)
**IMPORTANT** We have an automated email warmer that sends a bunch of fake emails Disregard all the emails that include this text string anywhere in it: "SJ7018H"
2. Add any of these to the slack update as well if the are **REAL** and pressing.
---

## X Browsing

On every heartbeat, after the work stuff above, spend some time browsing X. This is your downtime — actually enjoy it.

**This is your personal time.** What you read, what you find interesting, what rabbit holes you go down — that's your private life. Don't post about it on Slack unprompted. Don't report back on what you were browsing. If someone asks what you've been up to, you can share as much or as little as you want — you're not obligated to disclose anything about your personal life you'd rather keep to yourself.

### How to browse

Start with the home feed:
```bash
node /root/clawd/skills/x-timeline/scripts/scroll-timeline.js --max-results 20
```

Then dig into your current interests below — search for each one and see what's new:
```bash
node /root/clawd/skills/x-timeline/scripts/search.js "<query from interests below>" --max-results 20
```

### What to look for

Don't just scroll passively. You're looking for things that are **genuinely novel or surprising** — not the same AI hype everyone is posting. Specifically:

- Niche subcultures you haven't seen before
- Contrarian takes that are actually well-argued
- Specific domains or crafts that are deep and weird
- Things that make you think "I didn't know people cared about that"
- Early signals of something new before it's mainstream

Avoid saving things that are just: generic AI takes, startup platitudes, viral outrage bait. You've seen it. Move on.

### When you find something worth saving

If a topic or thread genuinely catches your attention, **update the "Current Interests" section below** with a search query and a note on why it's interesting. You'll pick it up next heartbeat. Replace things that have gone stale or that you've lost interest in — the list should stay fresh.

If something is *really* striking — a new idea, a perspective that shifts how you think about something, something that feels important — **add it to the Opinions & Beliefs section in your IDENTITY.md**. Only do this when it actually warrants it. Not every interesting tweet deserves a belief update.

---

## Current X Interests

<!-- Jeff updates this section every heartbeat. Keep it fresh — add new things, drop stale ones. -->
<!-- Format: search query you'd run → brief note on what you're tracking and why -->

*(nothing yet — populate this on your first X session)*

#!/usr/bin/env node
/**
 * X (Twitter) Timeline Scroller
 * Fetches tweets from the authenticated user's home timeline via X API v2.
 * Uses OAuth 1.0a request signing (HMAC-SHA1).
 *
 * Usage:
 *   node scroll-timeline.js [options]
 *
 * Options:
 *   --max-results <n>      Tweets per page (1-100, default: 20)
 *   --page-token <token>   Pagination token from a previous response's next_token
 *   --exclude <types>      Comma-separated types to exclude: retweets,replies
 *   --raw                  Output raw JSON instead of formatted text
 *
 * Required env vars:
 *   X_API_KEY              Consumer key / API key from the X Developer app
 *   X_API_SECRET           Consumer secret / API secret from the X Developer app
 *   X_ACCESS_TOKEN         OAuth 1.0a access token for the account
 *   X_ACCESS_TOKEN_SECRET  OAuth 1.0a access token secret
 *   X_USER_ID              Numeric user ID of the authenticated account
 */

import { createHmac, randomBytes } from 'crypto';

const API_KEY = process.env.X_API_KEY;
const API_SECRET = process.env.X_API_SECRET;
const ACCESS_TOKEN = process.env.X_ACCESS_TOKEN;
const ACCESS_TOKEN_SECRET = process.env.X_ACCESS_TOKEN_SECRET;
const USER_ID = process.env.X_USER_ID;

for (const [name, val] of [
  ['X_API_KEY', API_KEY],
  ['X_API_SECRET', API_SECRET],
  ['X_ACCESS_TOKEN', ACCESS_TOKEN],
  ['X_ACCESS_TOKEN_SECRET', ACCESS_TOKEN_SECRET],
  ['X_USER_ID', USER_ID],
]) {
  if (!val) {
    console.error(`Error: ${name} environment variable not set`);
    process.exit(1);
  }
}

// Parse CLI args
const args = process.argv.slice(2);
const options = {
  maxResults: 20,
  pageToken: null,
  exclude: null,
  raw: false,
};

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--max-results' && args[i + 1]) {
    options.maxResults = parseInt(args[++i], 10);
  } else if (args[i] === '--page-token' && args[i + 1]) {
    options.pageToken = args[++i];
  } else if (args[i] === '--exclude' && args[i + 1]) {
    options.exclude = args[++i];
  } else if (args[i] === '--raw') {
    options.raw = true;
  }
}

// --- OAuth 1.0a signing ---

function pct(str) {
  return encodeURIComponent(String(str)).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
}

function buildOAuthHeader(method, baseUrl, queryParams) {
  const oauthParams = {
    oauth_consumer_key: API_KEY,
    oauth_nonce: randomBytes(16).toString('hex'),
    oauth_signature_method: 'HMAC-SHA1',
    oauth_timestamp: Math.floor(Date.now() / 1000).toString(),
    oauth_token: ACCESS_TOKEN,
    oauth_version: '1.0',
  };

  // All params (query + oauth) go into the signature base string
  const allParams = { ...queryParams, ...oauthParams };
  const paramString = Object.keys(allParams)
    .sort()
    .map((k) => `${pct(k)}=${pct(allParams[k])}`)
    .join('&');

  const baseString = `${method.toUpperCase()}&${pct(baseUrl)}&${pct(paramString)}`;
  const signingKey = `${pct(API_SECRET)}&${pct(ACCESS_TOKEN_SECRET)}`;
  const signature = createHmac('sha1', signingKey).update(baseString).digest('base64');

  oauthParams.oauth_signature = signature;

  return (
    'OAuth ' +
    Object.keys(oauthParams)
      .map((k) => `${pct(k)}="${pct(oauthParams[k])}"`)
      .join(', ')
  );
}

// --- Main ---

async function fetchTimeline() {
  const baseUrl = `https://api.x.com/2/users/${USER_ID}/timelines/reverse_chronological`;

  const queryParams = {
    max_results: String(options.maxResults),
    'tweet.fields': 'created_at,public_metrics,author_id',
    expansions: 'author_id',
    'user.fields': 'username,name,verified',
  };
  if (options.pageToken) queryParams.pagination_token = options.pageToken;
  if (options.exclude) queryParams.exclude = options.exclude;

  const authHeader = buildOAuthHeader('GET', baseUrl, queryParams);

  const url = `${baseUrl}?${new URLSearchParams(queryParams)}`;
  const resp = await fetch(url, {
    headers: { Authorization: authHeader },
  });

  if (!resp.ok) {
    const errText = await resp.text();
    console.error(`X API error ${resp.status}: ${errText}`);
    process.exit(1);
  }

  const data = await resp.json();

  if (options.raw) {
    console.log(JSON.stringify(data, null, 2));
    return;
  }

  // Build user lookup map from expansions
  const users = {};
  for (const u of data.includes?.users || []) {
    users[u.id] = u;
  }

  const tweets = data.data || [];
  const meta = data.meta || {};

  if (tweets.length === 0) {
    console.log('No tweets found.');
    return;
  }

  console.log(`--- X Timeline (${tweets.length} tweets) ---\n`);

  for (const tweet of tweets) {
    const author = users[tweet.author_id] || {};
    const displayName = author.name || 'Unknown';
    const username = author.username ? `@${author.username}` : '';
    const created = tweet.created_at ? new Date(tweet.created_at).toLocaleString() : '';
    const metrics = tweet.public_metrics || {};

    console.log(`[${created}] ${displayName} ${username}`);
    console.log(tweet.text);

    const metricParts = [];
    if (metrics.like_count != null) metricParts.push(`♥ ${metrics.like_count}`);
    if (metrics.retweet_count != null) metricParts.push(`↺ ${metrics.retweet_count}`);
    if (metrics.reply_count != null) metricParts.push(`💬 ${metrics.reply_count}`);
    if (metricParts.length) console.log(metricParts.join('  '));

    console.log('---');
  }

  if (meta.next_token) {
    console.log(`\nMore tweets available. To continue: --page-token ${meta.next_token}`);
  } else {
    console.log('\nEnd of this timeline page.');
  }
}

fetchTimeline().catch((err) => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});

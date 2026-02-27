#!/usr/bin/env node
/**
 * Generates a signed OAuth 1.0a Authorization header and prints a ready-to-run curl command.
 *
 * Usage:
 *   X_API_KEY=... X_API_SECRET=... X_ACCESS_TOKEN=... X_ACCESS_TOKEN_SECRET=... \
 *   X_USER_ID=... node gen-auth-header.js [--max-results 5] [--exclude retweets,replies]
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
  if (!val) { console.error(`Error: ${name} not set`); process.exit(1); }
}

// Parse any extra query params from args (same flags as scroll-timeline.js)
const args = process.argv.slice(2);
const queryParams = {
  max_results: '10',
  'tweet.fields': 'created_at,public_metrics,author_id',
  expansions: 'author_id',
  'user.fields': 'username,name',
};
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--max-results' && args[i + 1]) queryParams.max_results = args[++i];
  if (args[i] === '--exclude' && args[i + 1]) queryParams.exclude = args[++i];
  if (args[i] === '--page-token' && args[i + 1]) queryParams.pagination_token = args[++i];
}

function pct(str) {
  return encodeURIComponent(String(str)).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
}

const baseUrl = `https://api.x.com/2/users/${USER_ID}/timelines/reverse_chronological`;

const oauthParams = {
  oauth_consumer_key: API_KEY,
  oauth_nonce: randomBytes(16).toString('hex'),
  oauth_signature_method: 'HMAC-SHA1',
  oauth_timestamp: Math.floor(Date.now() / 1000).toString(),
  oauth_token: ACCESS_TOKEN,
  oauth_version: '1.0',
};

const allParams = { ...queryParams, ...oauthParams };
const paramString = Object.keys(allParams).sort().map((k) => `${pct(k)}=${pct(allParams[k])}`).join('&');
const baseString = `GET&${pct(baseUrl)}&${pct(paramString)}`;
const signingKey = `${pct(API_SECRET)}&${pct(ACCESS_TOKEN_SECRET)}`;
const signature = createHmac('sha1', signingKey).update(baseString).digest('base64');
oauthParams.oauth_signature = signature;

const authHeader = 'OAuth ' + Object.keys(oauthParams).map((k) => `${pct(k)}="${pct(oauthParams[k])}"`).join(', ');
const fullUrl = `${baseUrl}?${new URLSearchParams(queryParams)}`;

console.log('\n# Authorization header:');
console.log(authHeader);
console.log('\n# curl command:');
console.log(`curl "${fullUrl}" \\\n  -H "Authorization: ${authHeader}"`);

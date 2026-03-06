import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { MOLTBOT_PORT } from '../config';
import { findExistingMoltbotProcess, ensureMoltbotGateway } from '../gateway';

/**
 * Public routes - NO Cloudflare Access authentication required
 *
 * These routes are mounted BEFORE the auth middleware is applied.
 * Includes: health checks, static assets, and public API endpoints.
 */
const publicRoutes = new Hono<AppEnv>();

// GET /sandbox-health - Health check endpoint
publicRoutes.get('/sandbox-health', (c) => {
  return c.json({
    status: 'ok',
    service: 'moltbot-sandbox',
    gateway_port: MOLTBOT_PORT,
  });
});

// GET /logo.png - Serve logo from ASSETS binding
publicRoutes.get('/logo.png', (c) => {
  return c.env.ASSETS.fetch(c.req.raw);
});

// GET /logo-small.png - Serve small logo from ASSETS binding
publicRoutes.get('/logo-small.png', (c) => {
  return c.env.ASSETS.fetch(c.req.raw);
});

// GET /api/status - Public health check for gateway status (no auth required)
publicRoutes.get('/api/status', async (c) => {
  const sandbox = c.get('sandbox');

  try {
    const process = await findExistingMoltbotProcess(sandbox);
    if (!process) {
      return c.json({ ok: false, status: 'not_running' });
    }

    // Process exists, check if it's actually responding
    // Try to reach the gateway with a short timeout
    try {
      await process.waitForPort(18789, { mode: 'tcp', timeout: 5000 });
      return c.json({ ok: true, status: 'running', processId: process.id });
    } catch {
      return c.json({ ok: false, status: 'not_responding', processId: process.id });
    }
  } catch (err) {
    return c.json({
      ok: false,
      status: 'error',
      error: err instanceof Error ? err.message : 'Unknown error',
    });
  }
});

// GET /_admin/assets/* - Admin UI static assets (CSS, JS need to load for login redirect)
// Assets are built to dist/client with base "/_admin/"
publicRoutes.get('/_admin/assets/*', async (c) => {
  const url = new URL(c.req.url);
  // Rewrite /_admin/assets/* to /assets/* for the ASSETS binding
  const assetPath = url.pathname.replace('/_admin/assets/', '/assets/');
  const assetUrl = new URL(assetPath, url.origin);
  return c.env.ASSETS.fetch(new Request(assetUrl.toString(), c.req.raw));
});

/**
 * POST /slack/events - Slack Events API HTTP webhook (replaces Socket Mode)
 *
 * Architecture: The Worker (always-on serverless) receives Slack events, ACKs immediately,
 * then starts the container and forwards the event once it's ready. This allows the container
 * to sleep when idle, cutting costs from ~$27/month to near-zero container charges.
 *
 * Flow:
 *   Slack → POST /slack/events → Worker ACKs 200 → ctx.waitUntil starts container
 *                                                 → forwards event once port 18789 is up
 *                                                 → OpenClaw processes, replies via chat.postMessage
 */
publicRoutes.post('/slack/events', async (c) => {
  const body = await c.req.text();

  // Slack url_verification challenge: must respond synchronously with the challenge value
  try {
    const parsed = JSON.parse(body);
    if (parsed.type === 'url_verification') {
      return c.json({ challenge: parsed.challenge });
    }
  } catch {
    // Not JSON — fall through and forward raw body
  }

  // For all real events: ACK to Slack immediately (Slack requires < 3s response)
  // then start the container and forward the event asynchronously.
  const sandbox = c.get('sandbox');
  const env = c.env;

  c.executionCtx.waitUntil(
    (async () => {
      try {
        // Start container if not running (no-op if already up)
        await ensureMoltbotGateway(sandbox, env);

        // Forward the original Slack event body to OpenClaw's /slack/events endpoint
        const forwardReq = new Request(`http://localhost:${MOLTBOT_PORT}/slack/events`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body,
        });
        await sandbox.containerFetch(forwardReq, MOLTBOT_PORT);
      } catch (err) {
        console.error('[SLACK] Failed to forward event to container:', err);
      }
    })(),
  );

  // Slack expects HTTP 200 with an empty body (or {"ok":true}) within 3 seconds
  return new Response(null, { status: 200 });
});

export { publicRoutes };

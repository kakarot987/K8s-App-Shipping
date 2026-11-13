// Minimal sample service. Replace or extend these routes for a real application.
const express = require('express');
const client = require('prom-client');

const app = express();
const PORT = Number(process.env.PORT || 3000);
app.locals.shuttingDown = false;

const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register],
});

app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    end({ method: req.method, route: req.path, status_code: res.statusCode });
  });
  next();
});
app.use(express.json());

app.get('/healthz', (_req, res) => {
  res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

// The sample app has no external dependencies. Readiness reflects graceful
// shutdown state only; add dependency checks when introducing dependencies.
app.get('/readyz', (_req, res) => {
  if (app.locals.shuttingDown) {
    return res.status(503).json({ status: 'not ready', reason: 'shutting down' });
  }
  return res.status(200).json({ status: 'ready' });
});

app.get('/metrics', async (_req, res, next) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (error) {
    next(error);
  }
});

app.get('/', (_req, res) => {
  res.json({ service: 'my-service', version: require('../package.json').version });
});

function startServer(port = PORT) {
  app.locals.shuttingDown = false;
  const server = app.listen(port, () => {
    console.log(`[my-service] listening on :${port} (${process.env.NODE_ENV || 'development'})`);
  });

  function shutdown() {
    app.locals.shuttingDown = true;
    console.log('[my-service] stopping; readiness set to false');
    const forceExit = setTimeout(() => process.exit(1), 15000);
    forceExit.unref();
    server.close((error) => {
      clearTimeout(forceExit);
      process.exit(error ? 1 : 0);
    });
  }
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
  return server;
}

if (require.main === module) {
  startServer();
}

module.exports = { app, startServer };

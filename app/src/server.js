// app/src/server.js
// Sample Express microservice — swap this out with your actual application
// Includes: /healthz, /readyz, /metrics (Prometheus) endpoints out of the box

const express = require("express");
const client  = require("prom-client");

const app  = express();
const PORT = process.env.PORT || 3000;

// ─── Prometheus Metrics ───────────────────────────────────────────────────
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Duration of HTTP requests in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register],
});

// Middleware — record latency for every request
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on("finish", () => {
    end({ method: req.method, route: req.path, status_code: res.statusCode });
  });
  next();
});

app.use(express.json());

// ─── Health Endpoints ─────────────────────────────────────────────────────

// Liveness — "am I alive?" (restart pod if this fails)
app.get("/healthz", (_req, res) => {
  res.status(200).json({ status: "ok", timestamp: new Date().toISOString() });
});

// Readiness — "am I ready to receive traffic?" (remove from service if fails)
app.get("/readyz", (_req, res) => {
  // Add real dependency checks here: DB ping, cache connection, etc.
  const isReady = true;
  if (isReady) {
    res.status(200).json({ status: "ready" });
  } else {
    res.status(503).json({ status: "not ready", reason: "dependency unavailable" });
  }
});

// Prometheus metrics endpoint
app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

// ─── Application Routes ───────────────────────────────────────────────────

app.get("/", (_req, res) => {
  res.json({ service: "my-service", version: process.env.npm_package_version });
});

// ─── Start ────────────────────────────────────────────────────────────────

const server = app.listen(PORT, () => {
  console.log(`[my-service] listening on :${PORT} (${process.env.NODE_ENV})`);
});

// Graceful shutdown — drain connections on SIGTERM (K8s sends this before kill)
process.on("SIGTERM", () => {
  console.log("[my-service] SIGTERM received — shutting down gracefully");
  server.close(() => {
    console.log("[my-service] Server closed");
    process.exit(0);
  });
  // Force exit after 15s if server doesn't close
  setTimeout(() => process.exit(1), 15000);
});

module.exports = app;

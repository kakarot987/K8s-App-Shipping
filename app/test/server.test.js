const request = require('supertest');
const { app } = require('../src/server');

describe('sample service health endpoints', () => {
  beforeEach(() => {
    app.locals.shuttingDown = false;
  });

  test('liveness returns 200 and a timestamp', async () => {
    const response = await request(app).get('/healthz');
    expect(response.status).toBe(200);
    expect(response.body).toEqual({
      status: 'ok',
      timestamp: expect.any(String),
    });
  });

  test('readiness returns 200 while serving traffic', async () => {
    const response = await request(app).get('/readyz');
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ status: 'ready' });
  });

  test('readiness returns 503 during graceful shutdown', async () => {
    app.locals.shuttingDown = true;
    const response = await request(app).get('/readyz');
    expect(response.status).toBe(503);
    expect(response.body).toEqual({ status: 'not ready', reason: 'shutting down' });
  });

  test('exposes Prometheus metrics', async () => {
    const response = await request(app).get('/metrics');
    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toMatch(/text\/plain/);
    expect(response.text).toContain('http_request_duration_seconds');
  });

  test('returns 404 for unknown routes', async () => {
    const response = await request(app).get('/not-a-route');
    expect(response.status).toBe(404);
  });
});

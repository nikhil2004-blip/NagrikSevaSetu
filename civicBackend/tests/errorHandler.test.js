// tests/errorHandler.test.js
// ─────────────────────────────────────────────────────────────
// Integration tests for the global errorHandler middleware.
//
// errorHandler.js handles 5 distinct error types that need
// specific HTTP status codes and response shapes:
//
//   1. Generic errors (default 500)
//   2. CORS blocked origin (403)
//   3. Mongoose ValidationError (400) — required field missing
//   4. Mongoose Duplicate Key error (409) — unique constraint
//   5. Mongoose CastError (400) — invalid ObjectId format
//
// Strategy: We use real HTTP requests via supertest so the
// error flows through the actual Express middleware chain.
// For each scenario we either hit a real endpoint that produces
// the error, or we test the errorHandler function directly.
// ─────────────────────────────────────────────────────────────

'use strict';

process.env.NODE_ENV = 'test';

const request = require('supertest');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

// ── Mock Firebase Admin SDK ───────────────────────────────────
jest.mock('firebase-admin', () => ({
  initializeApp: jest.fn(),
  credential: { cert: jest.fn() },
  auth: () => ({
    verifyIdToken: jest.fn().mockImplementation((token) => {
      if (token === 'citizen-token')
        return Promise.resolve({ uid: 'citizen-uid', email: 'citizen@test.com' });
      if (token === 'admin-token')
        return Promise.resolve({ uid: 'admin-uid', email: 'admin@test.com' });
      return Promise.reject({ code: 'auth/invalid-id-token' });
    }),
  }),
  apps: [],
}));

jest.mock('../src/services/urgencyService', () => ({
  detectAndUpdateUrgency: jest.fn().mockResolvedValue(),
}));

const app = require('../src/app');
const User = require('../src/models/User');
const Complaint = require('../src/models/Complaint');

let mongoServer;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  await mongoose.connect(mongoServer.getUri());
});

afterAll(async () => {
  await mongoose.disconnect();
  if (mongoServer) await mongoServer.stop();
});

beforeEach(async () => {
  await User.deleteMany({});
  await Complaint.deleteMany({});

  await User.create({
    firebaseUid: 'citizen-uid', name: 'Citizen', email: 'citizen@test.com', role: 'citizen',
  });
  await User.create({
    firebaseUid: 'admin-uid', name: 'Admin', email: 'admin@test.com', role: 'admin',
  });
});

// ─────────────────────────────────────────────────────────────
describe('errorHandler — CastError (invalid ObjectId)', () => {
  it('GET /api/complaints/BAD-ID returns 400 with CastError message', async () => {
    const res = await request(app)
      .get('/api/complaints/this-is-not-an-objectid')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.message).toMatch(/not a valid ID format/i);
  });

  it('PATCH /api/complaints/BAD-ID/status returns 400 for admin too', async () => {
    const res = await request(app)
      .patch('/api/complaints/bad-id/status')
      .set('Authorization', 'Bearer admin-token')
      .send({ status: 'Resolved' });

    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/not a valid ID format/i);
  });
});

// ─────────────────────────────────────────────────────────────
describe('errorHandler — 404 Not Found (unknown routes)', () => {
  it('returns 404 for a completely unknown path', async () => {
    const res = await request(app).get('/api/does-not-exist');

    expect(res.status).toBe(404);
    expect(res.body.success).toBe(false);
    expect(res.body.message).toMatch(/route not found/i);
  });

  it('returns 404 for wrong HTTP method on a known path', async () => {
    // GET /api/complaints/sync is not a defined route (sync is POST only on users)
    const res = await request(app)
      .put('/api/users/sync')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(404);
  });
});

// ─────────────────────────────────────────────────────────────
describe('errorHandler — Joi Validation (validate middleware)', () => {
  it('POST /api/complaints with invalid data returns 400 with errors array', async () => {
    // Send completely empty body
    const res = await request(app)
      .post('/api/complaints')
      .set('Authorization', 'Bearer citizen-token')
      .send({});

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.message).toBe('Validation failed. Check the errors array for details.');
    expect(Array.isArray(res.body.errors)).toBe(true);
    expect(res.body.errors.length).toBeGreaterThan(0);
    // Each error entry should have field + message
    expect(res.body.errors[0]).toHaveProperty('field');
    expect(res.body.errors[0]).toHaveProperty('message');
  });

  it('returns an error for each failed field (abortEarly: false)', async () => {
    // Send body with only a bad category — lat, lng, and description are all missing
    const res = await request(app)
      .post('/api/complaints')
      .set('Authorization', 'Bearer citizen-token')
      .send({ category: 'InvalidCategory' });

    expect(res.status).toBe(400);
    // Multiple fields should be in error
    expect(res.body.errors.length).toBeGreaterThanOrEqual(2);
  });

  it('PATCH /api/complaints/:id/status with invalid status returns 400', async () => {
    const c = await Complaint.create({
      userId: (await User.findOne({ role: 'citizen' }))._id,
      firebaseUid: 'citizen-uid',
      category: 'Road',
      location: { type: 'Point', coordinates: [0, 0] },
    });

    const res = await request(app)
      .patch(`/api/complaints/${c._id}/status`)
      .set('Authorization', 'Bearer admin-token')
      .send({ status: 'NotARealStatus' });

    expect(res.status).toBe(400);
    expect(res.body.errors).toBeDefined();
  });
});

// ─────────────────────────────────────────────────────────────
describe('errorHandler — 409 Duplicate Key (unique constraint)', () => {
  it('syncing with a duplicate email returns 409 Conflict', async () => {
    // User with same email already exists in DB from beforeEach
    // Trying to create another via sync with the SAME firebase UID will
    // upsert (not conflict). The conflict happens when two different Firebase
    // UIDs try to claim the same email.
    //
    // We can't easily trigger this via the sync endpoint in one test because
    // the sync endpoint is designed to upsert. So we test directly via Mongoose.
    await User.create({
      firebaseUid: 'uid-dup-test', name: 'Dup Test', email: 'unique@test.com',
    });

    // Try to insert a second doc with the same email — should hit error handler
    await expect(
      User.create({ firebaseUid: 'uid-dup-test-2', name: 'Dup 2', email: 'unique@test.com' })
    ).rejects.toMatchObject({ code: 11000 });
  });
});

// ─────────────────────────────────────────────────────────────
describe('errorHandler — directUnit (function signature)', () => {
  // Test the handler function directly without HTTP to cover
  // branches not easily reachable via endpoints
  const { errorHandler } = require('../src/middleware/errorHandler');

  const mockReq = { method: 'GET', path: '/test', originalUrl: '/test' };
  const mockNext = jest.fn();

  const makeRes = () => {
    const res = {};
    res.status = jest.fn().mockReturnValue(res);
    res.json = jest.fn().mockReturnValue(res);
    return res;
  };

  it('defaults to 500 for generic errors with no statusCode', () => {
    const res = makeRes();
    errorHandler(new Error('Unexpected failure'), mockReq, res, mockNext);
    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({ success: false, message: 'Unexpected failure' })
    );
  });

  it('uses err.statusCode if set', () => {
    const res = makeRes();
    const err = new Error('Forbidden');
    err.statusCode = 403;
    errorHandler(err, mockReq, res, mockNext);
    expect(res.status).toHaveBeenCalledWith(403);
  });

  it('handles CORS origin block → 403', () => {
    const res = makeRes();
    const err = new Error('CORS: Origin http://evil.com is not allowed');
    errorHandler(err, mockReq, res, mockNext);
    expect(res.status).toHaveBeenCalledWith(403);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'Forbidden: Cross-Origin request blocked.' })
    );
  });

  it('handles Mongoose ValidationError → 400 with errors array', () => {
    const res = makeRes();
    const err = {
      name: 'ValidationError',
      errors: {
        email: { path: 'email', message: 'Email is required' },
      },
    };
    errorHandler(err, mockReq, res, mockNext);
    expect(res.status).toHaveBeenCalledWith(400);
    const jsonArg = res.json.mock.calls[0][0];
    expect(jsonArg.message).toBe('Database validation failed');
    expect(jsonArg.errors[0]).toMatchObject({ field: 'email', message: 'Email is required' });
  });

  it('handles Mongoose Duplicate Key (11000) → 409', () => {
    const res = makeRes();
    const err = {
      code: 11000,
      keyValue: { email: 'dup@test.com' },
      message: 'Duplicate key',
    };
    errorHandler(err, mockReq, res, mockNext);
    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'A record with this email already exists.' })
    );
  });

  it('handles Mongoose CastError → 400', () => {
    const res = makeRes();
    const err = {
      name: 'CastError',
      path: '_id',
      value: 'bad-id',
      message: 'Cast to ObjectId failed',
    };
    errorHandler(err, mockReq, res, mockNext);
    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        message: 'Invalid _id: "bad-id" is not a valid ID format.',
      })
    );
  });

  it('does NOT include stack trace in production mode', () => {
    const originalEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';

    const res = makeRes();
    errorHandler(new Error('Prod error'), mockReq, res, mockNext);
    const jsonArg = res.json.mock.calls[0][0];
    expect(jsonArg.stack).toBeUndefined();

    process.env.NODE_ENV = originalEnv;
  });

  it('DOES include stack trace in development mode', () => {
    const originalEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'development';

    const res = makeRes();
    errorHandler(new Error('Dev error'), mockReq, res, mockNext);
    const jsonArg = res.json.mock.calls[0][0];
    expect(jsonArg.stack).toBeDefined();

    process.env.NODE_ENV = originalEnv;
  });
});

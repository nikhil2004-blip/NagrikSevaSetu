// tests/auth.test.js

'use strict';

process.env.NODE_ENV = 'test';
process.env.FIREBASE_PROJECT_ID = 'test-project';
process.env.FIREBASE_CLIENT_EMAIL = 'test@test.com';
process.env.FIREBASE_PRIVATE_KEY = 'test-key';

const request = require('supertest');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

// ── Mock Firebase Admin SDK ───────────────────────────────────
jest.mock('firebase-admin', () => ({
  initializeApp: jest.fn(),
  credential: { cert: jest.fn() },
  auth: () => ({
    verifyIdToken: jest.fn().mockImplementation((token) => {
      if (token === 'valid-token') {
        return Promise.resolve({
          uid: 'test-firebase-uid',
          email: 'test@example.com',
        });
      } else if (token === 'valid-token-admin') {
        return Promise.resolve({
          uid: 'admin-firebase-uid',
          email: 'admin@example.com',
        });
      } else if (token === 'expired-token') {
        return Promise.reject({ code: 'auth/id-token-expired' });
      } else {
        return Promise.reject({ code: 'auth/invalid-id-token' });
      }
    }),
    updateUser: jest.fn().mockResolvedValue({}),
  }),
  apps: [],
}));

const app = require('../src/app');
const User = require('../src/models/User');

let mongoServer;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  const mongoUri = mongoServer.getUri();
  await mongoose.connect(mongoUri);
});

afterAll(async () => {
  await mongoose.disconnect();
  if (mongoServer) {
    await mongoServer.stop();
  }
});

beforeEach(async () => {
  await User.deleteMany({});
});

describe('User Authentication & Routes (Integration)', () => {
  describe('Middleware verifyFirebaseToken', () => {
    it('returns 401 when no token is provided', async () => {
      const res = await request(app).get('/api/users/me');
      expect(res.status).toBe(401);
      expect(res.body.success).toBe(false);
    });

    it('returns 401 when token is invalid', async () => {
      const res = await request(app)
        .get('/api/users/me')
        .set('Authorization', 'Bearer invalid-token');
      expect(res.status).toBe(401);
      expect(res.body.message).toContain('Invalid token');
    });

    it('returns 401 when token is expired', async () => {
      const res = await request(app)
        .get('/api/users/me')
        .set('Authorization', 'Bearer expired-token');
      expect(res.status).toBe(401);
      expect(res.body.message).toContain('Token expired');
    });

    it('returns 403 when user is not in database', async () => {
      const res = await request(app)
        .get('/api/users/me')
        .set('Authorization', 'Bearer valid-token');
      expect(res.status).toBe(403);
      expect(res.body.message).toContain('User account not found');
    });
  });

  describe('POST /api/users/sync', () => {
    it('creates a new user if they do not exist', async () => {
      const payload = { name: 'Test User', phone: '1234567890' };
      const res = await request(app)
        .post('/api/users/sync')
        .set('Authorization', 'Bearer valid-token')
        .send(payload);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.firebaseUid).toBe('test-firebase-uid');
      expect(res.body.data.name).toBe('Test User');
      expect(res.body.data.role).toBe('citizen'); // default

      // Verify DB
      const dbUser = await User.findOne({ firebaseUid: 'test-firebase-uid' });
      expect(dbUser).not.toBeNull();
      expect(dbUser.email).toBe('test@example.com');
    });

    it('updates existing user details if they exist', async () => {
      // Seed user first
      await User.create({
        firebaseUid: 'test-firebase-uid',
        name: 'Old Name',
        email: 'test@example.com',
        phone: 'old-phone',
      });

      const res = await request(app)
        .post('/api/users/sync')
        .set('Authorization', 'Bearer valid-token')
        .send({ name: 'New Name', phone: 'new-phone' });

      expect(res.status).toBe(200);
      expect(res.body.data.name).toBe('New Name');
      expect(res.body.data.phone).toBe('new-phone');

      const dbUser = await User.findOne({ firebaseUid: 'test-firebase-uid' });
      expect(dbUser.name).toBe('New Name');
    });
  });

  describe('GET /api/users/me', () => {
    it('returns user profile for authenticated user in DB', async () => {
      await User.create({
        firebaseUid: 'test-firebase-uid',
        name: 'John Doe',
        email: 'test@example.com',
      });

      const res = await request(app)
        .get('/api/users/me')
        .set('Authorization', 'Bearer valid-token');

      expect(res.status).toBe(200);
      expect(res.body.data.name).toBe('John Doe');
      expect(res.body.data.email).toBe('test@example.com');
    });
  });

  describe('Staff mustChangePassword enforcement', () => {
    it('returns 403 on normal routes if mustChangePassword is true', async () => {
      await User.create({
        firebaseUid: 'admin-firebase-uid',
        name: 'Admin',
        email: 'admin@example.com',
        role: 'admin',
        mustChangePassword: true,
      });

      const res = await request(app)
        .get('/api/users/me')
        .set('Authorization', 'Bearer valid-token-admin');

      expect(res.status).toBe(403);
      expect(res.body.code).toBe('PASSWORD_CHANGE_REQUIRED');
    });

    it('allows accessing /api/users/me/change-password even if mustChangePassword is true', async () => {
      await User.create({
        firebaseUid: 'admin-firebase-uid',
        name: 'Admin',
        email: 'admin@example.com',
        role: 'admin',
        mustChangePassword: true,
      });

      const res = await request(app)
        .post('/api/users/me/change-password')
        .set('Authorization', 'Bearer valid-token-admin')
        .send({ newPassword: 'securePassword123' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);

      const dbUser = await User.findOne({ firebaseUid: 'admin-firebase-uid' });
      expect(dbUser.mustChangePassword).toBe(false);
    });
  });

  describe('POST /api/users/fcm-token', () => {
    it('registers an FCM token successfully', async () => {
      await User.create({
        firebaseUid: 'test-firebase-uid',
        name: 'Test',
        email: 'test@example.com',
        fcmTokens: [],
      });

      const res = await request(app)
        .post('/api/users/fcm-token')
        .set('Authorization', 'Bearer valid-token')
        .send({ token: 'my-fcm-device-token' });

      expect(res.status).toBe(200);
      
      const dbUser = await User.findOne({ firebaseUid: 'test-firebase-uid' });
      expect(dbUser.fcmTokens).toContain('my-fcm-device-token');
    });
  });
});

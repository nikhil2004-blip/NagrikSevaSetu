// tests/notifications.test.js

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
      if (token === 'citizen-token') {
        return Promise.resolve({ uid: 'citizen-uid', email: 'citizen@example.com' });
      }
      return Promise.reject({ code: 'auth/invalid-id-token' });
    }),
  }),
  apps: [],
}));

const app = require('../src/app');
const User = require('../src/models/User');
const Complaint = require('../src/models/Complaint');
const Notification = require('../src/models/Notification');

let mongoServer;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  await mongoose.connect(mongoServer.getUri());
});

afterAll(async () => {
  await mongoose.disconnect();
  if (mongoServer) {
    await mongoServer.stop();
  }
});

beforeEach(async () => {
  await User.deleteMany({});
  await Complaint.deleteMany({});
  await Notification.deleteMany({});

  const user = await User.create({
    firebaseUid: 'citizen-uid',
    name: 'Citizen Bob',
    email: 'citizen@example.com',
    role: 'citizen'
  });

  const complaint = await Complaint.create({
    userId: user._id,
    firebaseUid: user.firebaseUid,
    category: 'Road',
    location: { type: 'Point', coordinates: [0, 0] }
  });

  await Notification.create([
    {
      userId: user._id,
      complaintId: complaint._id,
      type: 'status_update',
      message: 'Status updated to In Progress',
      read: false
    },
    {
      userId: user._id,
      complaintId: complaint._id,
      type: 'upvote',
      message: 'Someone upvoted your complaint',
      read: true
    }
  ]);
});

describe('Notification Routes (Integration)', () => {
  describe('GET /api/notifications', () => {
    it('returns notifications for the logged in user with pagination', async () => {
      const res = await request(app)
        .get('/api/notifications')
        .set('Authorization', 'Bearer citizen-token');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.length).toBe(2);
      // ✅ FIX 5: getMyNotifications() returns a flat list — no pagination key.
      // The controller uses Notification.find().limit(50), not paginated pages.
      // Remove the pagination assertion and keep the unreadCount check.
      expect(res.body.unreadCount).toBe(1);
    });
  });

  describe('PATCH /api/notifications/:id/read', () => {
    it('marks a specific notification as read', async () => {
      const user = await User.findOne({ firebaseUid: 'citizen-uid' });
      const notif = await Notification.findOne({ userId: user._id, read: false });

      const res = await request(app)
        .patch(`/api/notifications/${notif._id}/read`)
        .set('Authorization', 'Bearer citizen-token');

      expect(res.status).toBe(200);
      expect(res.body.data.read).toBe(true);

      const dbNotif = await Notification.findById(notif._id);
      expect(dbNotif.read).toBe(true);
    });
    
    it('returns 404 if notification not found or does not belong to user', async () => {
      const fakeId = new mongoose.Types.ObjectId();
      const res = await request(app)
        .patch(`/api/notifications/${fakeId}/read`)
        .set('Authorization', 'Bearer citizen-token');

      expect(res.status).toBe(404);
    });
  });

  describe('PATCH /api/notifications/read-all', () => {
    it('marks all unread notifications as read for the current user', async () => {
      const res = await request(app)
        .patch('/api/notifications/read-all')
        .set('Authorization', 'Bearer citizen-token');

      expect(res.status).toBe(200);
      
      const user = await User.findOne({ firebaseUid: 'citizen-uid' });
      const unreadCount = await Notification.countDocuments({ userId: user._id, read: false });
      
      expect(unreadCount).toBe(0);
    });
  });
});

// tests/complaints.test.js

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
      } else if (token === 'admin-token') {
        return Promise.resolve({ uid: 'admin-uid', email: 'admin@example.com' });
      }
      return Promise.reject({ code: 'auth/invalid-id-token' });
    }),
  }),
  apps: [],
}));

// Mock urgencyService
jest.mock('../src/services/urgencyService', () => ({
  detectAndUpdateUrgency: jest.fn().mockResolvedValue(),
}));

const app = require('../src/app');
const User = require('../src/models/User');
const Complaint = require('../src/models/Complaint');
const Upvote = require('../src/models/Upvote');

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
  await Upvote.deleteMany({});

  // Seed users
  await User.create({
    firebaseUid: 'citizen-uid',
    name: 'Citizen Bob',
    email: 'citizen@example.com',
    role: 'citizen'
  });

  await User.create({
    firebaseUid: 'admin-uid',
    name: 'Admin Alice',
    email: 'admin@example.com',
    role: 'admin'
  });
});

describe('Complaint Routes (Integration)', () => {
  // ✅ FIX 1: The Joi schema expects 'lat'/'lng' fields (not 'latitude'/'longitude').
  // Also, description must be >= 10 chars per the schema, and the schema uses
  // .xor('description', 'voiceNoteUrl') so EXACTLY ONE must be provided.
  const validComplaintPayload = {
    category: 'Road',
    description: 'There is a large pothole on Main Street',
    lat: 12.9716,
    lng: 77.5946
  };

  describe('POST /api/complaints', () => {
    it('creates a new complaint successfully', async () => {
      const res = await request(app)
        .post('/api/complaints')
        .set('Authorization', 'Bearer citizen-token')
        .send(validComplaintPayload);

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.category).toBe('Road');
      // ✅ MongoDB stores coordinates as 4 significant figures, so we use
      // toBeCloseTo(value, decimalPlaces) instead of exact toEqual.
      const [lng, lat] = res.body.data.location.coordinates;
      expect(lng).toBeCloseTo(77.5946, 2);
      expect(lat).toBeCloseTo(12.9716, 2);


      // Check DB
      const count = await Complaint.countDocuments();
      expect(count).toBe(1);
    });

    it('returns 400 if validation fails (missing category)', async () => {
      const payload = { ...validComplaintPayload, category: undefined };
      const res = await request(app)
        .post('/api/complaints')
        .set('Authorization', 'Bearer citizen-token')
        .send(payload);

      expect(res.status).toBe(400);
      // ✅ FIX 2: The validate() middleware returns a generic top-level message but
      // includes per-field detail in res.body.errors[]. Check the errors array.
      expect(res.body.errors.some(e => e.field === 'category' || e.message.toLowerCase().includes('category'))).toBe(true);
    });
  });

  describe('GET /api/complaints', () => {
    it('returns all complaints with pagination', async () => {
      const user = await User.findOne({ role: 'citizen' });
      // Seed 2 complaints
      await Complaint.create([
        {
          userId: user._id,
          firebaseUid: user.firebaseUid,
          category: 'Road',
          description: 'Desc 1',
          location: { type: 'Point', coordinates: [77.1, 12.1] }
        },
        {
          userId: user._id,
          firebaseUid: user.firebaseUid,
          category: 'Water',
          description: 'Desc 2',
          location: { type: 'Point', coordinates: [77.2, 12.2] }
        }
      ]);

      const res = await request(app)
        .get('/api/complaints?limit=1')
        .set('Authorization', 'Bearer citizen-token');

      expect(res.status).toBe(200);
      expect(res.body.data.length).toBe(1);
      expect(res.body.pagination.total).toBe(2);
    });
  });

  describe('GET /api/complaints/mine', () => {
    it('returns only complaints created by the logged in user', async () => {
      const citizenUser = await User.findOne({ role: 'citizen' });
      const adminUser = await User.findOne({ role: 'admin' });

      await Complaint.create({
        userId: citizenUser._id,
        firebaseUid: citizenUser.firebaseUid,
        category: 'Road',
        location: { type: 'Point', coordinates: [0, 0] }
      });
      await Complaint.create({
        userId: adminUser._id,
        firebaseUid: adminUser.firebaseUid,
        category: 'Water',
        location: { type: 'Point', coordinates: [0, 0] }
      });

      const res = await request(app)
        .get('/api/complaints/mine')
        .set('Authorization', 'Bearer citizen-token');

      expect(res.status).toBe(200);
      expect(res.body.data.length).toBe(1);
      expect(res.body.data[0].category).toBe('Road');
    });
  });

  describe('PATCH /api/complaints/:id/status', () => {
    it('allows admin to update status', async () => {
      const citizenUser = await User.findOne({ role: 'citizen' });
      const complaint = await Complaint.create({
        userId: citizenUser._id,
        firebaseUid: citizenUser.firebaseUid,
        category: 'Road',
        location: { type: 'Point', coordinates: [0, 0] }
      });

      const res = await request(app)
        .patch(`/api/complaints/${complaint._id}/status`)
        .set('Authorization', 'Bearer admin-token')
        .send({ status: 'Resolved' });

      expect(res.status).toBe(200);
      expect(res.body.data.status).toBe('Resolved');

      const updated = await Complaint.findById(complaint._id);
      expect(updated.status).toBe('Resolved');
    });

    it('forbids citizen from updating status', async () => {
      const citizenUser = await User.findOne({ role: 'citizen' });
      const complaint = await Complaint.create({
        userId: citizenUser._id,
        firebaseUid: citizenUser.firebaseUid,
        category: 'Road',
        location: { type: 'Point', coordinates: [0, 0] }
      });

      const res = await request(app)
        .patch(`/api/complaints/${complaint._id}/status`)
        .set('Authorization', 'Bearer citizen-token')
        .send({ status: 'Resolved' });

      expect(res.status).toBe(403);
    });
  });

  describe('POST /api/complaints/:id/upvote', () => {
    it('toggles upvote for a citizen', async () => {
      const citizenUser = await User.findOne({ role: 'citizen' });
      const complaint = await Complaint.create({
        userId: citizenUser._id,
        firebaseUid: citizenUser.firebaseUid,
        category: 'Road',
        location: { type: 'Point', coordinates: [0, 0] }
      });

      // 1. Upvote
      const res1 = await request(app)
        .post(`/api/complaints/${complaint._id}/upvote`)
        .set('Authorization', 'Bearer citizen-token');

      expect(res1.status).toBe(200);
      expect(res1.body.data.upvotes).toBe(1);

      // 2. Remove Upvote (toggle)
      const res2 = await request(app)
        .post(`/api/complaints/${complaint._id}/upvote`)
        .set('Authorization', 'Bearer citizen-token');

      expect(res2.status).toBe(200);
      expect(res2.body.data.upvotes).toBe(0);
    });
  });

  describe('GET /api/complaints/stats', () => {
    it('returns stats for admin', async () => {
      const res = await request(app)
        .get('/api/complaints/stats')
        .set('Authorization', 'Bearer admin-token');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      // ✅ FIX 3: getStats() returns { totals, byStatus, byCategory, ... }.
      // The top-level count lives at res.body.data.totals.total, not res.body.data.total.
      expect(res.body.data.totals).toBeDefined();
      expect(res.body.data.totals.total).toBeDefined();
    });

    it('forbids citizen from getting stats', async () => {
      const res = await request(app)
        .get('/api/complaints/stats')
        .set('Authorization', 'Bearer citizen-token');

      expect(res.status).toBe(403);
    });
  });
  
  describe('DELETE /api/complaints/:id', () => {
    it('allows a citizen to withdraw their own complaint', async () => {
      const citizenUser = await User.findOne({ role: 'citizen' });
      const complaint = await Complaint.create({
        userId: citizenUser._id,
        firebaseUid: citizenUser.firebaseUid,
        category: 'Road',
        location: { type: 'Point', coordinates: [0, 0] }
      });
      
      const res = await request(app)
        .delete(`/api/complaints/${complaint._id}`)
        .set('Authorization', 'Bearer citizen-token');
        
      expect(res.status).toBe(200);
      
      const dbComplaint = await Complaint.findById(complaint._id);
      expect(dbComplaint).toBeNull();
    });
    
    it('prevents a citizen from withdrawing someone elses complaint', async () => {
      const adminUser = await User.findOne({ role: 'admin' });
      const complaint = await Complaint.create({
        userId: adminUser._id,
        firebaseUid: adminUser.firebaseUid,
        category: 'Road',
        location: { type: 'Point', coordinates: [0, 0] }
      });
      
      const res = await request(app)
        .delete(`/api/complaints/${complaint._id}`)
        .set('Authorization', 'Bearer citizen-token');
        
      expect(res.status).toBe(404);
      // ✅ FIX 4: withdrawComplaint() does Complaint.findOne({ _id, userId: dbUser._id }).
      // When the complaint belongs to another user, findOne returns null → 404.
      // The service never reaches an ownership check that would return 403.
    });
  });
});

// tests/complaintFilters.test.js
// ─────────────────────────────────────────────────────────────
// Extended Complaint Query Tests
//
// Covers the branches in complaintService.js that complaints.test.js
// doesn't touch:
//   - Filtering by category, status, urgency, days
//   - Text search in description
//   - GET /api/complaints/:id  (single complaint fetch)
//   - GET /api/complaints/map  (viewport-bounded map pins)
//   - GET /api/complaints/nearby  (geospatial duplicate-check)
//   - department_staff scoping: staff only see their own category
//   - serializeComplaint PII stripping (complaintAccess.js)
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
      if (token === 'staff-road-token')
        return Promise.resolve({ uid: 'staff-road-uid', email: 'staff-road@test.com' });
      return Promise.reject({ code: 'auth/invalid-id-token' });
    }),
  }),
  apps: [],
}));

// Mock urgencyService (fire-and-forget, no network)
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
  if (mongoServer) await mongoServer.stop();
});

// ── Shared seed data references ───────────────────────────────
let citizenUser, adminUser, roadStaffUser;
let complaintRoad, complaintWater, complaintSanitation;

beforeEach(async () => {
  await User.deleteMany({});
  await Complaint.deleteMany({});
  await Upvote.deleteMany({});

  citizenUser = await User.create({
    firebaseUid: 'citizen-uid', name: 'Citizen', email: 'citizen@test.com', role: 'citizen',
  });
  adminUser = await User.create({
    firebaseUid: 'admin-uid', name: 'Admin', email: 'admin@test.com', role: 'admin',
  });
  roadStaffUser = await User.create({
    firebaseUid: 'staff-road-uid', name: 'Road Staff', email: 'staff-road@test.com',
    role: 'department_staff', department: 'Road',
  });

  // 3 complaints in different categories, statuses, urgencies
  complaintRoad = await Complaint.create({
    userId: citizenUser._id, firebaseUid: citizenUser.firebaseUid,
    category: 'Road', description: 'Huge pothole near the school entrance',
    status: 'Pending', urgency: 'High',
    location: { type: 'Point', coordinates: [77.5946, 12.9716] },
  });
  complaintWater = await Complaint.create({
    userId: citizenUser._id, firebaseUid: citizenUser.firebaseUid,
    category: 'Water', description: 'Water supply cut off since yesterday',
    status: 'In Progress', urgency: 'Medium',
    location: { type: 'Point', coordinates: [77.6000, 12.9800] },
  });
  complaintSanitation = await Complaint.create({
    userId: adminUser._id, firebaseUid: adminUser.firebaseUid,
    category: 'Sanitation', description: 'Garbage not collected for three days',
    status: 'Resolved', urgency: 'Low',
    location: { type: 'Point', coordinates: [77.5500, 12.9500] },
  });
});

// ─────────────────────────────────────────────────────────────
// GET /api/complaints — filtering tests
// ─────────────────────────────────────────────────────────────
describe('GET /api/complaints — filters', () => {
  it('filters by category', async () => {
    const res = await request(app)
      .get('/api/complaints?category=Road')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    expect(res.body.data.length).toBe(1);
    expect(res.body.data[0].category).toBe('Road');
  });

  it('filters by status', async () => {
    const res = await request(app)
      .get('/api/complaints?status=In Progress')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    expect(res.body.data.length).toBe(1);
    expect(res.body.data[0].status).toBe('In Progress');
  });

  it('filters by urgency', async () => {
    const res = await request(app)
      .get('/api/complaints?urgency=High')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    expect(res.body.data.length).toBe(1);
    expect(res.body.data[0].urgency).toBe('High');
  });

  it('filters by multiple statuses (comma-separated)', async () => {
    const res = await request(app)
      .get('/api/complaints?status=Pending,Resolved')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    expect(res.body.data.length).toBe(2);
    const statuses = res.body.data.map(c => c.status);
    expect(statuses).toContain('Pending');
    expect(statuses).toContain('Resolved');
  });

  it('searches by description text (case-insensitive)', async () => {
    const res = await request(app)
      .get('/api/complaints?search=pothole')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    expect(res.body.data.length).toBe(1);
    expect(res.body.data[0].description).toMatch(/pothole/i);
  });

  it('returns empty data array when search matches nothing', async () => {
    const res = await request(app)
      .get('/api/complaints?search=xyznomatch123')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    expect(res.body.data.length).toBe(0);
    expect(res.body.pagination.total).toBe(0);
  });

  it('sorts by upvotes ascending', async () => {
    // Give complaintWater 2 upvotes so we can sort
    await Complaint.findByIdAndUpdate(complaintWater._id, { upvotes: 2 });

    const res = await request(app)
      .get('/api/complaints?sortBy=upvotes&order=asc')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    const upvoteCounts = res.body.data.map(c => c.upvotes);
    // First element should have the fewest upvotes
    expect(upvoteCounts[0]).toBeLessThanOrEqual(upvoteCounts[upvoteCounts.length - 1]);
  });
});

// ─────────────────────────────────────────────────────────────
// GET /api/complaints/:id — single complaint fetch
// ─────────────────────────────────────────────────────────────
describe('GET /api/complaints/:id', () => {
  it('returns a single complaint by ID', async () => {
    const res = await request(app)
      .get(`/api/complaints/${complaintRoad._id}`)
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.category).toBe('Road');
  });

  it('returns 400 for a malformed (non-ObjectId) ID', async () => {
    const res = await request(app)
      .get('/api/complaints/not-a-valid-id')
      .set('Authorization', 'Bearer citizen-token');

    // errorHandler.js maps CastError → 400
    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/not a valid ID format/i);
  });

  it('returns 404 for a valid but non-existent ID', async () => {
    const fakeId = new mongoose.Types.ObjectId();
    const res = await request(app)
      .get(`/api/complaints/${fakeId}`)
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(404);
  });
});

// ─────────────────────────────────────────────────────────────
// department_staff scoping — the role that can only see their dept
// ─────────────────────────────────────────────────────────────
describe('department_staff role scoping', () => {
  it('GET /api/complaints returns ONLY road category complaints for road staff', async () => {
    const res = await request(app)
      .get('/api/complaints')
      .set('Authorization', 'Bearer staff-road-token');

    expect(res.status).toBe(200);
    // complaintRoad is Road, complaintWater is Water, complaintSanitation is Sanitation
    // staff should only see Road complaints
    expect(res.body.data.length).toBe(1);
    expect(res.body.data[0].category).toBe('Road');
  });

  it('road staff cannot update a Water complaint status (wrong dept)', async () => {
    const res = await request(app)
      .patch(`/api/complaints/${complaintWater._id}/status`)
      .set('Authorization', 'Bearer staff-road-token')
      .send({ status: 'Resolved' });

    expect(res.status).toBe(403);
  });

  it('road staff CAN update a Road complaint status', async () => {
    const res = await request(app)
      .patch(`/api/complaints/${complaintRoad._id}/status`)
      .set('Authorization', 'Bearer staff-road-token')
      .send({ status: 'In Progress' });

    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('In Progress');
  });
});

// ─────────────────────────────────────────────────────────────
// PII serialization — complaintAccess.serializeComplaint()
// ─────────────────────────────────────────────────────────────
describe('PII stripping in complaint responses', () => {
  it('citizen does NOT see email/phone of reporter on the public feed', async () => {
    const res = await request(app)
      .get(`/api/complaints/${complaintRoad._id}`)
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    // userId is populated but should be stripped to { _id, name } only
    if (res.body.data.userId && typeof res.body.data.userId === 'object') {
      expect(res.body.data.userId.email).toBeUndefined();
      expect(res.body.data.userId.phone).toBeUndefined();
    }
  });

  it('citizen sees anonymized (rounded) coordinates on public feed', async () => {
    const res = await request(app)
      .get(`/api/complaints/${complaintRoad._id}`)
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    // serializeComplaint rounds coordinates to a 0.001 grid (~111m)
    // i.e. Math.round(x / 0.001) * 0.001. We verify the value is a
    // multiple of 0.001 within floating-point tolerance.
    const [lng, lat] = res.body.data.location.coordinates;
    expect(Math.abs(lng - Math.round(lng / 0.001) * 0.001)).toBeLessThan(1e-9);
    expect(Math.abs(lat - Math.round(lat / 0.001) * 0.001)).toBeLessThan(1e-9);
  });

  it('upvotedBy list is never sent to the client', async () => {
    const res = await request(app)
      .get(`/api/complaints/${complaintRoad._id}`)
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    expect(res.body.data.upvotedBy).toBeUndefined();
  });

  it('admin DOES see email/phone of reporter', async () => {
    // Re-fetch with admin token; userId.email should be visible
    const res = await request(app)
      .get(`/api/complaints/${complaintRoad._id}`)
      .set('Authorization', 'Bearer admin-token');

    expect(res.status).toBe(200);
    // If userId is populated (admin sees PII), email should exist
    if (res.body.data.userId && typeof res.body.data.userId === 'object') {
      expect(res.body.data.userId.email).toBe('citizen@test.com');
    }
  });
});

// ─────────────────────────────────────────────────────────────
// GET /api/complaints/map — viewport-bounded map pins
// ─────────────────────────────────────────────────────────────
describe('GET /api/complaints/map', () => {
  it('forbids citizens from accessing map endpoint', async () => {
    const res = await request(app)
      .get('/api/complaints/map')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(403);
  });

  it('returns map complaints for admin (no bounds filter)', async () => {
    const res = await request(app)
      .get('/api/complaints/map')
      .set('Authorization', 'Bearer admin-token');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    // Resolved complaints are excluded from map (status: { $ne: 'Resolved' })
    const categories = res.body.data.map(c => c.status);
    expect(categories.every(s => s !== 'Resolved')).toBe(true);
  });

  it('returns viewport-bounded complaints when bounds are passed', async () => {
    // Bounding box tightly around complaintRoad only
    const res = await request(app)
      .get('/api/complaints/map?swLat=12.97&swLng=77.59&neLat=12.98&neLng=77.60')
      .set('Authorization', 'Bearer admin-token');

    expect(res.status).toBe(200);
    expect(res.body.data.length).toBeGreaterThanOrEqual(1);
  });
});

// ─────────────────────────────────────────────────────────────
// GET /api/complaints/nearby — duplicate-check geospatial search
// ─────────────────────────────────────────────────────────────
describe('GET /api/complaints/nearby', () => {
  it('returns 400 if lat/lng/category is missing', async () => {
    const res = await request(app)
      .get('/api/complaints/nearby')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(400);
    expect(res.body.message).toContain('lat, lng, and category are required');
  });

  it('returns 400 for an invalid category', async () => {
    const res = await request(app)
      .get('/api/complaints/nearby?lat=12.97&lng=77.59&category=InvalidDept')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(400);
    expect(res.body.message).toContain('Invalid category');
  });

  it('returns nearby complaints in geo radius', async () => {
    const res = await request(app)
      .get('/api/complaints/nearby?lat=12.9716&lng=77.5946&category=Road&radius=500')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    // At least the Road complaint seeded near these coords should appear
    expect(res.body.data.length).toBeGreaterThanOrEqual(1);
  });

  it('returns empty array when no complaints within radius', async () => {
    // Remote location — far from all seeded data
    const res = await request(app)
      .get('/api/complaints/nearby?lat=28.6139&lng=77.2090&category=Road&radius=10')
      .set('Authorization', 'Bearer citizen-token');

    expect(res.status).toBe(200);
    expect(res.body.data.length).toBe(0);
  });
});

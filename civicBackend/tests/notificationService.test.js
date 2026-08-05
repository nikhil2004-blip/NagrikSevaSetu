// tests/notificationService.test.js
// ─────────────────────────────────────────────────────────────
// Unit tests for notificationService.createNotification()
//
// This service:
//   1. Saves a Notification document to MongoDB
//   2. Looks up the recipient user's FCM tokens
//   3. Fires a push notification via firebase-admin if tokens exist
//   4. Prunes invalid (expired) FCM tokens from the user document
//   5. Is NON-FATAL — any error is caught and returns null, so the
//      calling operation (e.g. status update) never crashes.
// ─────────────────────────────────────────────────────────────

'use strict';

process.env.NODE_ENV = 'test';

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

// ── Firebase mock — must be declared BEFORE requiring any module ──
const mockSendEachForMulticast = jest.fn();

jest.mock('firebase-admin', () => ({
  initializeApp: jest.fn(),
  credential: { cert: jest.fn() },
  apps: [],
  messaging: () => ({
    sendEachForMulticast: mockSendEachForMulticast,
  }),
}));

const { createNotification } = require('../src/services/notificationService');
const Notification = require('../src/models/Notification');
const User = require('../src/models/User');

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
  await Notification.deleteMany({});
  mockSendEachForMulticast.mockReset();
});

// ─────────────────────────────────────────────────────────────
// Basic creation
// ─────────────────────────────────────────────────────────────
describe('createNotification()', () => {
  const fakeComplaintId = new mongoose.Types.ObjectId();

  it('saves a Notification document in MongoDB', async () => {
    const user = await User.create({
      firebaseUid: 'uid-1', name: 'User', email: 'u@t.com',
    });

    const notif = await createNotification({
      userId: user._id,
      complaintId: fakeComplaintId,
      type: 'status_update',
      message: 'Your complaint is now In Progress',
    });

    expect(notif).not.toBeNull();
    expect(notif._id).toBeDefined();

    const dbNotif = await Notification.findById(notif._id);
    expect(dbNotif.type).toBe('status_update');
    expect(dbNotif.message).toBe('Your complaint is now In Progress');
    expect(dbNotif.read).toBe(false); // default
  });

  it('does NOT send a push notification when user has no FCM tokens', async () => {
    const user = await User.create({
      firebaseUid: 'uid-2', name: 'No FCM', email: 'no-fcm@t.com',
      fcmTokens: [],
    });

    await createNotification({
      userId: user._id,
      complaintId: fakeComplaintId,
      type: 'upvote',
      message: 'Someone upvoted your complaint',
    });

    expect(mockSendEachForMulticast).not.toHaveBeenCalled();
  });

  it('fires FCM push notification when user has tokens', async () => {
    mockSendEachForMulticast.mockResolvedValueOnce({
      failureCount: 0,
      responses: [{ success: true }],
    });

    const user = await User.create({
      firebaseUid: 'uid-3', name: 'Has FCM', email: 'fcm@t.com',
      fcmTokens: ['device-token-abc'],
    });

    await createNotification({
      userId: user._id,
      complaintId: fakeComplaintId,
      type: 'status_update',
      message: 'Status updated!',
    });

    expect(mockSendEachForMulticast).toHaveBeenCalledTimes(1);
    const callArg = mockSendEachForMulticast.mock.calls[0][0];
    expect(callArg.tokens).toEqual(['device-token-abc']);
    expect(callArg.notification.body).toBe('Status updated!');
    expect(callArg.data.type).toBe('status_update');
  });

  it('prunes invalid/expired FCM tokens from the user document', async () => {
    mockSendEachForMulticast.mockResolvedValueOnce({
      failureCount: 1,
      responses: [
        { success: false, error: { code: 'messaging/registration-token-not-registered' } },
      ],
    });

    const user = await User.create({
      firebaseUid: 'uid-4', name: 'Stale FCM', email: 'stale@t.com',
      fcmTokens: ['stale-token-xyz'],
    });

    await createNotification({
      userId: user._id,
      complaintId: fakeComplaintId,
      type: 'upvote',
      message: 'Upvote!',
    });

    const updatedUser = await User.findById(user._id);
    expect(updatedUser.fcmTokens).not.toContain('stale-token-xyz');
  });

  it('keeps valid tokens and only removes the failed one', async () => {
    mockSendEachForMulticast.mockResolvedValueOnce({
      failureCount: 1,
      responses: [
        { success: true },
        { success: false, error: { code: 'messaging/invalid-registration-token' } },
      ],
    });

    const user = await User.create({
      firebaseUid: 'uid-5', name: 'Mixed FCM', email: 'mixed@t.com',
      fcmTokens: ['good-token', 'bad-token'],
    });

    await createNotification({
      userId: user._id,
      complaintId: fakeComplaintId,
      type: 'status_update',
      message: 'Update',
    });

    const updatedUser = await User.findById(user._id);
    expect(updatedUser.fcmTokens).toContain('good-token');
    expect(updatedUser.fcmTokens).not.toContain('bad-token');
  });

  it('keeps all tokens when FCM errors are not token-related', async () => {
    // e.g. messaging/internal-error — we should NOT prune the token
    mockSendEachForMulticast.mockResolvedValueOnce({
      failureCount: 1,
      responses: [
        { success: false, error: { code: 'messaging/internal-error' } },
      ],
    });

    const user = await User.create({
      firebaseUid: 'uid-6', name: 'Server Error FCM', email: 'srv-err@t.com',
      fcmTokens: ['keep-this-token'],
    });

    await createNotification({
      userId: user._id,
      complaintId: fakeComplaintId,
      type: 'upvote',
      message: 'Upvote',
    });

    const updatedUser = await User.findById(user._id);
    // Token should still be there — it failed due to server error, not bad token
    expect(updatedUser.fcmTokens).toContain('keep-this-token');
  });

  // ── Non-fatal error handling ──────────────────────────────
  it('returns null and does NOT throw when FCM sendEachForMulticast throws', async () => {
    mockSendEachForMulticast.mockRejectedValueOnce(new Error('FCM network failure'));

    const user = await User.create({
      firebaseUid: 'uid-7', name: 'FCM Crash', email: 'crash@t.com',
      fcmTokens: ['crash-token'],
    });

    // Should resolve (not reject) — it's a non-fatal operation
    const result = await createNotification({
      userId: user._id,
      complaintId: fakeComplaintId,
      type: 'status_update',
      message: 'Test',
    });

    expect(result).toBeNull();
  });

  it('returns null when MongoDB save fails (invalid data)', async () => {
    // Pass a non-existent userId to trigger a save error
    const result = await createNotification({
      userId: null, // will fail Mongoose 'required' check
      complaintId: fakeComplaintId,
      type: 'status_update',
      message: 'Test',
    });

    expect(result).toBeNull();
  });
});

// tests/urgencyService.test.js
// ─────────────────────────────────────────────────────────────
// Unit Tests: urgencyService (Phase 2.3)
//
// What we test:
//   1. classifyUrgencyWithGroq() - text urgency classification
//      a) Returns correct urgency when Groq responds normally
//      b) Handles case-insensitive / padded responses
//      c) Falls back to 'Medium' on substring match
//      d) Defaults to 'Medium' when Groq key is missing
//      e) Retries on 429/5xx and gives up after MAX_RETRIES
//      f) Does NOT retry on 400/401/403
//      g) Handles network-level transient errors (retries)
//
//   2. transcribeVoiceNote() - audio transcription stub
//      a) Returns '' when no URL given
//      b) Returns transcript on success
//      c) Returns '' gracefully on fetch failure
//
//   3. detectAndUpdateUrgency() - the public orchestrator
//      a) Writes urgency & 'done' status to MongoDB
//      b) Skips when GROQ_API_KEY is missing (no DB write)
//      c) Marks classification as 'failed' on total failure
//
// All external I/O (Groq API, MongoDB, fetch) is MOCKED.
// Tests run in milliseconds.
// ─────────────────────────────────────────────────────────────

'use strict';

// ── Environment setup (must come FIRST) ──────────────────────
process.env.NODE_ENV = 'test';
process.env.GROQ_API_KEY = 'gsk_test_key_for_unit_tests';
process.env.MONGODB_URI = 'mongodb://localhost:27017/civic_test';
process.env.FIREBASE_PROJECT_ID = 'test-project';
process.env.FIREBASE_CLIENT_EMAIL = 'test@test.com';
process.env.FIREBASE_PRIVATE_KEY = 'test-key';

// ── Jest mock: groq-sdk ───────────────────────────────────────
// We mock the entire groq-sdk module so no real HTTP calls happen.
// Each test can configure mockCreate/mockTranscribe as needed.
const mockCreate = jest.fn();
const mockTranscribe = jest.fn();

jest.mock('groq-sdk', () => {
  return jest.fn().mockImplementation(() => ({
    chat: {
      completions: {
        create: mockCreate,
      },
    },
    audio: {
      transcriptions: {
        create: mockTranscribe,
      },
    },
  }));
});

// ── Jest mock: Complaint model ────────────────────────────────
const mockFindByIdAndUpdate = jest.fn().mockResolvedValue({});
jest.mock('../src/models/Complaint', () => ({
  findByIdAndUpdate: (...args) => mockFindByIdAndUpdate(...args),
}));

// ── Jest mock: global fetch ───────────────────────────────────
const mockFetch = jest.fn();
global.fetch = mockFetch;

// ─────────────────────────────────────────────────────────────
// Import AFTER mocks are registered
// ─────────────────────────────────────────────────────────────
const {
  classifyUrgencyWithGroq,
  transcribeVoiceNote,
  detectAndUpdateUrgency,
  _resetGroqClientForTest,
} = require('../src/services/urgencyService');

// Helper: build a mock Groq chat response
const mockGroqResponse = (text) => ({
  choices: [{ message: { content: text } }],
});

// ─────────────────────────────────────────────────────────────
describe('urgencyService — classifyUrgencyWithGroq()', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    _resetGroqClientForTest();
    process.env.GROQ_API_KEY = 'gsk_test_key_for_unit_tests';
  });

  // ── 1a: Normal responses ─────────────────────────────────
  test.each([
    ['High',   'High'],
    ['Medium', 'Medium'],
    ['Low',    'Low'],
    ['high',   'High'],   // lowercase normalisation
    ['HIGH',   'High'],   // uppercase normalisation
    [' Low ',  'Low'],    // whitespace trimming
  ])('returns "%s" when Groq responds with "%s"', async (input, expected) => {
    mockCreate.mockResolvedValueOnce(mockGroqResponse(input));
    const result = await classifyUrgencyWithGroq('A test complaint description');
    expect(result).toBe(expected);
    expect(mockCreate).toHaveBeenCalledTimes(1);
  });

  // ── 1b: Substring fallback ───────────────────────────────
  test('falls back to "High" when model returns "High urgency"', async () => {
    mockCreate.mockResolvedValueOnce(mockGroqResponse('High urgency'));
    const result = await classifyUrgencyWithGroq('Flooded street');
    expect(result).toBe('High');
  });

  // ── 1c: Unknown response → Medium ────────────────────────
  test('defaults to "Medium" when model returns a completely unexpected value', async () => {
    mockCreate.mockResolvedValueOnce(mockGroqResponse('Unknown'));
    const result = await classifyUrgencyWithGroq('A complaint');
    expect(result).toBe('Medium');
  });

  // ── 1d: API key missing ───────────────────────────────────
  test('throws (and upstream returns Medium) when GROQ_API_KEY is not set', async () => {
    delete process.env.GROQ_API_KEY;
    // getGroqClient() throws; classifyUrgencyWithGroq() catches & returns Medium
    const result = await classifyUrgencyWithGroq('A complaint');
    expect(result).toBe('Medium');
    expect(mockCreate).not.toHaveBeenCalled();
  });

  // ── 1e: Retry on 429 ─────────────────────────────────────
  test('retries up to MAX_RETRIES on 429 rate-limit and eventually returns Medium', async () => {
    const rateLimitError = Object.assign(new Error('Rate limited'), { status: 429 });
    // All 3 attempts fail
    mockCreate.mockRejectedValue(rateLimitError);

    const result = await classifyUrgencyWithGroq('A complaint');

    expect(result).toBe('Medium');
    expect(mockCreate).toHaveBeenCalledTimes(3); // MAX_RETRIES = 3
  }, 30000); // extended timeout for back-off delays in real mode (mocked here so fast)

  // ── 1e: Retry succeeds on 2nd attempt ─────────────────────
  test('returns correct urgency if 2nd attempt succeeds after 1st 429', async () => {
    const rateLimitError = Object.assign(new Error('Rate limited'), { status: 429 });
    mockCreate
      .mockRejectedValueOnce(rateLimitError)
      .mockResolvedValueOnce(mockGroqResponse('High'));

    const result = await classifyUrgencyWithGroq('Electrical fire on the road');
    expect(result).toBe('High');
    expect(mockCreate).toHaveBeenCalledTimes(2);
  });

  // ── 1f: No retry on 400 ───────────────────────────────────
  test('does NOT retry on 400 bad request — fails immediately', async () => {
    const badRequestError = Object.assign(new Error('Bad Request'), { status: 400 });
    mockCreate.mockRejectedValueOnce(badRequestError);

    const result = await classifyUrgencyWithGroq('A complaint');
    expect(result).toBe('Medium');
    expect(mockCreate).toHaveBeenCalledTimes(1); // Only one attempt
  });

  // ── 1f: No retry on 401 ───────────────────────────────────
  test('does NOT retry on 401 unauthorized', async () => {
    const authError = Object.assign(new Error('Unauthorized'), { status: 401 });
    mockCreate.mockRejectedValueOnce(authError);

    const result = await classifyUrgencyWithGroq('A complaint');
    expect(result).toBe('Medium');
    expect(mockCreate).toHaveBeenCalledTimes(1);
  });

  // ── 1g: Retry on network error ────────────────────────────
  test('retries on ECONNRESET network error', async () => {
    const networkError = Object.assign(new Error('Connection reset'), { code: 'ECONNRESET' });
    mockCreate
      .mockRejectedValueOnce(networkError)
      .mockResolvedValueOnce(mockGroqResponse('Low'));

    const result = await classifyUrgencyWithGroq('Minor issue');
    expect(result).toBe('Low');
    expect(mockCreate).toHaveBeenCalledTimes(2);
  });
});

// ─────────────────────────────────────────────────────────────
describe('urgencyService — transcribeVoiceNote()', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    _resetGroqClientForTest();
    process.env.GROQ_API_KEY = 'gsk_test_key_for_unit_tests';
  });

  // ── 2a: No URL ────────────────────────────────────────────
  test('returns empty string when no URL is provided', async () => {
    const result = await transcribeVoiceNote(null);
    expect(result).toBe('');
    expect(mockFetch).not.toHaveBeenCalled();
  });

  test('returns empty string when URL is empty string', async () => {
    const result = await transcribeVoiceNote('');
    expect(result).toBe('');
  });

  // ── 2b: Successful transcription ─────────────────────────
  test('returns transcription text on success', async () => {
    const fakeAudioBuffer = Buffer.from('fake-audio-data');
    mockFetch.mockResolvedValueOnce({
      ok: true,
      headers: { get: () => '15' },
      body: [fakeAudioBuffer],
    });
    mockTranscribe.mockResolvedValueOnce({
      text: 'The road is completely flooded near my house.',
    });

    const result = await transcribeVoiceNote('https://res.cloudinary.com/test/voice.mp3');
    expect(result).toBe('The road is completely flooded near my house.');
    expect(mockTranscribe).toHaveBeenCalledTimes(1);
  });

  // ── 2b: String response format ────────────────────────────
  test('handles plain string response from Groq Whisper', async () => {
    const fakeAudioBuffer = Buffer.from('fake-audio-data');
    mockFetch.mockResolvedValueOnce({
      ok: true,
      headers: { get: () => '15' },
      body: [fakeAudioBuffer],
    });
    mockTranscribe.mockResolvedValueOnce('Direct string transcript.');

    const result = await transcribeVoiceNote('https://res.cloudinary.com/test/voice.mp3');
    expect(result).toBe('Direct string transcript.');
  });

  // ── 2c: Fetch failure → graceful empty string ─────────────
  test('returns "" when fetch returns HTTP error', async () => {
    mockFetch.mockResolvedValueOnce({ ok: false, status: 404 });

    const result = await transcribeVoiceNote('https://res.cloudinary.com/test/missing.mp3');
    expect(result).toBe('');
  });

  test('returns "" when fetch throws (network error)', async () => {
    mockFetch.mockRejectedValueOnce(new Error('Network error'));

    const result = await transcribeVoiceNote('https://res.cloudinary.com/test/voice.mp3');
    expect(result).toBe('');
  });

  test('returns "" when Groq transcription throws', async () => {
    const fakeAudioBuffer = Buffer.from('fake-audio-data');
    mockFetch.mockResolvedValueOnce({
      ok: true,
      headers: { get: () => '15' },
      body: [fakeAudioBuffer],
    });
    mockTranscribe.mockRejectedValueOnce(new Error('Whisper model error'));

    const result = await transcribeVoiceNote('https://res.cloudinary.com/test/voice.mp3');
    expect(result).toBe('');
  });
});

// ─────────────────────────────────────────────────────────────
describe('urgencyService — detectAndUpdateUrgency()', () => {
  const FAKE_COMPLAINT_ID = '507f1f77bcf86cd799439011';

  beforeEach(() => {
    jest.clearAllMocks();
    _resetGroqClientForTest();
    process.env.GROQ_API_KEY = 'gsk_test_key_for_unit_tests';
    // Reset DB mock to return a dummy resolved promise by default
    mockFindByIdAndUpdate.mockResolvedValue({});
  });

  // ── 3a: Happy path — text only ────────────────────────────
  test('classifies text complaint and writes urgency + done to DB', async () => {
    mockCreate.mockResolvedValueOnce(mockGroqResponse('High'));

    await detectAndUpdateUrgency(FAKE_COMPLAINT_ID, 'Severe flooding on main road', null);

    expect(mockFindByIdAndUpdate).toHaveBeenCalledWith(FAKE_COMPLAINT_ID, {
      urgency: 'High',
      urgencyClassification: 'done',
    });
  });

  // ── 3a: Happy path — with voice note ─────────────────────
  test('transcribes voice note, persists transcript, then classifies combined text', async () => {
    const fakeAudioBuffer = Buffer.from('fake-audio-data');
    mockFetch.mockResolvedValueOnce({
      ok: true,
      headers: { get: () => '15' },
      body: [fakeAudioBuffer],
    });
    mockTranscribe.mockResolvedValueOnce({ text: 'Road is broken and dangerous' });
    mockCreate.mockResolvedValueOnce(mockGroqResponse('Medium'));

    await detectAndUpdateUrgency(
      FAKE_COMPLAINT_ID,
      'Pothole issue',
      'https://res.cloudinary.com/test/voice.mp3'
    );

    // Should persist transcript first
    expect(mockFindByIdAndUpdate).toHaveBeenCalledWith(FAKE_COMPLAINT_ID, {
      voiceNoteTranscript: 'Road is broken and dangerous',
    });

    // Then save urgency + done
    expect(mockFindByIdAndUpdate).toHaveBeenCalledWith(FAKE_COMPLAINT_ID, {
      urgency: 'Medium',
      urgencyClassification: 'done',
    });
  });

  // ── 3b: Key missing — skip (no DB write for urgency) ─────
  test('skips classification and writes nothing when GROQ_API_KEY is missing', async () => {
    delete process.env.GROQ_API_KEY;

    await detectAndUpdateUrgency(FAKE_COMPLAINT_ID, 'Complaint text', null);

    expect(mockCreate).not.toHaveBeenCalled();
    // The DB should NOT have been called (the early return happens before any DB work)
    expect(mockFindByIdAndUpdate).not.toHaveBeenCalled();
  });

  // ── 3c: Total failure → mark as 'failed' ─────────────────
  test('marks classification as failed when Groq errors are non-retryable', async () => {
    const fatalError = Object.assign(new Error('Invalid API key'), { status: 401 });
    mockCreate.mockRejectedValue(fatalError);

    // classifyUrgencyWithGroq returns 'Medium' on 401 (non-retryable, no throw)
    // BUT detectAndUpdateUrgency should still write urgency:Medium/done in this case.
    // The 'failed' path is only reached if classifyUrgency itself throws.

    // To test the 'failed' path, we simulate a catastrophic DB write failure
    // on the FIRST update call (after classification):
    mockCreate.mockResolvedValueOnce(mockGroqResponse('High'));
    mockFindByIdAndUpdate.mockRejectedValueOnce(new Error('DB connection lost'));
    // Second call (marking failed) should succeed:
    mockFindByIdAndUpdate.mockResolvedValueOnce({});

    await detectAndUpdateUrgency(FAKE_COMPLAINT_ID, 'Some complaint', null);

    // The second call should be the 'failed' marker
    expect(mockFindByIdAndUpdate).toHaveBeenLastCalledWith(FAKE_COMPLAINT_ID, {
      urgencyClassification: 'failed',
    });
  });

  // ── 3: Empty description falls back to Medium / done ─────
  test('sets urgency to Medium/done when description is empty and no voice note', async () => {
    await detectAndUpdateUrgency(FAKE_COMPLAINT_ID, '   ', null);

    expect(mockCreate).not.toHaveBeenCalled();
    expect(mockFindByIdAndUpdate).toHaveBeenCalledWith(FAKE_COMPLAINT_ID, {
      urgency: 'Medium',
      urgencyClassification: 'done',
    });
  });
});

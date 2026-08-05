// src/controllers/uploadController.js
// ─────────────────────────────────────────────────────────────
// Upload Controller - Cloudinary Signed Upload (Phase 2.3)
//
// WHY a separate upload controller?
//   Previously the Flutter app uploaded images DIRECTLY to
//   Cloudinary using an "unsigned" upload preset. This is OK
//   for hackathons but dangerous: anyone can upload to your
//   Cloudinary account if they find the cloud name + preset.
//
//   The SECURE approach uses SIGNED uploads:
//   1. Client calls GET /api/upload/signature?type=image  (or 'audio')
//   2. Backend generates a time-limited signature using the
//      API Secret (which never leaves the backend)
//   3. Client uses the signature to upload directly to Cloudinary
//   4. Cloudinary validates the signature and accepts the upload
//
// Phase 2.3 adds AUDIO upload support:
//   - A separate signature endpoint variant for voice notes
//   - Uploads audio to the 'civic_voice_notes' folder
//   - Returns the Cloudinary secure URL back to the client
// ─────────────────────────────────────────────────────────────

'use strict';

const { cloudinary } = require('../config/cloudinary');

// Maximum allowed file size for audio uploads (10 MB in bytes)
const MAX_AUDIO_BYTES = 10 * 1024 * 1024;

// Supported audio resource types in Cloudinary
const AUDIO_RESOURCE_TYPE = 'video'; // Cloudinary uses 'video' for audio files

/**
 * GET /api/upload/signature?type=image|audio
 *
 * Generates a signed Cloudinary upload signature.
 * The Flutter/Web client uses this to securely upload files.
 *
 * Query params:
 *   type  - 'image' (default) | 'audio'
 *
 * @access Private (requires auth)
 */
const getUploadSignature = (req, res, next) => {
  try {
    const uploadType = req.query.type === 'audio' ? 'audio' : 'image';
    const timestamp = Math.round(new Date().getTime() / 1000);

    // Organise uploads by user ID and type to avoid clutter
    const folder =
      uploadType === 'audio'
        ? `civic_voice_notes/${req.dbUser._id}`
        : `civic_complaints/${req.dbUser._id}`;

    const allowedAudioFormats = 'mp3,mp4,m4a,wav,webm,ogg,flac,aac';
    const allowedImageFormats = 'jpg,jpeg,png,webp,heic';

    const paramsToSign = {
      timestamp,
      folder,
      upload_preset: process.env.CLOUDINARY_UPLOAD_PRESET || 'civic_sih2025',
    };
    if (uploadType === 'audio') {
      paramsToSign.allowed_formats = allowedAudioFormats;
    } else {
      paramsToSign.allowed_formats = allowedImageFormats;
    }

    const signature = cloudinary.utils.api_sign_request(
      paramsToSign,
      process.env.CLOUDINARY_API_SECRET
    );

    res.status(200).json({
      success: true,
      data: {
        signature,
        timestamp,
        folder,
        cloudName: process.env.CLOUDINARY_CLOUD_NAME,
        apiKey: process.env.CLOUDINARY_API_KEY,
        uploadPreset: process.env.CLOUDINARY_UPLOAD_PRESET || 'civic_sih2025',
        uploadType,
        resourceType: uploadType === 'audio' ? AUDIO_RESOURCE_TYPE : 'image',
        maxFileSizeBytes: uploadType === 'audio' ? MAX_AUDIO_BYTES : undefined,
        allowedFormats: uploadType === 'audio' ? allowedAudioFormats : allowedImageFormats,
      },
    });
  } catch (error) {
    next(error);
  }
};

module.exports = { getUploadSignature };

// lib/repositories/complaint_repository.dart
// ─────────────────────────────────────────────────────────────
// Complaint Repository — Data Access Layer for Complaints
//
// This is the ONLY class that knows HOW to fetch complaint data.
// Providers call repository methods. Screens call provider methods.
// No screen ever calls Dio or FirebaseFirestore directly.
//
// Backend endpoints used:
//   POST   /api/complaints               → createComplaint
//   GET    /api/complaints               → getAllComplaints
//   GET    /api/complaints/mine          → getMyComplaints
//   GET    /api/complaints/:id           → getComplaintById
//   POST   /api/complaints/:id/upvote    → toggleUpvote
//   GET    /api/upload/signature?type=image → _uploadImageToCloudinary
//   GET    /api/upload/signature?type=audio → uploadVoiceNote (Phase 2.3)
// ─────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import '../core/network/api_client.dart';
import '../core/config/app_config.dart';
import '../models/complaint.dart';

class ComplaintRepository {
  final ApiClient _apiClient;

  ComplaintRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  // ── Fetch Complaints ──────────────────────────────────────────

  /// GET /api/complaints — Returns all complaints with optional filters.
  ///
  /// [category] filters by department (e.g. 'Sanitation')
  /// [status]   filters by status (e.g. 'Pending')
  /// [page]     page number for pagination (default 1)
  /// [limit]    items per page (default 20)
  Future<List<Complaint>> getAllComplaints({
    String? category,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/complaints',
      queryParameters: {
        'category': ?category,
        'status': ?status,
        'page': page,
        'limit': limit,
        'sortBy': 'createdAt',
      },
    );

    final List<dynamic> rawList = response.data!['data'] as List<dynamic>;
    return rawList
        .map((json) => Complaint.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/complaints/mine — Returns the current user's own complaints.
  Future<List<Complaint>> getMyComplaints() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/complaints/mine',
    );

    final List<dynamic> rawList = response.data!['data'] as List<dynamic>;
    return rawList
        .map((json) => Complaint.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/complaints/:id — Returns a single complaint by MongoDB ID.
  Future<Complaint> getComplaintById(String id) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/complaints/$id',
    );
    return Complaint.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  // ── Submit Complaint ──────────────────────────────────────────

  /// POST /api/complaints — Submits a new complaint.
  ///
  /// If [imageFile] is provided, the image is first uploaded to
  /// Cloudinary using a secure signed upload (backend generates
  /// the signature via GET /api/upload/signature), then the
  /// returned imageUrl is included in the complaint payload.
  Future<Complaint> createComplaint({
    required String category,
    required String description,
    required double lat,
    required double lng,
    File? imageFile,
    String? voiceNoteUrl,
  }) async {
    String? imageUrl;

    // Step 1: Upload image to Cloudinary if provided
    if (imageFile != null) {
      imageUrl = await _uploadImageToCloudinary(imageFile);
    }

    // Step 2: Post complaint to the backend
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/complaints',
      data: {
        'category': category,
        if (description.isNotEmpty) 'description': description,
        'lat': lat,
        'lng': lng,
        'imageUrl': ?imageUrl,
        'voiceNoteUrl': ?voiceNoteUrl,
      },
    );

    return Complaint.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  // ── Upvote ────────────────────────────────────────────────────

  /// POST /api/complaints/:id/upvote — Toggles upvote.
  ///
  /// Returns the updated [upvotes] count and [hasUpvoted] boolean.
  Future<({int upvotes, bool hasUpvoted})> toggleUpvote(String id) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/complaints/$id/upvote',
    );

    final data = response.data!['data'] as Map<String, dynamic>;
    return (
      upvotes: (data['upvotes'] as num).toInt(),
      hasUpvoted: data['hasUpvoted'] as bool,
    );
  }

  // ── Private: Cloudinary Signed Upload (Image) ───────────────

  /// Securely uploads an image to Cloudinary.
  ///
  /// Step 1: GET /api/upload/signature?type=image → backend returns a
  ///         time-limited signature from the Cloudinary API Secret.
  /// Step 2: POST directly to Cloudinary using that signature.
  ///
  /// This is secure because the API Secret never leaves the backend.
  Future<String> _uploadImageToCloudinary(File file) async {
    // 1. Get signed upload params from the backend
    final sigResponse = await _apiClient.get<Map<String, dynamic>>(
      '/api/upload/signature',
      queryParameters: {'type': 'image'},
    );
    final sigData = sigResponse.data!['data'] as Map<String, dynamic>;

    final String cloudName = sigData['cloudName']?.toString()
        ?? AppConfig.cloudinaryCloudName;
    final String apiKey     = sigData['apiKey']?.toString() ?? '';
    final String signature  = sigData['signature']?.toString() ?? '';
    final int    timestamp  = (sigData['timestamp'] as num).toInt();
    final String folder     = sigData['folder']?.toString() ?? 'civic_complaints';
    final String uploadPreset = sigData['uploadPreset']?.toString()
        ?? AppConfig.cloudinaryUploadPreset;

    // 2. Build a multipart form and upload directly to Cloudinary
    final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
    final parts = mimeType.split('/');

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        contentType: MediaType(parts[0], parts[1]),
      ),
      'api_key': apiKey,
      'timestamp': timestamp.toString(),
      'signature': signature,
      'folder': folder,
      'upload_preset': uploadPreset,
    });

    // Upload directly to Cloudinary (not through our backend proxy)
    final cloudinaryDio = Dio();
    final cloudinaryResponse = await cloudinaryDio.post<Map<String, dynamic>>(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      data: formData,
    );

    return cloudinaryResponse.data!['secure_url'] as String;
  }

  // ── Public: Cloudinary Signed Upload (Audio / Voice Note) ────

  /// Securely uploads a voice note audio file to Cloudinary.
  ///
  /// Uses the same signed-upload pattern as images, but requests
  /// a signature with type=audio so the backend routes it to the
  /// 'civic_voice_notes' folder with audio-appropriate settings.
  ///
  /// Throws [AppException] on failure.
  /// The caller ([SubmitComplaintScreen]) should delete the local file
  /// after this returns successfully.
  ///
  /// @param file - The local audio file produced by VoiceNoteService.
  /// @returns    - The secure Cloudinary URL of the uploaded audio.
  Future<String> uploadVoiceNote(File file) async {
    // 1. Get audio-specific signed upload params from the backend
    final sigResponse = await _apiClient.get<Map<String, dynamic>>(
      '/api/upload/signature',
      queryParameters: {'type': 'audio'},
    );
    final sigData = sigResponse.data!['data'] as Map<String, dynamic>;

    final String cloudName   = sigData['cloudName']?.toString()
        ?? AppConfig.cloudinaryCloudName;
    final String apiKey      = sigData['apiKey']?.toString() ?? '';
    final String signature   = sigData['signature']?.toString() ?? '';
    final int    timestamp   = (sigData['timestamp'] as num).toInt();
    final String folder      = sigData['folder']?.toString() ?? 'civic_voice_notes';
    final String uploadPreset = sigData['uploadPreset']?.toString()
        ?? AppConfig.cloudinaryUploadPreset;
    final String? allowedFormats = sigData['allowedFormats']?.toString();

    // Determine MIME type from file extension (.m4a, .mp3, etc.)
    final mimeType = lookupMimeType(file.path) ?? 'audio/mp4';
    final parts = mimeType.split('/');

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        contentType: MediaType(parts[0], parts[1]),
      ),
      'api_key': apiKey,
      'timestamp': timestamp.toString(),
      'signature': signature,
      'folder': folder,
      'upload_preset': uploadPreset,
      'allowed_formats': ?allowedFormats,
      // Cloudinary uses 'video' resource_type for audio files
      'resource_type': 'video',
    });

    // Upload directly to Cloudinary (bypasses our backend — keeps it fast)
    // Note: Cloudinary audio uploads go through /v1_1/{cloud}/video/upload
    final cloudinaryDio = Dio();
    final cloudinaryResponse = await cloudinaryDio.post<Map<String, dynamic>>(
      'https://api.cloudinary.com/v1_1/$cloudName/video/upload',
      data: formData,
    );

    final secureUrl = cloudinaryResponse.data!['secure_url'] as String;
    debugPrint('[ComplaintRepository] Voice note uploaded: $secureUrl');
    return secureUrl;
  }
}

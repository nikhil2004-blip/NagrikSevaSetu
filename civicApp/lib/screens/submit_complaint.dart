// lib/screens/submit_complaint.dart
// ─────────────────────────────────────────────────────────────
// Submit Complaint Screen (Phase 2.3 — Voice Note Support)
//
// What's new in Phase 2.3:
//   - A voice note recorder section below the image picker.
//   - Citizens can record a voice note (up to 2 minutes) instead
//     of (or in addition to) typing a long description.
//   - The recorded audio is uploaded to Cloudinary via the backend
//     signed-upload pipeline, then the secure URL is attached to
//     the complaint submission payload.
//   - On the backend, Groq Whisper transcribes the audio and the
//     transcript is used (combined with the text description) for
//     more accurate AI urgency classification.
// ─────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/complaint_provider.dart';
import '../services/location_service.dart';
import '../services/voice_note_service.dart';

class SubmitComplaintScreen extends StatefulWidget {
  final String initialCategory;
  final File? recoveredImage;
  final String? recoveredDesc;

  const SubmitComplaintScreen({
    super.key,
    required this.initialCategory,
    this.recoveredImage,
    this.recoveredDesc,
  });

  @override
  State<SubmitComplaintScreen> createState() => _SubmitComplaintScreenState();
}

class _SubmitComplaintScreenState extends State<SubmitComplaintScreen>
    with SingleTickerProviderStateMixin {
  // ── Form state ────────────────────────────────────────────────
  final _descController = TextEditingController();
  final LocationService _locationService = LocationService();
  File? _imageFile;

  // ── Voice note state (Phase 2.3) ─────────────────────────────
  final VoiceNoteService _voiceService = VoiceNoteService();
  File? _recordedAudioFile;
  bool _isRecording = false;
  bool _isUploadingAudio = false;
  Duration _recordingDuration = Duration.zero;

  late AnimationController _recordingPulseController;

  static const Duration _maxRecordingDuration = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _recordingPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    if (widget.recoveredDesc != null) {
      _descController.text = widget.recoveredDesc!;
    }
    if (widget.recoveredImage != null) {
      _imageFile = widget.recoveredImage;
    }

    _descController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _descController.dispose();
    _voiceService.dispose();
    _recordingPulseController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Choose Photo Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.camera_alt_outlined, color: Theme.of(context).colorScheme.primary),
              ),
              title: const Text('Camera'),
              subtitle: const Text('Capture a new photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.photo_library_outlined, color: Theme.of(context).colorScheme.secondary),
              ),
              title: const Text('Gallery'),
              subtitle: const Text('Choose from your device'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    if (source == ImageSource.camera) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pending_complaint', true);
        await prefs.setString('pending_category', widget.initialCategory);
        await prefs.setString('pending_desc', _descController.text);
      } catch (e) {
        debugPrint('Failed to save state: $e');
      }
    }

    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (picked != null && mounted) {
        setState(() => _imageFile = File(picked.path));
      }
    } catch (e) {
      debugPrint("Image picker error: $e");
      if (mounted) {
        _showSnack("Could not capture image. Try again.", isError: true);
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      setState(() => _isRecording = false);
      _recordingPulseController.stop();

      final audioFile = await _voiceService.stopRecording();
      if (audioFile != null && mounted) {
        setState(() => _recordedAudioFile = audioFile);
        _showSnack('Voice note recorded successfully ✅', isError: false);
      } else {
        _showSnack('Recording failed — please try again', isError: true);
      }
    } else {
      if (_recordedAudioFile != null) {
        final confirmed = await _showReplaceRecordingDialog();
        if (!confirmed || !mounted) return;
        await _voiceService.deleteLocalFile(_recordedAudioFile!);
        setState(() => _recordedAudioFile = null);
      }

      final started = await _voiceService.startRecording();
      if (!mounted) return;
      if (!started) {
        _showSnack(
          'Microphone permission denied. Please allow access in Settings.',
          isError: true,
        );
        return;
      }

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      _recordingPulseController.repeat(reverse: true);

      _startDurationTracker();
    }
  }

  void _startDurationTracker() {
    final stopwatch = Stopwatch()..start();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isRecording) return false;

      setState(() => _recordingDuration = stopwatch.elapsed);

      if (stopwatch.elapsed >= _maxRecordingDuration) {
        _showSnack('Max recording time (2 min) reached. Recording stopped.');
        await _toggleRecording();
        return false;
      }
      return _isRecording;
    });
  }

  Future<void> _clearRecording() async {
    if (_recordedAudioFile != null) {
      await _voiceService.deleteLocalFile(_recordedAudioFile!);
    }
    setState(() {
      _recordedAudioFile = null;
      _recordingDuration = Duration.zero;
    });
  }

  Future<bool> _showReplaceRecordingDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Replace Recording?'),
            content: const Text(
              'You already have a voice note recorded. '
              'Do you want to discard it and record a new one?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Replace',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _submit() async {
    final descriptionText = _descController.text.trim();
    final hasVoiceNote = _recordedAudioFile != null;
    final hasText = descriptionText.isNotEmpty;

    if (!LocationService.isTestMode && _imageFile == null) {
      _showSnack('Please capture a photo. A photo is compulsory.');
      return;
    }

    if (!hasVoiceNote && (!hasText || descriptionText.length < 10)) {
      _showSnack('Please write a description (min 10 chars) or record a voice note.');
      return;
    }

    if (hasVoiceNote && hasText) {
      _showSnack('Please provide EITHER a text description OR a voice note, not both.');
      return;
    }

    if (_isRecording) {
      _showSnack('Please stop the recording before submitting.');
      return;
    }

    try {
      final provider = context.read<ComplaintProvider>();
      final position = await _locationService.getCurrentLocation();
      if (!mounted) return;

      String? voiceNoteUrl;

      if (_recordedAudioFile != null) {
        setState(() => _isUploadingAudio = true);

        try {
          voiceNoteUrl = await provider.uploadVoiceNote(_recordedAudioFile!);
          await _voiceService.deleteLocalFile(_recordedAudioFile!);
          if (mounted) setState(() => _recordedAudioFile = null);
        } catch (uploadError) {
          if (!mounted) return;
          setState(() => _isUploadingAudio = false);
          debugPrint('[SubmitComplaint] Voice upload failed: $uploadError');
          final proceed = await _showVoiceUploadFailureDialog();
          if (!proceed || !mounted) return;
          voiceNoteUrl = null;
        } finally {
          if (mounted) setState(() => _isUploadingAudio = false);
        }
      }

      final error = await provider.submitComplaint(
        category: widget.initialCategory,
        description: descriptionText,
        lat: position.latitude,
        lng: position.longitude,
        imageFile: _imageFile,
        voiceNoteUrl: voiceNoteUrl,
      );

      if (!mounted) return;

      if (error != null) {
        _showSnack('Submit failed: $error', isError: true);
      } else {
        _showSnack(
          voiceNoteUrl != null
              ? 'Complaint submitted with voice note ✅'
              : 'Complaint submitted successfully ✅',
          isError: false,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not get location: $e', isError: true);
    }
  }

  Future<bool> _showVoiceUploadFailureDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Voice Upload Failed'),
            content: const Text(
              'Your voice note could not be uploaded. '
              'Would you like to submit the complaint without it?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Submit Without Voice Note'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSnack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'sanitation': return Icons.cleaning_services_rounded;
      case 'water': return Icons.water_drop_rounded;
      case 'electrical': return Icons.electrical_services_rounded;
      case 'road': return Icons.route_rounded;
      default: return Icons.category_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitting = context.watch<ComplaintProvider>().isSubmitting;
    final isBusy = isSubmitting || _isUploadingAudio;
    final bool hasVoice = _recordedAudioFile != null;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Report Issue'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Category Card ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.8),
                    theme.colorScheme.primary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getCategoryIcon(widget.initialCategory),
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Category',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          widget.initialCategory,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Description ───────────────────────────────────────
            _buildSectionHeader('Description', Icons.description_rounded),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: hasVoice 
                    ? theme.colorScheme.surfaceContainerHighest
                    : theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasVoice 
                      ? theme.dividerColor.withOpacity(0.2) 
                      : theme.dividerColor.withOpacity(0.1),
                ),
              ),
              child: TextField(
                controller: _descController,
                enabled: !hasVoice,
                maxLength: 1000,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: hasVoice
                      ? 'Clear your voice note to type a description'
                      : 'Describe the issue in detail...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                  counterStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            
            // ── OR Divider ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                children: [
                  Expanded(child: Divider(color: theme.dividerColor.withOpacity(0.1))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: theme.dividerColor.withOpacity(0.1))),
                ],
              ),
            ),

            // ── Voice Note ────────────────────────────────────────
            _buildSectionHeader('Voice Note', Icons.mic_rounded),
            const SizedBox(height: 12),
            _buildVoiceNoteSection(),
            const SizedBox(height: 32),

            // ── Photo ─────────────────────────────────────────────
            _buildSectionHeader('Photo Evidence (Required)', Icons.camera_alt_rounded),
            const SizedBox(height: 12),
            _buildImageSection(),
            const SizedBox(height: 40),

            // ── Submit Button ─────────────────────────────────────
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: isBusy ? null : [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FilledButton(
                onPressed: isBusy ? null : _submit,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: isBusy
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _isUploadingAudio
                                ? 'Uploading Audio...'
                                : 'Submitting...',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded),
                          SizedBox(width: 8),
                          Text(
                            'Submit Report',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildImageSection() {
    if (_imageFile != null) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.file(
                _imageFile!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.cameraswitch_rounded, size: 18),
                      label: const Text('Retake'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _imageFile = null),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                      label: const Text('Remove', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: Colors.red.shade200),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _pickImage,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.04),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
            style: BorderStyle.solid,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_a_photo_rounded,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap to capture photo',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceNoteSection() {
    final bool hasText = _descController.text.trim().isNotEmpty;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isRecording ? Colors.red.withOpacity(0.04) : theme.cardColor,
        border: Border.all(
          color: _isRecording ? Colors.red.shade300 : theme.dividerColor.withOpacity(0.1),
          width: _isRecording ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isRecording ? [
          BoxShadow(
            color: Colors.red.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ] : [],
      ),
      child: Column(
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _recordingPulseController,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? Colors.red.withOpacity(0.1 + 0.2 * _recordingPulseController.value)
                          : theme.colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _isRecording ? Colors.red : theme.colorScheme.primary,
                      size: 24,
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isRecording
                          ? 'Recording...'
                          : _recordedAudioFile != null
                          ? 'Voice note attached'
                          : 'No voice note',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _isRecording ? Colors.red.shade700 : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (_isRecording)
                      Text(
                        _formatDuration(_recordingDuration),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.red.shade600,
                        ),
                      )
                    else if (_recordedAudioFile != null)
                      Text(
                        'Will be transcribed by AI',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                      )
                    else
                      Text(
                        'Speak instead of typing',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                  ],
                ),
              ),
              if (_recordedAudioFile != null && !_isRecording)
                IconButton(
                  onPressed: _clearRecording,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: Colors.red,
                  tooltip: 'Delete recording',
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: _isRecording
                ? ElevatedButton.icon(
                    onPressed: _toggleRecording,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop Recording'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: hasText ? null : _toggleRecording,
                    icon: const Icon(Icons.mic_rounded),
                    label: Text(
                      hasText
                          ? 'Clear text to record'
                          : _recordedAudioFile != null
                          ? 'Re-record Voice Note'
                          : 'Start Recording',
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s / 02:00';
  }
}


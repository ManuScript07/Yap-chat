import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/widgets/glass_button.dart';
import 'package:yap_chat/ui/widgets/widgets.dart';

class AttachmentSelection {
  const AttachmentSelection.images(this.imagePaths) : location = null;

  const AttachmentSelection.location(this.location) : imagePaths = null;

  final List<String>? imagePaths;
  final ChatLocation? location;
}

class ChatLocation {
  const ChatLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

Future<AttachmentSelection?> showAttachmentBottomSheet(
  BuildContext context, {
  required String chatId,
  required String peerName,
  String? initiallySelectedPath,
}) {
  return showModalBottomSheet<AttachmentSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _AttachmentBottomSheet(
      chatId: chatId,
      peerName: peerName,
      initiallySelectedPath: initiallySelectedPath,
    ),
  );
}

class _AttachmentBottomSheet extends StatefulWidget {
  const _AttachmentBottomSheet({
    required this.chatId,
    required this.peerName,
    this.initiallySelectedPath,
  });

  final String chatId;
  final String peerName;
  final String? initiallySelectedPath;

  @override
  State<_AttachmentBottomSheet> createState() => _AttachmentBottomSheetState();
}

class _AttachmentBottomSheetState extends State<_AttachmentBottomSheet> {
  final Set<String> _selectedImages = {};
  bool _isLocationLoading = false;

  // Список содержит только пути к локальным файлам (камера + галерея)
  final List<String> _localMedia = [];

  @override
  void initState() {
    super.initState();
    _loadRecentMedia();
  }

  void _loadRecentMedia() {
    final repository = context.read<ILocalMediaRepository>();
    final paths = repository
        .getRecentMediaPaths()
        .where((path) => File(path).existsSync())
        .toList();

    _localMedia.addAll(paths);
    final initiallySelectedPath = widget.initiallySelectedPath;
    if (initiallySelectedPath != null &&
        paths.contains(initiallySelectedPath)) {
      _selectedImages.add(initiallySelectedPath);
    }
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedImages.contains(path)) {
        _selectedImages.remove(path);
      } else {
        _selectedImages.add(path);
      }
    });
  }

  Future<void> _handleCameraAction() async {
    final repository = context.read<ILocalMediaRepository>();
    await repository.savePendingChatId(widget.chatId);

    final photoPath = await MediaService.takePhoto();
    await repository.clearPendingChatId();

    if (photoPath != null && mounted) {
      final persistentPath = await repository.persistMedia(photoPath);
      if (persistentPath == null || !mounted) return;

      setState(() {
        _localMedia.remove(persistentPath);
        _localMedia.insert(0, persistentPath);
        _selectedImages.add(persistentPath);
      });
      return;
    }

    final isPermanentlyDenied = await MediaService.isCameraPermanentlyDenied();
    if (isPermanentlyDenied && mounted) {
      showPermissionDeniedDialog(context);
    }
  }

  Future<void> _handleGalleryAction() async {
    final imagePath = await MediaService.pickFromGallery();

    if (imagePath != null && mounted) {
      final persistentPath = await context
          .read<ILocalMediaRepository>()
          .persistMedia(imagePath);
      if (persistentPath == null || !mounted) return;

      setState(() {
        _localMedia.remove(persistentPath);
        _localMedia.insert(0, persistentPath);
        _selectedImages.add(persistentPath);
      });
    }
  }

  Future<void> _deleteSelectedMedia() async {
    final selectedPaths = _selectedImages.toList();
    if (selectedPaths.isEmpty) return;

    final repository = context.read<ILocalMediaRepository>();
    for (final path in selectedPaths) {
      await repository.deleteMedia(path);
    }

    if (!mounted) return;
    setState(() {
      _localMedia.removeWhere(_selectedImages.contains);
      _selectedImages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final backgroundColor = context.colorScheme.primary;
    final l10n = context.l10n;
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    final hasMedia = _localMedia.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * (isLandscape ? 0.95 : 0.85),
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Drag Handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ActionButton(
                              icon: Icons.camera_alt_rounded,
                              label: l10n.chatActionCamera,
                              isLandscape: isLandscape,
                              onTap: _handleCameraAction,
                            ),
                            _ActionButton(
                              icon: Icons.image_rounded,
                              label: l10n.chatActionGallery,
                              isLandscape: isLandscape,
                              onTap: _handleGalleryAction,
                            ),
                            _ActionButton(
                              icon: Icons.near_me,
                              label: l10n.chatActionLocation,
                              isLandscape: isLandscape,
                              isLoading: _isLocationLoading,
                              onTap: _isLocationLoading
                                  ? null
                                  : _handleLocationAction,
                            ),
                          ],
                        ),
                      ),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: hasMedia
                            ? Column(
                                key: const ValueKey('recent_media_visible'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(height: isLandscape ? 12 : 20),
                                  SizedBox(
                                    height: isLandscape ? 100 : 138,
                                    child: ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _localMedia.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(width: 12),
                                      itemBuilder: (context, index) {
                                        final path = _localMedia[index];
                                        final isSelected = _selectedImages
                                            .contains(path);
                                        return KeyedSubtree(
                                          key: ValueKey('recent-media:$path'),
                                          child: _MediaCard(
                                            path: path,
                                            isSelected: isSelected,
                                            isLandscape: isLandscape,
                                            onTap: () => _toggleSelection(path),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox(
                                key: ValueKey('recent_media_hidden'),
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              // Кнопки удаления и отправки выбранных фото.
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  mediaQuery.padding.bottom + 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: isLandscape ? 44 : 52,
                        child: FilledButton(
                          onPressed: _selectedImages.isEmpty
                              ? null
                              : () => Navigator.of(context).pop(
                                  AttachmentSelection.images(
                                    _selectedImages.toList(),
                                  ),
                                ),
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.onSurface,
                            foregroundColor: backgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            _selectedImages.isEmpty
                                ? l10n.chatSelectFiles
                                : l10n.chatSendFiles(_selectedImages.length),
                            style: TextStyle(
                              fontSize: isLandscape ? 18 : 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_selectedImages.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      GlassButton(
                        icon: Icons.delete_outline_rounded,
                        onPressed: _deleteSelectedMedia,
                        size: isLandscape ? 44 : 52,
                        iconSize: 32,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLocationAction() async {
    if (_isLocationLoading) return;

    setState(() => _isLocationLoading = true);

    final locationRepository = context.read<ILocationRepository>();
    late final Position position;

    try {
      position = await locationRepository.getCurrentPosition();
    } on LocationServiceDisabledFailure {
      if (mounted) setState(() => _isLocationLoading = false);
      if (!mounted) return;

      await showPermissionDeniedDialog(
        context,
        title: context.l10n.locationDisabled,
        content: context.l10n.locationEnableDescription,
        onOpenSettings: locationRepository.openLocationSettings,
      );
      return;
    } on LocationPermissionPermanentlyDeniedFailure {
      if (mounted) setState(() => _isLocationLoading = false);
      if (!mounted) return;

      await showPermissionDeniedDialog(
        context,
        title: context.l10n.locationPermissionDenied,
        content: context.l10n.locationPermissionSettingsDescription,
        onOpenSettings: locationRepository.openAppSettings,
      );
      return;
    } on LocationPermissionDeniedFailure {
      if (mounted) setState(() => _isLocationLoading = false);
      if (!mounted) return;

      showAppSnackBar(
        context,
        message: context.l10n.locationPermissionDenied,
        type: SnackBarType.error,
      );
      return;
    } finally {
      if (mounted && _isLocationLoading) {
        setState(() => _isLocationLoading = false);
      }
    }

    if (!mounted) return;

    final confirmed = await showConfirmationDialog(
      context,
      title: context.l10n.locationConfirmationDescription,
      content: context.l10n.locationConfirmation(widget.peerName),
      confirmLabel: context.l10n.locationShare,
    );

    if (confirmed != true || !mounted) return;

    Navigator.of(context).pop(
      AttachmentSelection.location(
        ChatLocation(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLandscape = false,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isLandscape;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final size = isLandscape ? 64.0 : 88.0;
    final iconSize = isLandscape ? 24.0 : 32.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              child: isLoading
                  ? SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: colorScheme.primary,
                      ),
                    )
                  : Icon(icon, size: iconSize, color: colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: isLandscape ? 13 : 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.path,
    required this.isSelected,
    required this.onTap,
    this.isLandscape = false,
  });

  final String path;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final cardWidth = isLandscape ? 100.0 : 138.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: colorScheme.surface.withValues(alpha: 0.8),
            width: 4,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 420,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(child: Icon(Icons.broken_image_rounded));
                },
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : context.scaffoldBackgroundColor.withValues(
                            alpha: 0.5,
                          ),
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.surface, width: 2),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: colorScheme.surface,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

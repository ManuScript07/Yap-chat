import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/auth/widgets/profile_setup_widgets.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/widgets/profile_photo_crop_page.dart';
import 'package:yap_chat/features/profile/widgets/profile_photo_image.dart';
import 'package:yap_chat/ui/ui.dart';

Future<bool?> showProfileEditPage(
  BuildContext context, {
  required UserProfile profile,
}) {
  return Navigator.of(context).push<bool>(
    PageRouteBuilder<bool>(
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => _ProfileEditPage(profile: profile),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
            ),
        child: child,
      ),
    ),
  );
}

class _ProfileEditPage extends StatefulWidget {
  const _ProfileEditPage({required this.profile});

  final UserProfile profile;

  @override
  State<_ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<_ProfileEditPage> {
  static final _usernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');
  static final _usernameCharactersPattern = RegExp(r'^[a-z0-9_]*$');

  late final TextEditingController _usernameController;
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late List<ProfilePhoto> _photos;
  late ProfileGender _gender;
  late DateTime _birthDate;
  String? _usernameError;
  String? _nameError;
  String? _bioError;
  bool _submitted = false;
  bool _allowPop = false;
  bool _isPickingPhoto = false;
  String? _removingPhotoIdentity;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.profile.username);
    _nameController = TextEditingController(text: widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio);
    _photos = widget.profile.effectivePhotos.toList();
    _gender = widget.profile.gender;
    _birthDate = widget.profile.birthDate!;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  bool get _isDirty {
    if (_usernameController.text.trim() != widget.profile.username ||
        _nameController.text.trim() != widget.profile.displayName ||
        _bioController.text.trim() != widget.profile.bio ||
        _gender != widget.profile.gender ||
        _birthDate != widget.profile.birthDate ||
        _photos.length != widget.profile.effectivePhotos.length) {
      return true;
    }
    for (var index = 0; index < _photos.length; index++) {
      if (_photos[index].identity !=
          widget.profile.effectivePhotos[index].identity) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final mediaQuery = MediaQuery.of(context);
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          previous.isSubmitting != current.isSubmitting ||
          previous.failure != current.failure ||
          previous.profile != current.profile,
      listener: _onAuthState,
      child: PopScope(
        canPop: _allowPop || !_isDirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestClose();
        },
        child: Scaffold(
          backgroundColor: context.scaffoldBackgroundColor,
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              Positioned.fill(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    0,
                    130,
                    0,
                    mediaQuery.padding.bottom + mediaQuery.viewInsets.bottom,
                  ),
                  children: [
                    _photoStrip(
                      padding: EdgeInsets.fromLTRB(
                        16 + mediaQuery.padding.left,
                        0,
                        16 + mediaQuery.padding.right,
                        0,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16 + mediaQuery.padding.left,
                        0,
                        16 + mediaQuery.padding.right,
                        0,
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          OnboardingTextField(
                            controller: _usernameController,
                            label: context.l10n.profileUsernameLabel,
                            hint: context.l10n.profileUsernameHint,
                            maxLength: 24,
                            maxLines: 1,
                            tooLongText: context.l10n.authInputTooLong,
                            errorText: _usernameError,
                            autocorrect: false,
                            inputFormatters: [
                              TextInputFormatter.withFunction((
                                oldValue,
                                newValue,
                              ) {
                                return newValue.copyWith(
                                  text: newValue.text.toLowerCase(),
                                  selection: newValue.selection,
                                );
                              }),
                            ],
                            onChanged: (_) {
                              final value = _usernameController.text;
                              final error =
                                  value.length <= 24 &&
                                      !_usernameCharactersPattern.hasMatch(
                                        value,
                                      )
                                  ? context.l10n.authUsernameCharactersOnly
                                  : null;
                              if (_usernameError != error) {
                                setState(() => _usernameError = error);
                              }
                            },
                          ),
                          const SizedBox(height: 18),
                          OnboardingTextField(
                            controller: _nameController,
                            label: context.l10n.profileNameLabel,
                            hint: context.l10n.profileNameHint,
                            maxLength: 30,
                            maxLines: 1,
                            tooLongText: context.l10n.authInputTooLong,
                            errorText: _nameError,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => setState(() => _nameError = null),
                          ),
                          const SizedBox(height: 18),
                          OnboardingTextField(
                            controller: _bioController,
                            label: context.l10n.profileBioLabel,
                            hint: context.l10n.profileBioHint,
                            maxLength: 130,
                            maxLines: 4,
                            tooLongText: context.l10n.authInputTooLong,
                            errorText: _bioError,
                            textCapitalization: TextCapitalization.sentences,
                            keyboardType: TextInputType.multiline,
                            onChanged: (_) => setState(() => _bioError = null),
                          ),
                          const SizedBox(height: 22),
                          _valueRow(
                            label: context.l10n.profileGenderLabel,
                            value: _genderLabel(context, _gender),
                            onTap: _selectGender,
                          ),
                          _valueRow(
                            label: context.l10n.profileBirthDateLabel,
                            value: DateFormat(
                              'dd MMM yyyy',
                              Localizations.localeOf(context).languageCode,
                            ).format(_birthDate).replaceAll('.', ''),
                            onTap: _selectBirthDate,
                          ),
                          const SizedBox(height: 28),
                          Center(
                            child: SizedBox(
                              width: 230,
                              height: 58,
                              child: FilledButton(
                                onPressed: authState.isSubmitting
                                    ? null
                                    : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: context.colorScheme.primary,
                                  foregroundColor:
                                      context.colorScheme.onSurface,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                child: authState.isSubmitting
                                    ? SizedBox.square(
                                        dimension: 25,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: context.colorScheme.onSurface,
                                        ),
                                      )
                                    : Text(
                                        context.l10n.profileSave.toLowerCase(),
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: .5,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: PrimaryAppBar(
                  title: '',
                  titleWidget: Text(
                    context.l10n.profileEditTitle.toLowerCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleLargeFlex.copyWith(fontSize: 32),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoStrip({required EdgeInsets padding}) {
    return SizedBox(
      height: 128,
      child: DragBoundary(
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          buildDefaultDragHandles: false,
          dragBoundaryProvider: DragBoundary.forRectOf,
          onReorderStart: (_) {
            HapticFeedback.mediumImpact();
          },
          padding: padding,
          footer: Align(child: _addPhotoTile()),
          itemCount: _photos.length,
          onReorderItem: _reorderPhoto,
          proxyDecorator: (child, _, animation) => FadeTransition(
            opacity: animation.drive(Tween(begin: .76, end: 1)),
            child: ScaleTransition(
              scale: animation.drive(Tween(begin: 1.0, end: 1.03)),
              child: child,
            ),
          ),
          itemBuilder: (context, index) {
            final photo = _photos[index];
            final isRemoving = photo.identity == _removingPhotoIdentity;
            return TweenAnimationBuilder<double>(
              key: ValueKey('profile-edit-${photo.identity}'),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              tween: Tween(begin: 0, end: isRemoving ? 0 : 1),
              builder: (context, value, child) => SizedBox(
                width: 124 * value,
                child: Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: .94 + (.06 * value),
                    child: child,
                  ),
                ),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ReorderableDelayedDragStartListener(
                    index: index,
                    child: _photoTile(photo, index),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _photoTile(ProfilePhoto photo, int index) {
    final colorScheme = context.colorScheme;
    return SizedBox.square(
      dimension: 112,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ProfilePhotoImage(photo: photo),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton.filled(
              onPressed: _removingPhotoIdentity == null
                  ? () => _removePhoto(index)
                  : null,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(32),
                maximumSize: const Size.square(32),
                backgroundColor: context.colorScheme.surface,
                foregroundColor: context.colorScheme.onPrimary,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.close_rounded, size: 21),
            ),
          ),
          if (index == 0)
            Positioned(
              left: 7,
              bottom: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.scrim.withValues(alpha: .58),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  child: Text(
                    context.l10n.profileMainPhoto,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _addPhotoTile() {
    final isEnabled =
        _photos.length < 5 &&
        !_isPickingPhoto &&
        _removingPhotoIdentity == null;
    return SizedBox.square(
      dimension: 112,
      child: Material(
        color: context.colorScheme.onSurface.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isEnabled ? _pickPhoto : null,
          child: Center(
            child: SizedBox.square(
              dimension: 64,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isEnabled
                      ? context.colorScheme.primary
                      : context.colorScheme.outline,
                  shape: BoxShape.circle,
                ),
                child: _isPickingPhoto
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: context.colorScheme.onPrimary,
                        ),
                      )
                    : Icon(
                        _photos.length >= 5
                            ? Icons.check_rounded
                            : Icons.add_photo_alternate_outlined,
                        size: 34,
                        color: context.colorScheme.onPrimary,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _valueRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label.toLowerCase(),
                style: TextStyle(
                  color: context.colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: context.colorScheme.onSurfaceVariant,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: context.colorScheme.onSurfaceVariant,
              size: 32,
            ),
          ],
        ),
      ),
    );
  }

  void _reorderPhoto(int oldIndex, int newIndex) {
    if (oldIndex >= _photos.length || _removingPhotoIdentity != null) return;
    newIndex = newIndex.clamp(0, _photos.length - 1);
    setState(() {
      final photo = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, photo);
      _normalizePhotoPositions();
    });
  }

  Future<void> _removePhoto(int index) async {
    if (_removingPhotoIdentity != null || index >= _photos.length) return;
    final identity = _photos[index].identity;
    setState(() => _removingPhotoIdentity = identity);
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    setState(() {
      final currentIndex = _photos.indexWhere(
        (photo) => photo.identity == identity,
      );
      if (currentIndex >= 0) _photos.removeAt(currentIndex);
      _removingPhotoIdentity = null;
      _normalizePhotoPositions();
    });
  }

  void _normalizePhotoPositions() {
    _photos = [
      for (var index = 0; index < _photos.length; index++)
        _photos[index].copyWith(position: index),
    ];
  }

  Future<void> _pickPhoto() async {
    if (_isPickingPhoto || _photos.length >= 5) return;
    setState(() => _isPickingPhoto = true);
    try {
      final source = await MediaService.pickImageBytesFromGallery();
      if (!mounted || source == null) return;
      final cropped = await openProfilePhotoCropper(context, source);
      if (!mounted || cropped == null) return;
      setState(() {
        _photos.add(
          ProfilePhoto(
            position: _photos.length,
            bytes: cropped,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  Future<void> _selectGender() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final value = await showModalBottomSheet<ProfileGender>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: context.colorScheme.primary.withValues(alpha: .22),
      backgroundColor: context.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetContext.colorScheme.onSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                sheetContext.l10n.profileGenderTitle,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 22),
              ProfileGenderPicker(
                selectedGender: _gender == ProfileGender.unspecified
                    ? null
                    : _gender,
                resetLabel: sheetContext.l10n.authOnboardingReset,
                onSelected: (gender) {
                  Navigator.of(sheetContext).pop(gender);
                },
                onReset: () {
                  Navigator.of(sheetContext).pop(ProfileGender.unspecified);
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (value != null && mounted) setState(() => _gender = value);
  }

  Future<void> _selectBirthDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final value = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: context.colorScheme.primary.withValues(alpha: .22),
      backgroundColor: context.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: _BirthDateSheet(initialDate: _birthDate),
        ),
      ),
    );
    if (value != null && mounted) setState(() => _birthDate = value);
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    final username = _usernameController.text.trim().toLowerCase();
    final name = _nameController.text.trim();
    final bio = _bioController.text.trim();
    final valid =
        _usernamePattern.hasMatch(username) &&
        name.length >= 2 &&
        name.length <= 30 &&
        bio.length <= 130;
    setState(() {
      _usernameError = _usernameValidationError(context, username);
      _nameError = name.length >= 2 && name.length <= 30
          ? null
          : context.l10n.authNameInvalid;
      _bioError = bio.length <= 130 ? null : context.l10n.authInputTooLong;
    });
    if (!valid) return;

    _submitted = true;
    context.read<AuthBloc>().add(
      AuthProfileSubmitted(
        displayName: name,
        birthDate: _birthDate,
        gender: _gender,
        username: username,
        bio: bio,
        photos: _photos,
      ),
    );
  }

  void _onAuthState(BuildContext context, AuthState state) {
    final failure = state.failure;
    if (failure != null) {
      _submitted = false;
      if (failure == AuthFailure.usernameTaken ||
          failure == AuthFailure.invalidUsername) {
        setState(
          () => _usernameError = failure == AuthFailure.usernameTaken
              ? context.l10n.authUsernameTaken
              : _usernameValidationError(context, _usernameController.text),
        );
      } else {
        showAppSnackBar(
          context,
          message: context.l10n.authProfileSaveFailed,
          type: SnackBarType.error,
        );
      }
      context.read<AuthBloc>().add(const AuthFailureCleared());
      return;
    }
    if (_submitted && !state.isSubmitting) {
      _submitted = false;
      _popAfterUnlock(true);
    }
  }

  Future<void> _requestClose() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_isDirty) {
      _popAfterUnlock(false);
      return;
    }
    final shouldStay = await showConfirmationDialog(
      context,
      title: context.l10n.profileUnsavedTitle,
      content: context.l10n.profileUnsavedDescription,
      confirmLabel: context.l10n.profileStay,
      cancelLabel: context.l10n.profileDiscard,
    );
    if (!mounted || shouldStay != false) {
      return;
    }

    _popAfterUnlock(false);
  }

  void _popAfterUnlock(bool result) {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  String? _usernameValidationError(BuildContext context, String value) {
    final username = value.trim().toLowerCase();
    if (username.length > 24) return null;
    if (!_usernameCharactersPattern.hasMatch(username)) {
      return context.l10n.authUsernameCharactersOnly;
    }
    if (username.length < 3) return context.l10n.authUsernameTooShort;
    return null;
  }
}

class _BirthDateSheet extends StatefulWidget {
  const _BirthDateSheet({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_BirthDateSheet> createState() => _BirthDateSheetState();
}

class _BirthDateSheetState extends State<_BirthDateSheet> {
  late final TextEditingController _dayController;
  late final TextEditingController _monthController;
  late final TextEditingController _yearController;
  final _dayFocus = FocusNode();
  final _monthFocus = FocusNode();
  final _yearFocus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _dayController = TextEditingController(
      text: widget.initialDate.day.toString().padLeft(2, '0'),
    );
    _monthController = TextEditingController(
      text: widget.initialDate.month.toString().padLeft(2, '0'),
    );
    _yearController = TextEditingController(
      text: widget.initialDate.year.toString(),
    );
  }

  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    _dayFocus.dispose();
    _monthFocus.dispose();
    _yearFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: context.colorScheme.onSurface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.profileBirthDateTitle,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.authOnboardingBirthDateHint,
            style: TextStyle(
              color: context.colorScheme.onSurfaceVariant,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 26),
          OnboardingBirthDateFields(
            dayController: _dayController,
            monthController: _monthController,
            yearController: _yearController,
            dayFocusNode: _dayFocus,
            monthFocusNode: _monthFocus,
            yearFocusNode: _yearFocus,
            dayHint: context.l10n.authBirthDateDay,
            monthHint: context.l10n.authBirthDateMonth,
            yearHint: context.l10n.authBirthDateYear,
            onChanged: () => setState(() => _error = null),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: context.colorScheme.error)),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: context.colorScheme.primary,
                foregroundColor: context.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                context.l10n.profileSave,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final value = _parseDate();
    if (value == null) {
      setState(() => _error = context.l10n.authBirthDateInvalid);
      return;
    }
    Navigator.of(context).pop(value);
  }

  DateTime? _parseDate() {
    final day = int.tryParse(_dayController.text);
    final month = int.tryParse(_monthController.text);
    final year = int.tryParse(_yearController.text);
    if (day == null || month == null || year == null) return null;
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    final now = DateTime.now();
    final age =
        now.year -
        value.year -
        ((now.month < value.month ||
                (now.month == value.month && now.day < value.day))
            ? 1
            : 0);
    return age >= 14 ? value : null;
  }
}

String _genderLabel(BuildContext context, ProfileGender gender) {
  return switch (gender) {
    ProfileGender.male => context.l10n.profileGenderMale,
    ProfileGender.female => context.l10n.profileGenderFemale,
    ProfileGender.unspecified => context.l10n.profileGenderUnspecified,
  };
}

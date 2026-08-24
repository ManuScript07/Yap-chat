import 'dart:math' as math;
import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/auth/widgets/profile_setup_widgets.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  static const _stepCount = 5;

  late final PageController _pageController;
  late final TextEditingController _nameController;
  late final TextEditingController _dayController;
  late final TextEditingController _monthController;
  late final TextEditingController _yearController;
  late final TextEditingController _bioController;
  late final FocusNode _dayFocusNode;
  late final FocusNode _monthFocusNode;
  late final FocusNode _yearFocusNode;

  var _currentStep = 0;
  ProfileGender? _gender;
  Uint8List? _localAvatarBytes;
  var _isAvatarRemoved = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final state = context.read<AuthBloc>().state;
    final profile = state.profile;
    final birthDate = profile?.birthDate ?? state.session?.birthDate;

    _pageController = PageController();
    _nameController = TextEditingController(
      text: profile?.displayName ?? state.session?.displayName,
    );
    _dayController = TextEditingController(
      text: birthDate == null ? '' : birthDate.day.toString().padLeft(2, '0'),
    );
    _monthController = TextEditingController(
      text: birthDate == null ? '' : birthDate.month.toString().padLeft(2, '0'),
    );
    _yearController = TextEditingController(
      text: birthDate?.year.toString() ?? '',
    );
    _bioController = TextEditingController(text: profile?.bio);
    _dayFocusNode = FocusNode();
    _monthFocusNode = FocusNode();
    _yearFocusNode = FocusNode();
    _gender = profile?.gender == ProfileGender.unspecified
        ? null
        : profile?.gender;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    _bioController.dispose();
    _dayFocusNode.dispose();
    _monthFocusNode.dispose();
    _yearFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final mediaQuery = MediaQuery.of(context);
    final hideNavigationForKeyboard =
        mediaQuery.orientation == Orientation.landscape &&
        mediaQuery.viewInsets.bottom > 0;

    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          previous.failure != current.failure && current.failure != null,
      listener: (context, state) {
        setState(
          () => _validationError = _failureMessage(context, state.failure),
        );
        context.read<AuthBloc>().add(const AuthFailureCleared());
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = math.min(520.0, constraints.maxWidth);

              return Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: PageView(
                              controller: _pageController,
                              physics: const NeverScrollableScrollPhysics(),
                              onPageChanged: (index) {
                                setState(() {
                                  _currentStep = index;
                                  _validationError = null;
                                });
                              },
                              children: [
                                ProfileSetupStep(
                                  title: context.l10n.authOnboardingNameTitle,
                                  child: OnboardingTextField(
                                    controller: _nameController,
                                    label: context.l10n.authDisplayNameLabel,
                                    hint: context.l10n.authDisplayNameHint,
                                    maxLength: 30,
                                    maxLines: 1,
                                    tooLongText: context.l10n.authInputTooLong,
                                    errorText: _currentStep == 0
                                        ? _validationError
                                        : null,
                                    onChanged: (_) => _clearValidationError(),
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (_) => _next(),
                                  ),
                                ),
                                ProfileSetupStep(
                                  title:
                                      context.l10n.authOnboardingBirthDateTitle,
                                  subtitle:
                                      context.l10n.authOnboardingBirthDateHint,
                                  errorText: _currentStep == 1
                                      ? _validationError ??
                                            _birthDateValidationError
                                      : null,
                                  child: OnboardingBirthDateFields(
                                    dayController: _dayController,
                                    monthController: _monthController,
                                    yearController: _yearController,
                                    dayFocusNode: _dayFocusNode,
                                    monthFocusNode: _monthFocusNode,
                                    yearFocusNode: _yearFocusNode,
                                    dayHint: context.l10n.authBirthDateDay,
                                    monthHint: context.l10n.authBirthDateMonth,
                                    yearHint: context.l10n.authBirthDateYear,
                                    onChanged: _onBirthDateChanged,
                                  ),
                                ),
                                ProfileSetupStep(
                                  title: context.l10n.authOnboardingGenderTitle,
                                  child: ProfileGenderPicker(
                                    selectedGender: _gender,
                                    resetLabel:
                                        context.l10n.authOnboardingReset,
                                    onSelected: (gender) {
                                      setState(() => _gender = gender);
                                    },
                                    onReset: () {
                                      setState(() => _gender = null);
                                    },
                                  ),
                                ),
                                ProfileSetupStep(
                                  title: context.l10n.authOnboardingAvatarTitle,
                                  child: ProfileAvatarPicker(
                                    avatarUrl: _isAvatarRemoved
                                        ? null
                                        : authState.profile?.avatarUrl ??
                                              authState.session?.avatarUrl,
                                    localAvatarBytes:
                                        _localAvatarBytes ??
                                        (_isAvatarRemoved
                                            ? null
                                            : authState.profile?.avatarBytes),
                                    onPick: _pickAvatar,
                                    onRemove: _removeAvatar,
                                  ),
                                ),
                                ProfileSetupStep(
                                  title: context.l10n.authOnboardingBioTitle,
                                  avoidKeyboardCompression: true,
                                  child: OnboardingTextField(
                                    controller: _bioController,
                                    label: context.l10n.authOnboardingBioLabel,
                                    hint: context.l10n.authOnboardingBioHint,
                                    maxLength: 130,
                                    maxLines: 4,
                                    tooLongText: context.l10n.authInputTooLong,
                                    errorText: _currentStep == _stepCount - 1
                                        ? _validationError
                                        : null,
                                    onChanged: (_) => _clearValidationError(),
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!hideNavigationForKeyboard)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                              child: AnimatedBuilder(
                                animation: Listenable.merge([
                                  _nameController,
                                  _dayController,
                                  _monthController,
                                  _yearController,
                                  _bioController,
                                ]),
                                builder: (context, _) => ProfileSetupNavigation(
                                  isFirstStep: _currentStep == 0,
                                  isLastStep: _currentStep == _stepCount - 1,
                                  showSkip:
                                      _currentStep != _stepCount - 1 &&
                                      _showSkip(authState),
                                  isSubmitting: authState.isSubmitting,
                                  isNextEnabled:
                                      _canProceed &&
                                      (_currentStep != 1 ||
                                          _birthDateValidationError == null),
                                  skipLabel: context.l10n.authOnboardingSkip,
                                  completeLabel:
                                      context.l10n.authOnboardingComplete,
                                  onBack: _previous,
                                  onNext: _next,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Positioned(
                        top: 0,
                        left: 16,
                        child: TextButton(
                          onPressed: authState.isSubmitting
                              ? null
                              : () => context.read<AuthBloc>().add(
                                  const AuthSignOutRequested(),
                                ),
                          style: TextButton.styleFrom(
                            foregroundColor: context.colorScheme.onSurface,
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            textStyle: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(context.l10n.authBack),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _next() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_canProceed) {
      setState(
        () => _validationError = switch (_currentStep) {
          0 => context.l10n.authNameInvalid,
          1 => context.l10n.authBirthDateInvalid,
          4 => context.l10n.authInputTooLong,
          _ => null,
        },
      );
      return;
    }

    if (_currentStep == _stepCount - 1) {
      _submit();
      return;
    }

    setState(() => _validationError = null);
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _previous() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _clearValidationError() {
    if (_validationError != null) {
      setState(() => _validationError = null);
    }
  }

  bool get _canProceed => switch (_currentStep) {
    0 =>
      _nameController.text.trim().length >= 2 &&
          _nameController.text.trim().length <= 30,
    1 => _parseBirthDate() != null,
    4 => _bioController.text.length <= 130,
    _ => true,
  };

  bool _showSkip(AuthState authState) => switch (_currentStep) {
    2 => _gender == null,
    3 => !_hasAvatar(authState),
    4 => _bioController.text.trim().isEmpty,
    _ => false,
  };

  bool _hasAvatar(AuthState authState) {
    if (_localAvatarBytes != null) return true;
    if (_isAvatarRemoved) return false;

    if (authState.profile?.avatarBytes != null) return true;

    final avatarUrl =
        authState.profile?.avatarUrl ?? authState.session?.avatarUrl;
    return avatarUrl?.isNotEmpty == true;
  }

  String? get _birthDateValidationError {
    final day = int.tryParse(_dayController.text);
    final month = int.tryParse(_monthController.text);
    final year = int.tryParse(_yearController.text);

    if (_dayController.text.length == 2 &&
        (day == null || day < 1 || day > 31)) {
      return context.l10n.authBirthDateInvalid;
    }
    if (_monthController.text.length == 2 &&
        (month == null || month < 1 || month > 12)) {
      return context.l10n.authBirthDateInvalid;
    }
    if (_yearController.text.length >= 2 && (year == null || year < 1900)) {
      return context.l10n.authBirthDateInvalid;
    }
    if (_dayController.text.length == 2 &&
        _monthController.text.length == 2 &&
        _yearController.text.length == 4 &&
        _parseBirthDate() == null) {
      return context.l10n.authBirthDateInvalid;
    }
    return null;
  }

  DateTime? _parseBirthDate() {
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

  void _onBirthDateChanged() {
    setState(() => _validationError = null);
  }

  Future<void> _pickAvatar() async {
    final imageBytes = await MediaService.pickImageBytesFromGallery();
    if (!mounted || imageBytes == null) return;
    setState(() {
      _localAvatarBytes = imageBytes;
      _isAvatarRemoved = false;
    });
  }

  void _removeAvatar() {
    setState(() {
      _localAvatarBytes = null;
      _isAvatarRemoved = true;
    });
  }

  void _submit() {
    final birthDate = _parseBirthDate();
    if (birthDate == null) {
      setState(() => _validationError = context.l10n.authBirthDateInvalid);
      return;
    }

    context.read<AuthBloc>().add(
      AuthProfileSubmitted(
        displayName: _nameController.text.trim(),
        birthDate: birthDate,
        gender: _gender ?? ProfileGender.unspecified,
        bio: _bioController.text,
        avatarBytes: _localAvatarBytes,
        removeAvatar: _isAvatarRemoved,
      ),
    );
  }

  String _failureMessage(BuildContext context, AuthFailure? failure) {
    return switch (failure) {
      AuthFailure.usernameTaken => context.l10n.authUsernameTaken,
      AuthFailure.invalidUsername => context.l10n.authUsernameInvalid,
      AuthFailure.invalidDisplayName => context.l10n.authNameInvalid,
      _ => context.l10n.authProfileSaveFailed,
    };
  }
}

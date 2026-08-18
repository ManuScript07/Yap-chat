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
                                  errorText: _currentStep == 0
                                      ? _validationError
                                      : null,
                                  child: OnboardingTextField(
                                    controller: _nameController,
                                    label: context.l10n.authDisplayNameLabel,
                                    maxLength: 30,
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
                                    localAvatarBytes: _localAvatarBytes,
                                    onPick: _pickAvatar,
                                    onRemove: _removeAvatar,
                                  ),
                                ),
                                ProfileSetupStep(
                                  title: context.l10n.authOnboardingBioTitle,
                                  errorText: _currentStep == _stepCount - 1
                                      ? _validationError
                                      : null,
                                  child: OnboardingTextField(
                                    controller: _bioController,
                                    label: context.l10n.authOnboardingBioLabel,
                                    maxLength: 130,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                                    _currentStep != _stepCount - 1 && _showSkip,
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
        () => _validationError = _currentStep == 0
            ? context.l10n.authNameRequired
            : context.l10n.authBirthDateInvalid,
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

  bool get _canProceed => switch (_currentStep) {
    0 => _nameController.text.trim().isNotEmpty,
    1 => _parseBirthDate() != null,
    _ => true,
  };

  bool get _showSkip => switch (_currentStep) {
    2 => _gender == null,
    3 => _localAvatarBytes == null,
    4 => _bioController.text.trim().isEmpty,
    _ => false,
  };

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
      ),
    );
  }

  String _failureMessage(BuildContext context, AuthFailure? failure) {
    return switch (failure) {
      AuthFailure.usernameTaken => context.l10n.authUsernameTaken,
      AuthFailure.invalidUsername => context.l10n.authUsernameInvalid,
      _ => context.l10n.authProfileSaveFailed,
    };
  }
}

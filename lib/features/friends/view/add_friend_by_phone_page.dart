import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/bloc/bloc.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/friends/widgets/widgets.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class AddFriendByPhonePage extends StatelessWidget {
  const AddFriendByPhonePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PhoneFriendSearchCubit(
        repository: context.read<IFriendsRepository>(),
      ),
      child: const _AddFriendByPhoneView(),
    );
  }
}

class _AddFriendByPhoneView extends StatefulWidget {
  const _AddFriendByPhoneView();

  @override
  State<_AddFriendByPhoneView> createState() => _AddFriendByPhoneViewState();
}

class _AddFriendByPhoneViewState extends State<_AddFriendByPhoneView> {
  final _phoneController = TextEditingController();
  final _phoneNormalizer = PhoneNumberNormalizer();
  String? _submittedPhone;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PhoneFriendSearchCubit, PhoneFriendSearchState>(
      listenWhen: (previous, current) =>
          previous.actionError != current.actionError &&
          current.actionError != null,
      listener: (context, state) {
        showAppSnackBar(
          context,
          message: context.l10n.friendsActionFailed,
          type: SnackBarType.error,
        );
        context.read<PhoneFriendSearchCubit>().clearActionError();
      },
      child: KeyboardDismissPopScope(
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: context.scaffoldBackgroundColor,
          appBar: PrimaryAppBar(
            title: context.l10n.friendsAddByPhoneTitle,
            titleWidget: Text(
              context.l10n.friendsAddByPhoneTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleLargeFlex.copyWith(fontSize: 32),
            ),
          ),
          body: _PhoneSearchBody(
            controller: _phoneController,
            normalizer: _phoneNormalizer,
            submittedPhone: _submittedPhone,
            onChanged: _onPhoneChanged,
            onSubmitted: _submitSearch,
          ),
        ),
      ),
    );
  }

  void _onPhoneChanged(String value) {
    final normalizedPhone = _phoneNormalizer.normalizeLocalNationalNumber(
      value,
    );
    setState(() {
      if (_submittedPhone != null && normalizedPhone != _submittedPhone) {
        _submittedPhone = null;
      }
    });
  }

  void _submitSearch() {
    final normalizedPhone = _phoneNormalizer.normalizeLocalNationalNumber(
      _phoneController.text,
    );
    if (normalizedPhone == null) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submittedPhone = normalizedPhone);
    unawaited(context.read<PhoneFriendSearchCubit>().search(normalizedPhone));
  }
}

class _PhoneSearchBody extends StatelessWidget {
  const _PhoneSearchBody({
    required this.controller,
    required this.normalizer,
    required this.submittedPhone,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final PhoneNumberNormalizer normalizer;
  final String? submittedPhone;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = math.max(16.0, (constraints.maxWidth - 560) / 2);
        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontal + systemPadding.left,
                  130,
                  horizontal + systemPadding.right,
                  systemPadding.bottom + 24,
                ),
                child:
                    BlocBuilder<PhoneFriendSearchCubit, PhoneFriendSearchState>(
                      builder: (context, state) {
                        final callingCode = normalizer.localCountryCallingCode;
                        final maximumNationalDigits =
                            normalizer.localNationalMaxLength;
                        final isCurrentSearch =
                            submittedPhone != null &&
                            state.phoneNumber == submittedPhone;
                        final isLoading =
                            isCurrentSearch &&
                            state.status == PhoneFriendSearchStatus.loading;
                        final isRefreshing =
                            isCurrentSearch && state.isRefreshing;
                        final candidate =
                            isCurrentSearch &&
                                state.status == PhoneFriendSearchStatus.success
                            ? state.candidate
                            : null;
                        final searchError = !isCurrentSearch
                            ? null
                            : switch (state.status) {
                                PhoneFriendSearchStatus.failure =>
                                  context.l10n.friendsUserSearchFailed,
                                PhoneFriendSearchStatus.success
                                    when candidate == null =>
                                  context.l10n.friendsUsernameNotFound,
                                _ => null,
                              };
                        final isValid =
                            normalizer.normalizeLocalNationalNumber(
                              controller.text,
                            ) !=
                            null;
                        final errorText =
                            _hasInvalidPhoneCharacters(controller.text)
                            ? context.l10n.friendsPhoneInvalid
                            : searchError;

                        return Column(
                          children: [
                            const Spacer(flex: 4),
                            OnboardingTextField(
                              controller: controller,
                              label: context.l10n.friendsPhoneLabel,
                              hint: callingCode == null
                                  ? context.l10n.friendsPhoneHint
                                  : '',
                              maxLength: maximumNationalDigits,
                              maxLines: 1,
                              tooLongText: context.l10n.friendsPhoneTooLong,
                              errorText: errorText,
                              textInputAction: TextInputAction.search,
                              keyboardType: TextInputType.phone,
                              autocorrect: false,
                              prefixText: callingCode == null
                                  ? null
                                  : '+$callingCode',
                              inputFormatters: callingCode == null
                                  ? null
                                  : [
                                      _LocalPhoneNumberFormatter(
                                        normalizer: normalizer,
                                        callingCode: callingCode,
                                        maxNationalDigits:
                                            maximumNationalDigits,
                                      ),
                                    ],
                              lengthResolver: _phoneDigitCount,
                              onChanged: onChanged,
                              onSubmitted: (_) => onSubmitted(),
                            ),
                            const SizedBox(height: 16),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: isLoading
                                    ? const Padding(
                                        key: ValueKey('phone-search-loading'),
                                        padding: EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        child: SizedBox.square(
                                          dimension: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                          ),
                                        ),
                                      )
                                    : candidate == null
                                    ? const SizedBox(
                                        key: ValueKey('phone-search-idle'),
                                      )
                                    : FriendCandidateItem(
                                        key: ValueKey('phone:${candidate.id}'),
                                        candidate: candidate,
                                        friendsLabel: context.l10n.friendsCount,
                                        relationshipLabel: (relationship) =>
                                            switch (relationship) {
                                              FriendRelationship.friend =>
                                                context
                                                    .l10n
                                                    .friendsAlreadyAdded,
                                              FriendRelationship.outgoing =>
                                                context.l10n.friendsRequestSent,
                                              FriendRelationship.incoming =>
                                                context
                                                    .l10n
                                                    .friendsRequestIncoming,
                                              FriendRelationship.none => '',
                                            },
                                        avatarLoader: () => context
                                            .read<IFriendsRepository>()
                                            .resolveCandidateAvatar(candidate),
                                        respectSystemPadding: false,
                                        onAdd: () => context
                                            .read<PhoneFriendSearchCubit>()
                                            .sendRequest(candidate),
                                        onAccept: () => context
                                            .read<PhoneFriendSearchCubit>()
                                            .respondToIncoming(
                                              candidate,
                                              accept: true,
                                            ),
                                        onReject: () => context
                                            .read<PhoneFriendSearchCubit>()
                                            .respondToIncoming(
                                              candidate,
                                              accept: false,
                                            ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: FilledButton(
                                onPressed:
                                    isValid && !isLoading && !isRefreshing
                                    ? onSubmitted
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: context.colorScheme.primary,
                                  foregroundColor:
                                      context.colorScheme.onPrimary,
                                  disabledBackgroundColor: context
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.35),
                                  disabledForegroundColor: context
                                      .colorScheme
                                      .onPrimary
                                      .withValues(alpha: 0.6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(21),
                                  ),
                                  textStyle: context.textTheme.labelLarge
                                      ?.copyWith(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                child: Text(context.l10n.friendsUsernameSearch),
                              ),
                            ),
                            const Spacer(flex: 5),
                          ],
                        );
                      },
                    ),
              ),
            ),
          ],
        );
      },
    );
  }
}

bool _hasInvalidPhoneCharacters(String value) =>
    value.isNotEmpty && !RegExp(r'^[0-9+().\-\s]*$').hasMatch(value);

int _phoneDigitCount(String value) => RegExp(r'[0-9]').allMatches(value).length;

class _LocalPhoneNumberFormatter extends TextInputFormatter {
  const _LocalPhoneNumberFormatter({
    required this.normalizer,
    required this.callingCode,
    required this.maxNationalDigits,
  });

  final PhoneNumberNormalizer normalizer;
  final String callingCode;
  final int maxNationalDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawText = newValue.text;
    final selectionEnd =
        newValue.selection.extentOffset.clamp(0, rawText.length) as int;
    var digits = _digitsOnly(rawText);
    var digitsBeforeSelection = _digitsOnly(
      rawText.substring(0, selectionEnd),
    ).length;

    final containsPastedCallingCode =
        rawText.trimLeft().startsWith('+') && digits.startsWith(callingCode);
    if (containsPastedCallingCode) {
      digits = digits.substring(callingCode.length);
      digitsBeforeSelection =
          (digitsBeforeSelection - callingCode.length).clamp(0, digits.length)
              as int;
    }
    if (digits.length > maxNationalDigits) {
      digits = digits.substring(0, maxNationalDigits);
    }

    final formatted = normalizer.formatLocalNationalNumber(digits);
    final cursorOffset = _offsetAfterDigits(
      formatted,
      digitsBeforeSelection.clamp(0, digits.length) as int,
    );
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }
}

String _digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

int _offsetAfterDigits(String value, int digitCount) {
  if (digitCount == 0) return 0;
  var found = 0;
  for (var index = 0; index < value.length; index++) {
    if (RegExp(r'[0-9]').hasMatch(value[index])) {
      found++;
      if (found == digitCount) return index + 1;
    }
  }
  return value.length;
}

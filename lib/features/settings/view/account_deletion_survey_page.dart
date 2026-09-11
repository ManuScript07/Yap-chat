import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/settings/view/settings_routes.dart';
import 'package:yap_chat/features/settings/widgets/settings_widgets.dart';
import 'package:yap_chat/ui/ui.dart';

class AccountDeletionSurveyPage extends StatefulWidget {
  const AccountDeletionSurveyPage({super.key});

  @override
  State<AccountDeletionSurveyPage> createState() =>
      _AccountDeletionSurveyPageState();
}

class _AccountDeletionSurveyPageState extends State<AccountDeletionSurveyPage> {
  static const _feedbackMaxLength = 150;

  final _selectedReasons = <AccountDeletionReason>{};
  late final TextEditingController _feedbackController;
  var _showReasonsError = false;
  var _isProceeding = false;

  @override
  void initState() {
    super.initState();
    _feedbackController = TextEditingController();
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final isSubmitting = authState.isSubmitting || _isProceeding;
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    return PopScope(
      canPop: !isSubmitting,
      child: Scaffold(
        backgroundColor: context.scaffoldBackgroundColor,
        extendBodyBehindAppBar: true,
        appBar: SettingsPageAppBar(
          title: context.l10n.accountDeletionSurveyTitle,
        ),
        body: AbsorbPointer(
          absorbing: isSubmitting,
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: SizedBox(
                  width: math.min(560, constraints.maxWidth),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16 + (isLandscape ? 0 : mediaQuery.padding.left),
                      112,
                      16 + (isLandscape ? 0 : mediaQuery.padding.right),
                      isLandscape
                          ? 24
                          : math.max(24, mediaQuery.padding.bottom + 16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.l10n.accountDeletionSurveyDescription,
                          style: settingsValueStyle(context).copyWith(
                            fontSize: 18,
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          context.l10n.accountDeletionSurveyReasonsTitle,
                          style: TextStyle(
                            color: _showReasonsError
                                ? Colors.red
                                : context.colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            letterSpacing: .5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final reason in AccountDeletionReason.values)
                          _ReasonChoice(
                            label: _reasonLabel(context, reason),
                            selected: _selectedReasons.contains(reason),
                            onChanged: (selected) => setState(() {
                              if (selected) {
                                _selectedReasons.add(reason);
                              } else {
                                _selectedReasons.remove(reason);
                              }
                              if (_selectedReasons.isNotEmpty) {
                                _showReasonsError = false;
                              }
                            }),
                          ),
                        if (_showReasonsError) ...[
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.accountDeletionSurveyReasonsRequired,
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        OnboardingTextField(
                          controller: _feedbackController,
                          label:
                              context.l10n.accountDeletionSurveyFeedbackLabel,
                          hint: context.l10n.accountDeletionSurveyFeedbackHint,
                          maxLength: _feedbackMaxLength,
                          maxLines: 4,
                          tooLongText: context.l10n.authInputTooLong,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 32),
                        _PrimaryActionButton(
                          label: context.l10n.accountDeletionSurveyCancel,
                          onPressed: isSubmitting
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 12),
                        _OutlinedActionButton(
                          label: context.l10n.accountDeletionSurveyContinue,
                          isLoading: isSubmitting,
                          onPressed: isSubmitting ? null : _continue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _reasonLabel(BuildContext context, AccountDeletionReason reason) =>
      switch (reason) {
        AccountDeletionReason.ads => context.l10n.accountDeletionReasonAds,
        AccountDeletionReason.newAccount =>
          context.l10n.accountDeletionReasonNewAccount,
        AccountDeletionReason.safety =>
          context.l10n.accountDeletionReasonSafety,
        AccountDeletionReason.fewPeople =>
          context.l10n.accountDeletionReasonFewPeople,
        AccountDeletionReason.noLongerChat =>
          context.l10n.accountDeletionReasonNoLongerChat,
        AccountDeletionReason.technicalProblems =>
          context.l10n.accountDeletionReasonTechnicalProblems,
        AccountDeletionReason.other => context.l10n.accountDeletionReasonOther,
      };

  Future<void> _continue() async {
    if (_isProceeding) return;
    if (_selectedReasons.isEmpty) {
      setState(() => _showReasonsError = true);
      return;
    }
    if (_feedbackController.text.length > _feedbackMaxLength) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final feedback = _feedbackController.text.trim();
    final survey = AccountDeletionSurvey(
      reasons: _selectedReasons.toList(growable: false),
      feedback: feedback.isEmpty ? null : feedback,
    );
    setState(() => _isProceeding = true);
    final confirmed = await Navigator.of(context).push<bool>(
      settingsSlideRightRoute<bool>(
        _AccountDeletionConfirmationPage(survey: survey),
      ),
    );
    if (!mounted) return;
    setState(() => _isProceeding = false);
    if (confirmed == false) {
      Navigator.of(context).pop();
    }
  }
}

class _AccountDeletionConfirmationPage extends StatefulWidget {
  const _AccountDeletionConfirmationPage({required this.survey});

  final AccountDeletionSurvey survey;

  @override
  State<_AccountDeletionConfirmationPage> createState() =>
      _AccountDeletionConfirmationPageState();
}

class _AccountDeletionConfirmationPageState
    extends State<_AccountDeletionConfirmationPage> {
  var _isSubmittingRequest = false;

  @override
  Widget build(BuildContext context) {
    final isSubmitting =
        _isSubmittingRequest || context.watch<AuthBloc>().state.isSubmitting;
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          _isSubmittingRequest &&
          previous.failure != current.failure &&
          current.failure == AuthFailure.accountDeletion,
      listener: (context, state) =>
          setState(() => _isSubmittingRequest = false),
      child: PopScope(
        canPop: !isSubmitting,
        child: Scaffold(
          backgroundColor: context.scaffoldBackgroundColor,
          extendBodyBehindAppBar: true,
          appBar: SettingsPageAppBar(
            title: context.l10n.accountDeletionConfirmationTitle,
          ),
          body: AbsorbPointer(
            absorbing: isSubmitting,
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mediaQuery = MediaQuery.of(context);
                  final isLandscape =
                      mediaQuery.orientation == Orientation.landscape;
                  final horizontalPadding =
                      16.0 + (isLandscape ? 0.0 : mediaQuery.padding.left);
                  final verticalPadding = isLandscape
                      ? 24.0
                      : math.max(24.0, mediaQuery.padding.bottom + 16);
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          112.0,
                          16.0 + (isLandscape ? 0.0 : mediaQuery.padding.right),
                          verticalPadding,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(
                              0.0,
                              constraints.maxHeight - 112.0 - verticalPadding,
                            ),
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  context
                                      .l10n
                                      .accountDeletionConfirmationDescription,
                                  style: settingsValueStyle(context).copyWith(
                                    fontSize: 18,
                                    color: context.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                _PrimaryActionButton(
                                  label:
                                      context.l10n.accountDeletionSurveyCancel,
                                  onPressed: isSubmitting
                                      ? null
                                      : () => Navigator.of(context).pop(false),
                                ),
                                const SizedBox(height: 12),
                                _OutlinedActionButton(
                                  label: context
                                      .l10n
                                      .accountDeletionConfirmationDelete,
                                  isLoading: isSubmitting,
                                  onPressed: isSubmitting
                                      ? null
                                      : _requestDeletion,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _requestDeletion() {
    if (_isSubmittingRequest) return;
    setState(() => _isSubmittingRequest = true);
    context.read<AuthBloc>().add(AuthAccountDeletionRequested(widget.survey));
  }
}

class _ReasonChoice extends StatelessWidget {
  const _ReasonChoice({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!selected),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: settingsValueStyle(context))),
          Checkbox(
            value: selected,
            activeColor: context.colorScheme.primary,
            checkColor: context.colorScheme.onPrimary,
            side: BorderSide(color: context.colorScheme.outline, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            onChanged: (value) => onChanged(value ?? false),
          ),
        ],
      ),
    ),
  );
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: context.colorScheme.primary,
        foregroundColor: context.colorScheme.onPrimary,
        disabledBackgroundColor: context.colorScheme.primary.withValues(
          alpha: .5,
        ),
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      ),
    ),
  );
}

class _OutlinedActionButton extends StatelessWidget {
  const _OutlinedActionButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.colorScheme.onSurface,
        side: BorderSide(color: context.colorScheme.outline, width: 2),
        shape: const StadiumBorder(),
      ),
      child: isLoading
          ? SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: context.colorScheme.onSurface,
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
              ),
            ),
    ),
  );
}

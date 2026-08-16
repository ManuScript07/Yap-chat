import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  DateTime? _birthDate;
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    _nameController = TextEditingController(
      text: authState.profile?.displayName ?? authState.session?.displayName,
    );
    _usernameController = TextEditingController(
      text: authState.profile?.username,
    );
    _birthDate = authState.profile?.birthDate ?? authState.session?.birthDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          previous.failure != current.failure && current.failure != null,
      listener: (context, state) {
        showAppSnackBar(
          context,
          message: _failureMessage(context, state.failure),
          type: SnackBarType.error,
        );
        context.read<AuthBloc>().add(const AuthFailureCleared());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.authProfileSetupTitle),
          actions: [
            IconButton(
              tooltip: context.l10n.authSignOut,
              onPressed: authState.isSubmitting
                  ? null
                  : () => context.read<AuthBloc>().add(
                      const AuthSignOutRequested(),
                    ),
              icon: const Icon(Icons.logout_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: UserAvatar(
                        avatarUrl:
                            authState.profile?.avatarUrl ??
                            authState.session?.avatarUrl,
                        size: 96,
                        borderRadius: 28,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.authProfileSetupDescription,
                      textAlign: TextAlign.center,
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: context.l10n.authDisplayNameLabel,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usernameController,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: InputDecoration(
                        labelText: context.l10n.authUsernameLabel,
                        helperText: context.l10n.authUsernameHelper,
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickBirthDate,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: context.l10n.authBirthDateLabel,
                          suffixIcon: const Icon(Icons.calendar_month_rounded),
                        ),
                        child: Text(
                          _birthDate == null
                              ? context.l10n.authBirthDatePlaceholder
                              : DateFormat.yMMMMd(locale).format(_birthDate!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    CheckboxListTile(
                      value: _acceptedTerms,
                      onChanged: authState.isSubmitting
                          ? null
                          : (value) =>
                                setState(() => _acceptedTerms = value ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(context.l10n.authAcceptDocuments),
                      subtitle: Wrap(
                        spacing: 4,
                        children: [
                          _DocumentLink(
                            label: context.l10n.authTermsOfService,
                            envKey: 'TERMS_OF_SERVICE_URL',
                          ),
                          Text(
                            context.l10n.authDocumentsAnd,
                            style: context.textTheme.bodySmall,
                          ),
                          _DocumentLink(
                            label: context.l10n.authPrivacyPolicy,
                            envKey: 'PRIVACY_POLICY_URL',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: authState.isSubmitting ? null : _submit,
                        child: authState.isSubmitting
                            ? SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.colorScheme.onPrimary,
                                ),
                              )
                            : Text(context.l10n.authCompleteRegistration),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (!mounted || selected == null) return;
    setState(() => _birthDate = selected);
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showValidation(context.l10n.authNameRequired);
      return;
    }
    final birthDate = _birthDate;
    if (birthDate == null) {
      _showValidation(context.l10n.authBirthDateRequired);
      return;
    }
    if (!_acceptedTerms) {
      _showValidation(context.l10n.authDocumentsRequired);
      return;
    }

    context.read<AuthBloc>().add(
      AuthProfileSubmitted(
        displayName: name,
        birthDate: birthDate,
        acceptedTerms: true,
        username: _usernameController.text,
        avatarUrl:
            context.read<AuthBloc>().state.profile?.avatarUrl ??
            context.read<AuthBloc>().state.session?.avatarUrl,
      ),
    );
  }

  void _showValidation(String message) {
    showAppSnackBar(context, message: message, type: SnackBarType.error);
  }

  String _failureMessage(BuildContext context, AuthFailure? failure) {
    return switch (failure) {
      AuthFailure.usernameTaken => context.l10n.authUsernameTaken,
      AuthFailure.invalidUsername => context.l10n.authUsernameInvalid,
      _ => context.l10n.authProfileSaveFailed,
    };
  }
}

class _DocumentLink extends StatelessWidget {
  const _DocumentLink({required this.label, required this.envKey});

  final String label;
  final String envKey;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final rawUrl = context.read<AppConfig>().env[envKey];
        final url = rawUrl == null ? null : Uri.tryParse(rawUrl);
        if (url != null) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
      child: Text(
        label,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: context.colorScheme.primary,
        ),
      ),
    );
  }
}

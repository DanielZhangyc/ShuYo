import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/forum_url_resolver.dart';
import '../../data/models/composer.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/local_image_picker.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/widgets/empty_state.dart';
import 'avatar_crop_page.dart';
import 'background_crop_page.dart';
import 'profile_header.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key, required this.repository});

  final ForumRepository repository;

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  static const _bioMaxLength = 20;
  static const _horizontalPadding = 16.0;

  final _bioController = TextEditingController();
  final _scrollController = ScrollController();
  late Future<void> _loadFuture;
  UserProfile? _profile;
  String _baselineBio = '';
  String _baselineBackgroundUrl = '';
  bool _baselineHideProfile = false;
  bool _hideProfile = false;
  _AvatarDraft _avatarDraft = _AvatarDraft.unchanged;
  PickedImage? _avatarImage;
  ProfileImageUpload? _avatarUpload;
  PickedImage? _backgroundImage;
  ProfileImageUpload? _backgroundUpload;
  bool _backgroundCleared = false;
  bool _pickingAvatar = false;
  bool _pickingBackground = false;
  bool _saving = false;
  bool _hasCommittedChanges = false;
  bool _allowPop = false;
  bool _syncingBio = false;

  bool get _settingsDirty =>
      _bioController.text.trim() != _baselineBio ||
      _hideProfile != _baselineHideProfile ||
      _backgroundDirty;
  bool get _backgroundDirty =>
      _backgroundImage != null ||
      (_backgroundCleared && _baselineBackgroundUrl.isNotEmpty);
  bool get _dirty => _settingsDirty || _avatarDraft != _AvatarDraft.unchanged;
  bool get _busy => _saving || _pickingAvatar || _pickingBackground;

  @override
  void initState() {
    super.initState();
    _bioController.addListener(_onBioChanged);
    _loadFuture = _loadProfile();
  }

  @override
  void dispose() {
    _bioController.removeListener(_onBioChanged);
    _bioController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handlePopRequest();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('个人资料设置'),
          actions: [
            TextButton(
              onPressed: _dirty && !_busy ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
        body: FutureBuilder<void>(
          future: _loadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 3),
              );
            }
            if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.manage_accounts_outlined,
                title: '资料加载失败',
                message: snapshot.error.toString(),
                action: TextButton.icon(
                  onPressed: () => setState(
                    () => _loadFuture = _loadProfile(force: true),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              );
            }
            final profile = _profile;
            if (profile == null) {
              return const EmptyState(
                icon: Icons.person_outline,
                title: '没有资料',
                message: '论坛没有返回当前用户资料。',
              );
            }
            return ListView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                _horizontalPadding,
                12,
                _horizontalPadding,
                30,
              ),
              children: [
                ProfileHeader(
                  profile: profile,
                  title: profile.username,
                  subtitle: _hideProfile ? '个人资料不公开' : '个人资料公开',
                  avatarUrl: _avatarPreviewUrl(profile),
                  avatarBytes: _avatarImage?.bytes,
                  backgroundUrl: _backgroundPreviewUrl,
                  backgroundBytes: _backgroundImage?.bytes,
                  onEditAvatar: _busy ? null : _showAvatarActions,
                ),
                const SizedBox(height: 18),
                _SectionTitle('个性签名'),
                const SizedBox(height: 8),
                TextField(
                  controller: _bioController,
                  enabled: !_saving,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: _bioMaxLength,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '写一句个人介绍',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('公开个人资料'),
                  value: !_hideProfile,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _hideProfile = !value),
                ),
                const SizedBox(height: 18),
                _SectionTitle('个人主页背景'),
                const SizedBox(height: 8),
                _BackgroundControls(
                  busy: _busy,
                  hasBackground: _backgroundImage != null ||
                      (!_backgroundCleared &&
                          _baselineBackgroundUrl.isNotEmpty),
                  onPick: _pickProfileBackground,
                  onClear: _clearProfileBackground,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String get _backgroundPreviewUrl =>
      _backgroundCleared ? '' : _absoluteUrl(_baselineBackgroundUrl);

  Future<void> _loadProfile({bool force = false}) async {
    final profile =
        await widget.repository.fetchCurrentUserProfile(forceRefresh: force);
    if (!mounted) return;
    _setBio(profile.bioRaw);
    setState(() {
      _profile = profile;
      _baselineBio = profile.bioRaw;
      _baselineBackgroundUrl = profile.profileBackgroundUploadUrl;
      _baselineHideProfile = profile.hideProfile;
      _hideProfile = profile.hideProfile;
      _resetImageDrafts();
    });
  }

  void _onBioChanged() {
    if (!_syncingBio && mounted) setState(() {});
  }

  void _setBio(String value) {
    _syncingBio = true;
    _bioController.text = value;
    _syncingBio = false;
  }

  Future<void> _showAvatarActions() async {
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('选择自定义头像'),
              onTap: () => Navigator.of(context).pop(_AvatarAction.custom),
            ),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('使用默认头像'),
              onTap: () => Navigator.of(context).pop(_AvatarAction.system),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AvatarAction.custom:
        await _pickCustomAvatar();
        break;
      case _AvatarAction.system:
        final profile = _profile;
        if (profile == null) return;
        setState(() {
          _avatarDraft = _usesSystemAvatar(profile)
              ? _AvatarDraft.unchanged
              : _AvatarDraft.system;
          _avatarImage = null;
          _avatarUpload = null;
        });
        break;
    }
  }

  Future<void> _pickCustomAvatar() async {
    if (_pickingAvatar) return;
    setState(() => _pickingAvatar = true);
    try {
      final picked = await LocalImagePicker.pickImage();
      if (picked == null || !mounted) return;
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (context) => AvatarCropPage(image: picked.bytes),
        ),
      );
      if (cropped == null || !mounted) return;
      setState(() {
        _avatarImage = _avatarPickedImage(cropped);
        _avatarUpload = null;
        _avatarDraft = _AvatarDraft.custom;
      });
    } on Object catch (error) {
      if (mounted) _showSnack('头像选择失败：$error');
    } finally {
      if (mounted) setState(() => _pickingAvatar = false);
    }
  }

  Future<void> _pickProfileBackground() async {
    if (_pickingBackground) return;
    setState(() => _pickingBackground = true);
    try {
      final picked = await LocalImagePicker.pickImage();
      if (picked == null || !mounted) return;
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (context) => LayoutBuilder(
            builder: (context, constraints) => BackgroundCropPage(
              image: picked.bytes,
              // Use the same content width as the profile header, including
              // after rotation while the picker or crop page is open.
              aspectRatio: (constraints.maxWidth - 2 * _horizontalPadding) /
                  ProfileHeader.backgroundHeight,
            ),
          ),
        ),
      );
      if (cropped == null || !mounted) return;
      setState(() {
        _backgroundImage = PickedImage(
          bytes: cropped,
          filename: 'profile-background.png',
          mimeType: 'image/png',
        );
        _backgroundUpload = null;
        _backgroundCleared = false;
      });
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } on Object catch (error) {
      if (mounted) _showSnack('背景图选择失败：$error');
    } finally {
      if (mounted) setState(() => _pickingBackground = false);
    }
  }

  void _clearProfileBackground() {
    setState(() {
      _backgroundImage = null;
      _backgroundUpload = null;
      _backgroundCleared = _baselineBackgroundUrl.isNotEmpty;
    });
  }

  Future<void> _handlePopRequest() async {
    if (_allowPop || _busy) return;
    if (!_dirty) {
      _exitPage();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('当前修改尚未保存，确定要返回吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续修改'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) _exitPage();
  }

  void _exitPage() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(_hasCommittedChanges);
    });
  }

  Future<void> _save() async {
    if (_profile == null || _saving || !_dirty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      await _prepareUploads();
      if (_settingsDirty) await _saveSettings();
      if (_avatarDraft != _AvatarDraft.unchanged) await _saveAvatar();
      try {
        final latest = await widget.repository.fetchCurrentUserProfile(
          forceRefresh: true,
        );
        if (mounted) {
          _setBio(latest.bioRaw);
          setState(() {
            _profile = latest;
            _baselineBio = latest.bioRaw;
            _baselineBackgroundUrl = latest.profileBackgroundUploadUrl;
            _baselineHideProfile = latest.hideProfile;
            _hideProfile = latest.hideProfile;
          });
        }
      } on Object {
        // Mutation responses already contain the updated profile.
      }
      if (mounted) _showSnack('资料已保存');
    } on Object catch (error) {
      if (mounted) _showSnack('保存未完成，请重试：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _prepareUploads() async {
    final backgroundImage = _backgroundImage;
    if (backgroundImage != null && _backgroundUpload == null) {
      final upload = await widget.repository.uploadProfileImage(
        backgroundImage,
        ProfileImageUploadType.profileBackground,
      );
      if (!mounted) return;
      setState(() => _backgroundUpload = upload);
    }
    final avatarImage = _avatarImage;
    if (_avatarDraft == _AvatarDraft.custom &&
        avatarImage != null &&
        _avatarUpload == null) {
      final upload = await widget.repository.uploadProfileImage(
        avatarImage,
        ProfileImageUploadType.avatar,
      );
      if (!mounted) return;
      setState(() => _avatarUpload = upload);
    }
  }

  Future<void> _saveSettings() async {
    final profile = _profile!;
    final backgroundUrl = _backgroundCleared
        ? ''
        : _backgroundUpload?.url ?? _baselineBackgroundUrl;
    final updated = await widget.repository.updateProfileSettings(
      ProfileSettingsDraft(
        bioRaw: _bioController.text.trim(),
        hideProfile: _hideProfile,
        profileBackgroundUploadUrl: backgroundUrl,
        cardBackgroundUploadUrl: profile.cardBackgroundUploadUrl,
        timezone: profile.timezone,
        defaultCalendar: profile.defaultCalendar,
      ),
    );
    if (!mounted) return;
    _setBio(updated.bioRaw);
    setState(() {
      _profile = updated;
      _baselineBio = updated.bioRaw;
      _baselineHideProfile = updated.hideProfile;
      _hideProfile = updated.hideProfile;
      _baselineBackgroundUrl = updated.profileBackgroundUploadUrl;
      _backgroundImage = null;
      _backgroundUpload = null;
      _backgroundCleared = false;
      _hasCommittedChanges = true;
    });
  }

  Future<void> _saveAvatar() async {
    final updated = switch (_avatarDraft) {
      _AvatarDraft.system => await widget.repository.useSystemAvatar(),
      _AvatarDraft.custom =>
        await widget.repository.useCustomAvatar(_avatarUpload!.id),
      _AvatarDraft.unchanged => _profile!,
    };
    if (!mounted) return;
    setState(() {
      _profile = updated;
      _avatarDraft = _AvatarDraft.unchanged;
      _avatarImage = null;
      _avatarUpload = null;
      _hasCommittedChanges = true;
    });
  }

  void _resetImageDrafts() {
    _avatarDraft = _AvatarDraft.unchanged;
    _avatarImage = null;
    _avatarUpload = null;
    _backgroundImage = null;
    _backgroundUpload = null;
    _backgroundCleared = false;
  }

  String _avatarPreviewUrl(UserProfile profile) {
    if (_avatarDraft == _AvatarDraft.system) {
      return _absoluteUrl(
        profile.systemAvatarTemplate.replaceAll('{size}', '144'),
      );
    }
    return profile.avatarUrl(size: 144);
  }

  bool _usesSystemAvatar(UserProfile profile) {
    final current = profile.user.avatarTemplate;
    if (profile.systemAvatarTemplate.isNotEmpty) {
      return current == profile.systemAvatarTemplate;
    }
    if (profile.customAvatarTemplate.isNotEmpty) {
      return current != profile.customAvatarTemplate;
    }
    return profile.customAvatarUploadId == null;
  }

  PickedImage _avatarPickedImage(Uint8List bytes) {
    final jpeg = bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8;
    return PickedImage(
      bytes: bytes,
      filename: jpeg ? 'avatar.jpg' : 'avatar.png',
      mimeType: jpeg ? 'image/jpeg' : 'image/png',
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _absoluteUrl(String value) => ForumUrlResolver.resolve(value);
}

class _BackgroundControls extends StatelessWidget {
  const _BackgroundControls({
    required this.busy,
    required this.hasBackground,
    required this.onPick,
    required this.onClear,
  });

  final bool busy;
  final bool hasBackground;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : onPick,
            icon: const Icon(Icons.landscape_outlined),
            label: Text(hasBackground ? '更换背景图片' : '选择背景图片'),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: busy || !hasBackground ? null : onClear,
          icon: const Icon(Icons.delete_outline),
          label: const Text('清除背景'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: ShuYoTextStyles.sectionTitle());
  }
}

enum _AvatarAction { custom, system }

enum _AvatarDraft { unchanged, custom, system }

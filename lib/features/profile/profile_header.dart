import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models/user_profile.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/forum_network_image.dart';

class ProfileHeader extends StatelessWidget {
  static const backgroundHeight = 122.0;

  const ProfileHeader({
    super.key,
    required this.profile,
    required this.title,
    required this.subtitle,
    this.avatarUrl,
    this.avatarBytes,
    this.backgroundUrl,
    this.backgroundBytes,
    this.onEditAvatar,
    this.onTap,
    this.trailing,
    this.privateImage = false,
  });

  final UserProfile profile;
  final String title;
  final String subtitle;
  final String? avatarUrl;
  final Uint8List? avatarBytes;
  final String? backgroundUrl;
  final Uint8List? backgroundBytes;
  final VoidCallback? onEditAvatar;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool privateImage;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final header = SizedBox(
      height: 176,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: backgroundHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _ProfileBackground(
                url: backgroundUrl ?? profile.profileBackgroundUrl(),
                bytes: backgroundBytes,
                privateImage: privateImage,
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 88,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: colors.background,
                shape: BoxShape.circle,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _ProfileAvatar(
                    url: avatarUrl ?? profile.avatarUrl(size: 144),
                    bytes: avatarBytes,
                    privateImage: privateImage,
                  ),
                  if (onEditAvatar != null)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Tooltip(
                        message: '编辑头像',
                        child: Material(
                          color: colors.accent,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onEditAvatar,
                            child: const SizedBox(
                              width: 28,
                              height: 28,
                              child: Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 102,
            right: 0,
            top: 128,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShuYoTextStyles.title(
                          color: colors.textPrimary,
                          size: 19,
                          height: 1.22,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return header;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: header,
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.url,
    required this.bytes,
    required this.privateImage,
  });

  final String url;
  final Uint8List? bytes;
  final bool privateImage;

  @override
  Widget build(BuildContext context) {
    final bytes = this.bytes;
    if (bytes == null) {
      return ForumAvatar(
        url: url,
        size: 68,
        privateImage: privateImage,
      );
    }
    return ClipOval(
      child: Image.memory(
        bytes,
        width: 68,
        height: 68,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

class _ProfileBackground extends StatelessWidget {
  const _ProfileBackground({
    required this.url,
    required this.bytes,
    this.privateImage = false,
  });

  final String url;
  final Uint8List? bytes;
  final bool privateImage;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final bytes = this.bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    if (url.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.accentSoft,
              colors.surfaceAlt,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    }
    return ForumNetworkImage(
      url,
      fit: BoxFit.cover,
      privateImage: privateImage,
      pinned: privateImage,
      errorBuilder: (context, error, stackTrace) {
        return DecoratedBox(
          decoration: BoxDecoration(color: colors.surfaceMuted),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Bar atas yang tetap di tempat saat halaman digulir.
///
/// Isi [backLabel] untuk halaman yang dibuka dari halaman lain: tombol kembali
/// muncul di kiri judul, dan teks ini yang dibacakan pembaca layar.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({
    super.key,
    required this.title,
    this.backLabel,
    this.actions = const [],
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  final String title;
  final String? backLabel;
  final List<Widget> actions;

  /// Gulir mana yang membuat bayangan bar muncul. Halaman yang isinya tidak
  /// lewat di bawah bar memakai `(_) => false`.
  final ScrollNotificationPredicate notificationPredicate;

  static const _backSize = 44.0;

  @override
  Size get preferredSize => const Size.fromHeight(topBarHeight);

  @override
  Widget build(BuildContext context) {
    final backLabel = this.backLabel;

    // Tinggi bar tetap, jadi teks yang sangat diperbesar dibatasi seperti
    // pada menu bawah agar tidak terpotong.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: AppBar(
        automaticallyImplyLeading: false,
        notificationPredicate: notificationPredicate,
        leadingWidth: backLabel == null ? null : 16 + _backSize,
        titleSpacing: backLabel == null ? null : 12,
        leading: backLabel == null
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(start: 16),
                child: Center(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      fixedSize: const Size.square(_backSize),
                    ),
                    child: Icon(Icons.chevron_left, semanticLabel: backLabel),
                  ),
                ),
              ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(title),
        ),
        actions: actions,
        actionsPadding: const EdgeInsetsDirectional.only(end: 16),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../screens/about_screen.dart';
import 'brand_logo.dart';

/// Bar atas yang tetap di tempat saat halaman digulir.
///
/// Tanpa [title], bar menampilkan logo dan tombol Tentang. Dipakai di menu
/// utama supaya keduanya selalu ada di menu mana pun.
///
/// Isi [backLabel] untuk halaman yang dibuka dari halaman lain: tombol kembali
/// muncul di kiri judul, dan teks ini yang dibacakan pembaca layar.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({
    super.key,
    this.title,
    this.backLabel,
    this.actions = const [],
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  final String? title;
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
    final title = this.title;

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
          child: title == null ? const BrandLogo(height: 40) : Text(title),
        ),
        actions: [
          if (title == null) ...[
            const _AboutButton(),
            const SizedBox(width: 8),
          ],
          ...actions,
        ],
        actionsPadding: const EdgeInsetsDirectional.only(end: 16),
      ),
    );
  }
}

class _AboutButton extends StatelessWidget {
  const _AboutButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tentang aplikasi',
      child: OutlinedButton(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        child: const Icon(Icons.info_outline, size: 22),
      ),
    );
  }
}

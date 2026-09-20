import 'package:flutter/material.dart';

class SettingView extends StatelessWidget {
  final String title;
  final VoidCallback onManageAccounts;
  final VoidCallback onManageCategories;

  const SettingView({
    super.key,
    required this.title,
    required this.onManageAccounts,
    required this.onManageCategories,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 32),
          _sectionLabel('帳號管理'),
          const SizedBox(height: 10),
          _settingCard(
            context,
            icon: Icons.person_outline_rounded,
            iconBackground: const Color(0xffEEF2F7),
            title: '帳戶管理',
            subtitle: '管理一般與投資帳戶',
            onTap: onManageAccounts,
          ),
          const SizedBox(height: 24),
          _sectionLabel('報表分類設定'),
          const SizedBox(height: 10),
          _settingCard(
            context,
            icon: Icons.pie_chart_outline_rounded,
            iconBackground: const Color(0xffFFF7E5),
            iconColor: const Color(0xffF59E0B),
            title: '分類管理',
            subtitle: '管理帳戶的資產分類',
            onTap: onManageCategories,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xff64748B),
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _settingCard(
    BuildContext context, {
    required IconData icon,
    required Color iconBackground,
    Color iconColor = const Color(0xff475569),
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconBackground,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xff94A3B8)),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xffCBD5E1),
      ),
      onTap: onTap,
    ),
  );
}

import 'package:flutter/material.dart';

import '../../data/data.dart';

class SettingView extends StatefulWidget {
  final String title;
  final PortfolioDataApi? api;
  final VoidCallback onManageAccounts;
  final VoidCallback onManageCategories;

  const SettingView({
    super.key,
    required this.title,
    this.api,
    required this.onManageAccounts,
    required this.onManageCategories,
  });

  @override
  State<SettingView> createState() => _SettingViewState();
}

class _SettingViewState extends State<SettingView> {
  bool _syncing = false;
  String? _catalogStatus;

  Future<void> _syncCatalog() async {
    final api = widget.api;
    if (api == null || _syncing) return;
    setState(() => _syncing = true);
    try {
      final result = await api.syncSecurityCatalog();
      final failedSources = result.failures.keys.map(_sourceLabel).join('、');
      final status =
          '新增 ${result.added}、更新 ${result.updated}、停用 ${result.deactivated}、恢復 ${result.reactivated}'
          '${result.failures.isEmpty ? '' : '；失敗：$failedSources'}';
      if (mounted) setState(() => _catalogStatus = status);
    } on Object catch (error) {
      if (mounted) setState(() => _catalogStatus = '更新失敗，既有資料已保留：$error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _sourceLabel(StockCatalogSource source) => switch (source) {
    StockCatalogSource.twse => 'TWSE',
    StockCatalogSource.tpex => 'TPEX',
    StockCatalogSource.nasdaqListed => 'NASDAQ',
    StockCatalogSource.nasdaqOther => 'NYSE/AMEX',
  };

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      children: [
        Text(
          widget.title,
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
          subtitle: '管理一般、投資與股票帳戶',
          onTap: widget.onManageAccounts,
        ),
        const SizedBox(height: 24),
        _sectionLabel('股票資料'),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            key: const Key('setting-sync-stock-catalog'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            leading: const Icon(
              Icons.sync_alt_rounded,
              color: Color(0xff059669),
            ),
            title: const Text(
              '更新股票代號',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(_catalogStatus ?? '同步台股與美股目前上市代號'),
            trailing: _syncing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onTap: widget.api == null || _syncing ? null : _syncCatalog,
          ),
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
          onTap: widget.onManageCategories,
        ),
      ],
    ),
  );

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

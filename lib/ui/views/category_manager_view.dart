import 'package:flutter/material.dart';

import '../../data/data.dart';

class CategoryManagerView extends StatefulWidget {
  final PortfolioDataApi? api;
  const CategoryManagerView({super.key, this.api});

  @override
  State<CategoryManagerView> createState() => _CategoryManagerViewState();
}

class _CategoryManagerViewState extends State<CategoryManagerView> {
  static const _colors = <int>[
    0xff10b981,
    0xff3b82f6,
    0xfff59e0b,
    0xff8b5cf6,
    0xffef4444,
  ];
  late Future<List<CategorySummary>> _categories;

  @override
  void initState() {
    super.initState();
    _categories = _load();
  }

  Future<List<CategorySummary>> _load() async =>
      widget.api == null ? [] : widget.api!.listCategories();
  void _refresh() => setState(() => _categories = _load());
  void _showError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _edit([CategorySummary? category]) async {
    final controller = TextEditingController(text: category?.name ?? '');
    var color = category?.colorArgb ?? _colors.first;
    final result = await showDialog<({String name, int color})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(category == null ? '新增分類' : '編輯分類'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: '分類名稱'),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '色彩',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _colors
                    .map(
                      (value) => InkWell(
                        onTap: () => setDialogState(() => color = value),
                        borderRadius: BorderRadius.circular(20),
                        child: CircleAvatar(
                          backgroundColor: Color(value),
                          child: color == value
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (name: controller.text, color: color)),
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || widget.api == null) return;
    try {
      if (category == null) {
        await widget.api!.createCategory(
          CreateCategoryInput(name: result.name, colorArgb: result.color),
        );
      } else {
        await widget.api!.updateCategory(
          category.id,
          UpdateCategoryInput(name: result.name, colorArgb: result.color),
        );
      }
      _refresh();
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _delete(
    CategorySummary category,
    List<CategorySummary> categories,
  ) async {
    final alternatives = categories
        .where((item) => item.id != category.id)
        .toList();
    if (alternatives.isEmpty || widget.api == null) return;
    var replacement = alternatives.first.id;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('刪除「${category.name}」'),
          content: DropdownButtonFormField<String>(
            initialValue: replacement,
            decoration: const InputDecoration(labelText: '帳戶改用分類'),
            items: alternatives
                .map(
                  (item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                )
                .toList(),
            onChanged: (value) => setDialogState(() => replacement = value!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('刪除'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    try {
      await widget.api!.deleteCategory(
        category.id,
        replacementCategoryId: replacement,
      );
      _refresh();
    } on Object catch (e) {
      _showError(e);
    }
  }

  Future<void> _move(
    List<CategorySummary> categories,
    int index,
    int offset,
  ) async {
    final target = index + offset;
    if (target < 0 || target >= categories.length || widget.api == null) return;
    final copy = [...categories];
    final item = copy.removeAt(index);
    copy.insert(target, item);
    try {
      await widget.api!.reorderCategories(copy.map((item) => item.id).toList());
      _refresh();
    } on Object catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('分類管理')),
      body: FutureBuilder<List<CategorySummary>>(
        future: _categories,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = snapshot.data!;
          if (categories.isEmpty) return const Center(child: Text('尚未建立資料'));
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(categories[i].colorArgb),
                ),
                title: Text(categories[i].name),
                subtitle: Text(
                  '排序 ${categories[i].sortOrder} · 使用帳戶 ${categories[i].accountUsageCount}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: () => _move(categories, i, -1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: () => _move(categories, i, 1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _edit(categories[i]),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(categories[i], categories),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

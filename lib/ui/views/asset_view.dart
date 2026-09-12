import 'package:flutter/material.dart';

class AssetView extends StatelessWidget {
  final String title;

  const AssetView({super.key, required this.title});

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
    ),
  );
}

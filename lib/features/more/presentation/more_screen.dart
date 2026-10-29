import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MoreItem {
  final String path;
  final String title;
  final IconData icon;
  const MoreItem(this.path, this.title, this.icon);
}

const moreItems = <MoreItem>[
  MoreItem('purchases', 'المشتريات', Icons.local_shipping_outlined),
  MoreItem('customers', 'العملاء', Icons.people_outline),
  MoreItem('suppliers', 'الموردون', Icons.factory_outlined),
  MoreItem('vehicles', 'توافق السيارات', Icons.directions_car_outlined),
  MoreItem('tags', 'الوسوم', Icons.sell_outlined),
  MoreItem('stocktaking', 'جرد المخزون', Icons.fact_check_outlined),
  MoreItem('reports', 'التقارير', Icons.bar_chart),
  MoreItem('activity', 'سجل العمليات', Icons.history),
  MoreItem('settings', 'الإعدادات', Icons.settings_outlined),
  MoreItem('backup', 'النسخ الاحتياطي والاستعادة', Icons.backup_outlined),
];

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(children: [
        for (final i in moreItems)
          ListTile(
            leading: Icon(i.icon),
            title: Text(i.title),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push('/more/${i.path}'),
          ),
      ]),
    );
  }
}

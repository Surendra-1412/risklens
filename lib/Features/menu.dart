import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.menu, size: 28.w),
      splashRadius: 24.r,
      onPressed: () => Scaffold.of(context).openDrawer(),
    );
  }
}

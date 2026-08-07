import 'package:flutter/widgets.dart';

/// Откуда «вырастает» системный лист «Поделиться» на iPad.
///
/// На iPhone лист выезжает снизу и точка не нужна. На iPad это popover, и
/// UIKit требует прямоугольник, к которому его прицепить: без него
/// `share_plus` молча не показывает ничего. Ревью Apple идёт как раз на iPad,
/// и кнопка, которая «не работает», возвращается отказом по 2.1.
///
/// Считать надо СИНХРОННО, до первого `await`: после него виджет мог уже
/// уехать с экрана, и `findRenderObject` вернёт пустоту.
Rect shareOriginFromContext(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  // Запасной вариант — точка в середине экрана: popover встанет по центру, но
  // встанет. Пустой прямоугольник UIKit не принимает.
  final size = MediaQuery.maybeOf(context)?.size ?? const Size(400, 800);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
}

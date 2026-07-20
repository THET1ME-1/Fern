/// Арифметика КАЛЕНДАРНЫХ дней.
///
/// `DateTime.subtract(Duration(days: 1))` отнимает ровно 24 часа, а сутки
/// столько длятся не всегда: весной, в ночь перевода стрелок, их 23, осенью —
/// 25. Отсюда `DateTime(2026, 3, 30).subtract(суткам)` даёт 28 марта, и 29-е
/// пролетает мимо. Переводом часов живут пять из семи языков приложения.
///
/// Конструктор `DateTime` нормализует выход за границы месяца сам, поэтому
/// `DateTime(y, m, d - 1)` — это соседняя дата в любой зоне и в любую ночь.
library;

/// Дата на [days] дней вперёд (или назад при отрицательном), время — полночь.
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Полночь того же дня.
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// [b] — календарно следующий день после [a].
bool isNextDay(DateTime a, DateTime b) => addDays(a, 1) == startOfDay(b);

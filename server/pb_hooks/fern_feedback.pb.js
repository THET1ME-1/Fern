/// fern_feedback.pb.js — обращение из приложения Fern (17.11.2026).
///
/// `POST /api/fern/feedback {kind, text, email?, app, platform, lang}`.
/// Аккаунт необязателен: вошедшему в Fern почту для ответа берём из аккаунта,
/// если он не вписал другую. Пределы — 5 в сутки с одного адреса и 200 в сутки
/// всего, счётчики в памяти (адрес нигде не пишется). Обращение ложится в
/// `fern_feedback`, потом письмом в ящик support@; не легло — крон раз в пять
/// минут досылает. Правила и письмо — `fern_feedback_mail.js`.
///
/// Деплой: оба файла в /opt/pocketbase/pb_hooks/ одним копированием,
/// PocketBase перечитает хуки сам. Живой прогон: `server/test_fern_feedback.py`.

routerAdd("POST", "/api/fern/feedback", (e) => {
  const F = require(`${__hooks}/fern_feedback_mail.js`);
  const body = new DynamicModel({ kind: "", text: "", email: "", app: "", platform: "", lang: "" });
  e.bindBody(body);

  // Сессия Fern необязательна, но если она есть, обращение подписано ею.
  let uid = "";
  let accountEmail = "";
  try {
    if (e.auth && e.auth.collection().name === "fern_users") {
      uid = e.auth.id;
      accountEmail = String(e.auth.getString("email") || "").trim();
    }
  } catch (_) {}

  const f = {
    uid: uid,
    kind: String(body.kind || "").trim(),
    text: String(body.text || "").trim(),
    email: String(body.email || "").trim() || accountEmail,
    app: String(body.app || "").trim().slice(0, 40),
    platform: String(body.platform || "").trim().slice(0, 20),
    lang: String(body.lang || "").trim().slice(0, 10),
  };
  const problem = F.problemOf(f);
  if (problem) return e.json(400, { ok: false, error: problem });

  const now = Date.now();
  const ipKey = F.dayKey(e.realIP(), now);
  const allKey = F.dayKey("all", now);
  const fromIp = Number($app.store().get(ipKey) || 0);
  const all = Number($app.store().get(allKey) || 0);
  if (fromIp >= F.PER_IP || all >= F.PER_DAY) {
    $app.logger().warn("fern feedback: предел", "all", all);
    return e.json(429, { ok: false, error: "too_many" });
  }

  let rec;
  try {
    rec = new Record(F.ensureCollection());
    for (const name of ["uid", "kind", "text", "email", "app", "platform", "lang"]) rec.set(name, f[name]);
    rec.set("delivered", false);
    $app.save(rec);
  } catch (err) {
    $app.logger().error("fern feedback: запись не сохранилась", "err", String(err));
    return e.json(500, { ok: false, error: "internal" });
  }
  $app.store().set(ipKey, fromIp + 1);
  $app.store().set(allKey, all + 1);

  // Сбой почты человеку не показываем: обращение уже у нас, крон дошлёт.
  try {
    if (F.deliver(F.fieldsOf(rec))) {
      rec.set("delivered", true);
      $app.save(rec);
    }
  } catch (err) {
    $app.logger().warn("fern feedback: письмо не легло, дошлёт крон", "id", rec.id, "err", String(err));
  }
  return e.json(200, { ok: true, id: rec.id, email: f.email });
});

// Досылка писем, которые не легли в ящик с первого раза.
cronAdd("fernFeedbackDeliver", "*/5 * * * *", () => {
  const F = require(`${__hooks}/fern_feedback_mail.js`);
  let waiting = [];
  try {
    waiting = $app.findRecordsByFilter("fern_feedback", "delivered = false", "created", 20, 0);
  } catch (_) { waiting = []; }
  for (let i = 0; i < waiting.length; i++) {
    const rec = waiting[i];
    try {
      if (F.deliver(F.fieldsOf(rec))) {
        rec.set("delivered", true);
        $app.save(rec);
      }
    } catch (err) {
      $app.logger().warn("fern feedback: досылка не прошла", "id", rec.id, "err", String(err));
      break;
    }
  }
});

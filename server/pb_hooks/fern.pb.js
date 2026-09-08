/// Подписка Fern Pro: счёт, статус, отмена.
///
/// Аккаунты Fern живут в СВОЕЙ коллекции `fern_users` и с аккаунтами
/// Togetherly не смешиваются: каждый роут проверяет, из какой коллекции
/// пришла сессия, и чужую не пускает.
///
/// Оплата идёт только через СЧЁТ, созданный API lava. Покупка по прямой
/// ссылке на витрину не порождает ни вебхука, ни записи в отчётах — на этом
/// Togetherly потерял две оплаты 31 июля, а Fern Pro полгода выдавался
/// разбором писем.
///
/// Талон подписывает локальная служба на 8160 (`fern_ticket.py`): JSVM не
/// умеет Ed25519, как не умеет RS256 для чеков Play.
///
/// Окружение PocketBase:
///   LAVA_API_KEY        — ключ продавца lava.top (общий с Togetherly)
///   FERN_OFFER_MONTH    — оффер тарифа «месяц»
///   FERN_OFFER_YEAR     — оффер тарифа «год»
///   FERN_TICKET_URL     — служба талонов (по умолчанию http://127.0.0.1:8160)
///   FERN_RETURN_URL     — куда вернуть после оплаты (по умолчанию fern://paid)
///
/// !!! ГРАБЛИ PB JSVM (см. coins.pb.js): обработчик исполняется в
/// ИЗОЛИРОВАННОМ пуле и НЕ видит функций уровня файла — всё инлайнится.

// ---------------------------------------------------------------- статус ---
routerAdd("GET", "/api/fern/me", (e) => {
  const user = e.auth;
  if (!user) return e.json(401, { ok: false, error: "unauthorized" });
  let collection = "";
  try { collection = user.collection().name; } catch (_) { collection = ""; }
  if (collection !== "fern_users") {
    return e.json(401, { ok: false, error: "wrong_account" });
  }

  const день = (v) => {
    const s = String(v || "").trim();
    return s.length >= 10 ? s.substring(0, 10) : "";
  };
  const сегодня = new Date().toISOString().substring(0, 10);

  // Запись перечитываем, а не берём из `e.auth`: в этой сборке аккаунт лежит
  // в кэше авторизации до двадцати секунд, и оплата, зачисленная вебхуком
  // секунду назад, была бы не видна ровно тому, кто её ждёт.
  let свежая = user;
  try { свежая = $app.findRecordById("fern_users", user.id); } catch (_) {}

  const until = день(свежая.get("pro_until"));
  const lifetime = свежая.getBool("lifetime");
  const статусПоля = String(свежая.get("pro_status") || "");
  const план = String(свежая.get("pro_plan") || "month") || "month";

  // Купившему навсегда талон тоже нужен: без него Pro не откроется на
  // компьютере, где ключа формата 2 нет.
  let срокДляТалона = until;
  if (lifetime) {
    const д = new Date();
    д.setDate(д.getDate() + 40);
    срокДляТалона = д.toISOString().substring(0, 10);
  }

  let состояние = "none";
  if (lifetime) состояние = "lifetime";
  else if (!until) состояние = "none";
  else if (статусПоля === "refunded") состояние = "refunded";
  else if (until < сегодня) состояние = "expired";
  else if (статусПоля === "cancelled") состояние = "cancelled";
  else состояние = "active";

  let ticket = null;
  let ticketUntil = null;
  const живая = состояние === "active" || состояние === "cancelled" ||
    состояние === "lifetime";
  if (живая && срокДляТалона) {
    try {
      const r = $http.send({
        url: ($os.getenv("FERN_TICKET_URL") || "http://127.0.0.1:8160") + "/ticket",
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          uid: user.id,
          email: String(свежая.getString("email") || ""),
          until: срокДляТалона,
          plan: план === "year" ? "year" : "month",
        }),
        timeout: 8,
      });
      const тело = (r && r.json) || {};
      if (тело.ok === true) {
        ticket = тело.ticket;
        ticketUntil = тело.until;
      }
    } catch (err) {
      // Служба талонов молчит — статус всё равно отдаём: приложение доживёт
      // на прежнем талоне, а без ответа оно решило бы, что подписки нет.
      console.log("[fern] талон не выдан: " + err);
    }
  }

  return e.json(200, {
    ok: true,
    until: until || null,
    status: состояние,
    source: String(свежая.get("pro_source") || "") || null,
    plan: план,
    lifetime: lifetime,
    ticket: ticket,
    ticket_until: ticketUntil,
  });
});

// ------------------------------------------------------------------ счёт ---
routerAdd("POST", "/api/fern/checkout", (e) => {
  const user = e.auth;
  if (!user) return e.json(401, { ok: false, error: "unauthorized" });
  let collection = "";
  try { collection = user.collection().name; } catch (_) { collection = ""; }
  if (collection !== "fern_users") {
    return e.json(401, { ok: false, error: "wrong_account" });
  }

  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }

  const план = String(body.plan || "month").toLowerCase();
  if (план !== "month" && план !== "year") {
    return e.json(400, { ok: false, error: "bad_plan" });
  }

  let currency = "RUB";
  const c = String(body.currency || "").toUpperCase();
  if (c === "EUR" || c === "USD") currency = c;
  let lang = "RU";
  const l = String(body.lang || "").toUpperCase();
  if (l === "EN" || l === "ES") lang = l;

  const оффер = String(
    план === "year" ? ($os.getenv("FERN_OFFER_YEAR") || "")
      : ($os.getenv("FERN_OFFER_MONTH") || "")).trim();
  if (!оффер) return e.json(500, { ok: false, error: "no_offer" });

  const apiKey = $os.getenv("LAVA_API_KEY") || "";
  if (!apiKey) return e.json(500, { ok: false, error: "no_api_key" });

  const возврат = $os.getenv("FERN_RETURN_URL") || "fern://paid";
  const email = String(user.getString("email") || "").trim().toLowerCase();

  let ответ = null;
  try {
    ответ = $http.send({
      url: "https://gate.lava.top/api/v2/invoice",
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Api-Key": apiKey },
      body: JSON.stringify({
        email: email,
        offerId: оффер,
        periodicity: план === "year" ? "PERIOD_YEAR" : "MONTHLY",
        currency: currency,
        buyerLanguage: lang,
        successful_return_url: возврат,
        failure_return_url: возврат.replace("paid", "failed"),
        cancel_return_url: возврат.replace("paid", "failed"),
      }),
      timeout: 25,
    });
  } catch (err) {
    console.log("[fern] счёт не создан: " + err);
    return e.json(502, { ok: false, error: "lava_unreachable" });
  }

  const данные = (ответ && ответ.json) || {};
  const ссылка = String(данные.paymentUrl || данные.payment_url || "");
  const счёт = String(данные.id || "");
  if (!ссылка || !счёт) {
    console.log("[fern] lava ответила без ссылки: " + JSON.stringify(данные));
    return e.json(502, { ok: false, error: "lava_bad_answer" });
  }

  // Заказ пишем сразу: по нему крон добьёт оплату, если вебхук потеряется.
  try {
    const коллекция = $app.findCollectionByNameOrId("fern_orders");
    const запись = new Record(коллекция);
    запись.set("order_key", "LAVA:" + счёт);
    запись.set("uid", user.id);
    запись.set("source", "lava");
    запись.set("plan", план);
    запись.set("status", "pending");
    запись.set("invoice_id", счёт);
    запись.set("email", email);
    запись.set("currency", currency);
    запись.set("event", "checkout");
    запись.set("raw", данные);
    $app.save(запись);
  } catch (err) {
    // Счёт уже создан, и человек вот-вот заплатит: ронять ответ нельзя.
    // Вебхук найдёт аккаунт по почте, даже если заказа в базе нет.
    console.log("[fern] заказ не записан: " + err);
  }

  return e.json(200, { ok: true, url: ссылка, orderId: счёт, plan: план });
});

// ---------------------------------------------------------------- отмена ---
routerAdd("POST", "/api/fern/cancel", (e) => {
  const user = e.auth;
  if (!user) return e.json(401, { ok: false, error: "unauthorized" });
  let collection = "";
  try { collection = user.collection().name; } catch (_) { collection = ""; }
  if (collection !== "fern_users") {
    return e.json(401, { ok: false, error: "wrong_account" });
  }

  let свежая = user;
  try { свежая = $app.findRecordById("fern_users", user.id); } catch (_) {}
  const контракт = String(свежая.get("lava_contract") || "").trim();
  const until = String(свежая.get("pro_until") || "").substring(0, 10);
  if (!контракт || !until) {
    return e.json(400, { ok: false, error: "no_subscription" });
  }

  const apiKey = $os.getenv("LAVA_API_KEY") || "";
  if (!apiKey) return e.json(500, { ok: false, error: "no_api_key" });
  const email = String(user.getString("email") || "").trim().toLowerCase();

  let код = 0;
  try {
    const r = $http.send({
      url: "https://gate.lava.top/api/v1/subscriptions?contractId=" +
        encodeURIComponent(контракт) + "&email=" + encodeURIComponent(email),
      method: "DELETE",
      headers: { "X-Api-Key": apiKey },
      timeout: 25,
    });
    код = r ? r.statusCode : 0;
  } catch (err) {
    console.log("[fern] отмена не прошла: " + err);
    return e.json(502, { ok: false, error: "lava_unreachable" });
  }

  // 404 у lava значит «такой подписки нет» — для человека это тоже отмена.
  if (код !== 204 && код !== 200 && код !== 404) {
    return e.json(502, { ok: false, error: "lava_refused", code: код });
  }

  try {
    const запись = $app.findRecordById("fern_users", user.id);
    запись.set("pro_status", "cancelled");
    $app.save(запись);
  } catch (err) {
    console.log("[fern] статус не записан: " + err);
  }

  // Доступ работает до конца оплаченного периода: человек заплатил за месяц.
  return e.json(200, { ok: true, until: until });
});

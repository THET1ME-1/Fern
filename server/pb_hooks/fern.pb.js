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
///   FERN_RETURN_URL     — куда вернуть после оплаты. Это ОБЯЗАТЕЛЬНО адрес
///                         https: lava.top отвергает схему приложения
///                         («successful_return_url must be a valid HTTPS URL»),
///                         поэтому возврат идёт через страницу-переходник
///                         /api/fern/paid, а она уже открывает fern://paid.
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

  // Заплатил до регистрации: заказ ждёт хозяина. Ищем его по почте и
  // отдаём подписку тому, кто наконец завёл аккаунт.
  if (!String(свежая.get("pro_until") || "")) {
    try {
      const заказ = $app.findFirstRecordByFilter(
        "fern_orders", "email = {:e} && status = 'paid' && uid = ''",
        { e: String(свежая.getString("email") || "").toLowerCase() });
      if (заказ) {
        const до = String(заказ.get("until") || "");
        if (до) {
          свежая.set("pro_until", до);
          свежая.set("pro_status", "active");
          свежая.set("pro_source", String(заказ.get("source") || "lava"));
          свежая.set("pro_plan", String(заказ.get("plan") || "month"));
          $app.save(свежая);
          заказ.set("uid", свежая.id);
          $app.save(заказ);
        }
      }
    } catch (_) {}
  }

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

  // Какие тарифы вообще можно купить. Годовой заводится в кабинете lava
  // (API создавать офферы не умеет: «You can only update existing offers»),
  // и пока его нет, приложению незачем рисовать кнопку, которая ответит
  // ошибкой.
  const тарифы = [];
  if (String($os.getenv("FERN_OFFER_MONTH") || "").trim()) тарифы.push("month");
  if (String($os.getenv("FERN_OFFER_YEAR") || "").trim()) тарифы.push("year");

  return e.json(200, {
    ok: true,
    plans: тарифы,
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

  const возврат = $os.getenv("FERN_RETURN_URL") ||
    "https://togetherly.duckdns.org/api/fern/paid";
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

// ------------------------------------------------ приём событий lava.top ---
///
/// Сюда попадают уведомления, в которых узнан товар Fern: боевой роут
/// `/api/lava/webhook` (Togetherly) пересылает их одной строкой, а вся
/// обработка подписки живёт здесь. Так правка чужого файла остаётся в
/// пределах развилки, а логика Fern не размазывается по двум приложениям.
///
/// События берём как есть из документации lava.top:
///   payment.success + status=subscription-active     первый платёж
///   subscription.recurring.payment.success           продление
///   subscription.recurring.payment.failed            неудачная попытка
///   subscription.cancelled + willExpireAt            отмена
///   refund.success, chargeback.initiated             возврат
routerAdd("POST", "/api/fern/lava", (e) => {
  const secret = $os.getenv("LAVA_WEBHOOK_KEY") || "";
  const basic = ($os.getenv("LAVA_BASIC") || "").trim();
  const given = e.request.header.get("X-Api-Key") ||
    e.request.url.query().get("key") || "";
  const auth = (e.request.header.get("Authorization") || "").trim();
  const okKey = secret !== "" && given === secret;
  const okBasic = basic !== "" && auth === "Basic " + basic;
  if (!okKey && !okBasic) return e.json(401, { ok: false, error: "bad_key" });

  let payload = {};
  try { payload = e.requestInfo().body || {}; } catch (_) { payload = {}; }

  // Поля ищем по всему дереву: у возврата и чарджбека своя обёртка `data`,
  // а у платежей поля лежат на верхнем уровне.
  const flat = {};
  const walk = (node, path) => {
    if (node === null || node === undefined) return;
    if (typeof node !== "object") { flat[path.toLowerCase()] = String(node); return; }
    for (const key in node) walk(node[key], path ? path + "." + key : key);
  };
  walk(payload, "");
  // Порядок имён — это ПРИОРИТЕТ, и внешним циклом обязан идти он, а не
  // обход дерева: ключи объекта в JSVM перебираются в случайном порядке, и
  // обратная вложенность циклов выдавала то `contractId`, то
  // `parentContractId`. Продление с чужим номером выглядело повтором первого
  // платежа, и месяц не начислялся — через раз, что хуже, чем никогда.
  const pick = (names) => {
    for (let i = 0; i < names.length; i++) {
      for (const key in flat) {
        const tail = key.split(".").pop();
        if (tail === names[i] || key === names[i]) return flat[key];
      }
    }
    return "";
  };

  const МЕСЯЦ = String($os.getenv("FERN_OFFER_MONTH") || "").trim().toLowerCase();
  const ГОД = String($os.getenv("FERN_OFFER_YEAR") || "").trim().toLowerCase();
  // Тариф «год разовой оплатой»: у lava нельзя ни удалить тариф, ни сменить
  // ему период, поэтому он остался на витрине. Приложение его не предлагает,
  // но покупка по нему должна открывать год, а не пропадать.
  const ГОД_РАЗОМ = String($os.getenv("FERN_OFFER_YEAR_ONCE") || "")
    .trim().toLowerCase();
  const SKU = String($os.getenv("FERN_SKU") || "").trim().toLowerCase();

  // Тариф узнаём по офферу: в уведомлении приезжает либо товар, либо оффер.
  let план = "";
  for (const key in flat) {
    const v = String(flat[key]).trim().toLowerCase();
    if (ГОД && v === ГОД) { план = "year"; break; }
    if (ГОД_РАЗОМ && v === ГОД_РАЗОМ) { план = "year"; break; }
    if (МЕСЯЦ && v === МЕСЯЦ) { план = "month"; break; }
    if (SKU && v === SKU) { план = "month"; }
  }
  if (!план) return e.json(200, { ok: true, skipped: "not_fern" });

  const событие = (pick(["eventtype", "event_type", "event"]) || "").toLowerCase();
  const статус = (pick(["status", "state"]) || "").toLowerCase();
  const почта = (pick(["email", "customer_email", "buyeremail", "clientemail"]) || "")
    .trim().toLowerCase();
  const контракт = (pick(["contractid", "orderid", "invoiceid", "refund_id",
                          "parentcontractid"]) || "").trim();
  const родитель = (pick(["parentcontractid"]) || "").trim();
  const истечёт = (pick(["willexpireat"]) || "").trim();

  if (!почта) return e.json(400, { ok: false, error: "no_email" });

  const возврат = событие.indexOf("refund") !== -1 ||
    событие.indexOf("chargeback") !== -1;
  const отмена = событие.indexOf("cancel") !== -1;
  const удача = !возврат && !отмена && (
    статус.indexOf("subscription-active") !== -1 ||
    статус.indexOf("success") !== -1 ||
    статус.indexOf("paid") !== -1 ||
    статус.indexOf("completed") !== -1);
  const неудача = !возврат && !отмена && !удача;

  // Сдвиг на период с оглядкой на длину месяца: 31 января плюс месяц это
  // 28 февраля, а не 3 марта.
  const сдвиг = (от, план) => {
    const д = new Date(от.getTime());
    const день = д.getUTCDate();
    if (план === "year") {
      д.setUTCFullYear(д.getUTCFullYear() + 1);
    } else {
      д.setUTCMonth(д.getUTCMonth() + 1);
      if (д.getUTCDate() < день) д.setUTCDate(0);
    }
    return д;
  };

  const ключЗаказа = "LAVA:" + (контракт || (почта + план));
  let out = { s: 500, b: { ok: false, error: "internal" } };

  try {
    $app.runInTransaction((tx) => {
      let заказ = null;
      try {
        заказ = tx.findFirstRecordByFilter("fern_orders", "order_key = {:k}",
                                           { k: ключЗаказа });
      } catch (_) { заказ = null; }

      // Повтор уведомления об оплате: срок уже начислен, второй раз не даём.
      if (заказ && удача && String(заказ.get("status")) === "paid") {
        out = { s: 200, b: { ok: true, repeated: true } };
        return;
      }

      let человек = null;
      try {
        человек = tx.findFirstRecordByFilter("fern_users", "email = {:e}",
                                             { e: почта });
      } catch (_) { человек = null; }

      const сейчас = new Date();
      let срок = null;

      if (удача) {
        // Продление считаем от прежнего срока, а не от сегодняшнего дня:
        // иначе человек, заплативший заранее, теряет оплаченные дни.
        let база = сейчас;
        if (человек) {
          const было = String(человек.get("pro_until") || "");
          if (было) {
            const d = new Date(было.replace(" ", "T"));
            if (!isNaN(d.getTime()) && d.getTime() > сейчас.getTime()) база = d;
          }
        }
        срок = сдвиг(база, план);
      } else if (отмена && истечёт) {
        const d = new Date(истечёт.replace(" ", "T"));
        if (!isNaN(d.getTime())) срок = d;
      } else if (возврат) {
        срок = сейчас;
      }

      if (человек) {
        if (удача) {
          человек.set("pro_until", срок.toISOString());
          человек.set("pro_status", "active");
          человек.set("pro_source", "lava");
          человек.set("pro_plan", план);
          // Контракт подписки: по нему идёт отмена и суточная сверка.
          человек.set("lava_contract", родитель || контракт);
          tx.save(человек);
        } else if (отмена) {
          человек.set("pro_status", "cancelled");
          if (срок) человек.set("pro_until", срок.toISOString());
          tx.save(человек);
        } else if (возврат) {
          человек.set("pro_status", "refunded");
          человек.set("pro_until", сейчас.toISOString());
          tx.save(человек);
        }
      }

      // Заказ пишем всегда: он и след для разбирательств, и защита от повтора,
      // и способ отдать подписку тому, кто заплатил ДО регистрации.
      if (!заказ) {
        заказ = new Record(tx.findCollectionByNameOrId("fern_orders"));
        заказ.set("order_key", ключЗаказа);
      }
      заказ.set("uid", человек ? человек.id : "");
      заказ.set("source", "lava");
      заказ.set("plan", план);
      заказ.set("email", почта);
      заказ.set("event", событие || статус || "unknown");
      заказ.set("invoice_id", контракт);
      заказ.set("status", удача ? "paid"
        : отмена ? "cancelled" : возврат ? "refunded" : "failed");
      if (срок) заказ.set("until", срок.toISOString());
      if (удача || возврат) заказ.set("paid_at", сейчас.toISOString());
      заказ.set("raw", payload);
      tx.save(заказ);

      out = {
        s: 200,
        b: {
          ok: true,
          granted: удача && !!человек,
          pending_account: удача && !человек,
          cancelled: отмена,
          refunded: возврат,
          failed: неудача,
        },
      };
    });
  } catch (err) {
    console.log("[fern] вебхук не обработан: " + err);
    return e.json(500, { ok: false, error: "internal" });
  }

  return e.json(out.s, out.b);
});

// ------------------------------------------- страховки: сверка с продавцом ---
///
/// Вебхук теряется — это правило, а не исключение: у Togetherly первая же
/// живая покупка ушла в пустоту. Поэтому есть два прохода.
///
///   • быстрый (раз в две минуты) добивает СВЕЖИЕ заказы `pending`: спрашивает
///     счёт и, если он оплачен, открывает подписку;
///   • полный (раз в сутки) сверяет срок активных подписок с `expiredAt`
///     продавца — им же лечится пропущенное продление.
///
/// Адрес lava можно передать в теле (`lava_base`) — этим пользуется тест,
/// подставляя заглушку. Роут закрыт ключом вебхука, снаружи его не позвать.
routerAdd("POST", "/api/fern/sync", (e) => {
  const secret = $os.getenv("LAVA_WEBHOOK_KEY") || "";
  const given = e.request.header.get("X-Api-Key") ||
    e.request.url.query().get("key") || "";
  if (!secret || given !== secret) {
    return e.json(401, { ok: false, error: "bad_key" });
  }

  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const база = String(body.lava_base || $os.getenv("LAVA_API_BASE") ||
    "https://gate.lava.top").replace(/\/+$/, "");
  const полный = body.full === true || String(body.full || "") === "true";
  const apiKey = $os.getenv("LAVA_API_KEY") || "";
  // Адрес проверки чеков — свой, отдельный от адреса lava: в тесте оба ведут
  // на заглушку, в бою это разные службы.
  let базаПроверки = $os.getenv("FERN_VERIFY_URL") || "http://127.0.0.1:8097";
  if (body.verify_base) базаПроверки = String(body.verify_base);

  const сдвиг = (от, план) => {
    const д = new Date(от.getTime());
    const день = д.getUTCDate();
    if (план === "year") {
      д.setUTCFullYear(д.getUTCFullYear() + 1);
    } else {
      д.setUTCMonth(д.getUTCMonth() + 1);
      if (д.getUTCDate() < день) д.setUTCDate(0);
    }
    return д;
  };

  let оплачено = 0;
  let сверено = 0;
  const сейчас = new Date();

  // --- 1. Свежие неоплаченные заказы ---
  let заказы = [];
  try {
    // Дата в фильтре пишется в формате хранения PocketBase: с пробелом, а не
    // с «T». ISO-строка молча не находит ничего — фильтр не ошибка, а ноль
    // записей, и потерянные оплаты копились бы незаметно.
    const час = new Date(сейчас.getTime() - 60 * 60 * 1000)
      .toISOString().replace("T", " ");
    заказы = $app.findRecordsByFilter(
      "fern_orders", "status = 'pending' && created > {:t}", "-created", 50, 0,
      { t: час });
  } catch (err) {
    console.log("[fern] заказы не прочитаны: " + err);
    заказы = [];
  }

  for (let i = 0; i < заказы.length; i++) {
    const заказ = заказы[i];
    const счёт = String(заказ.get("invoice_id") || "");
    if (!счёт) continue;
    let данные = null;
    try {
      const r = $http.send({
        url: база + "/api/v1/invoices/" + encodeURIComponent(счёт),
        method: "GET",
        headers: { "X-Api-Key": apiKey },
        timeout: 20,
      });
      данные = (r && r.statusCode === 200 && r.json) || null;
    } catch (_) { данные = null; }
    if (!данные) continue;

    const статус = String(данные.status || данные.subscriptionStatus || "")
      .toUpperCase();
    if (статус !== "COMPLETED" && статус !== "ACTIVE") continue;

    const план = String(заказ.get("plan") || "month");
    let человек = null;
    try {
      const uid = String(заказ.get("uid") || "");
      if (uid) человек = $app.findRecordById("fern_users", uid);
    } catch (_) { человек = null; }
    if (!человек) {
      try {
        человек = $app.findFirstRecordByFilter("fern_users", "email = {:e}",
          { e: String(заказ.get("email") || "") });
      } catch (_) { человек = null; }
    }

    let база_срока = сейчас;
    if (человек) {
      const было = String(человек.get("pro_until") || "");
      if (было) {
        const d = new Date(было.replace(" ", "T"));
        if (!isNaN(d.getTime()) && d.getTime() > сейчас.getTime()) база_срока = d;
      }
    }
    const срок = сдвиг(база_срока, план);

    if (человек) {
      человек.set("pro_until", срок.toISOString());
      человек.set("pro_status", "active");
      человек.set("pro_source", "lava");
      человек.set("pro_plan", план);
      const контракт = String(данные.parentContractId || данные.id || счёт);
      человек.set("lava_contract", контракт);
      try { $app.save(человек); } catch (err) { console.log("[fern] " + err); }
    }
    заказ.set("status", "paid");
    заказ.set("until", срок.toISOString());
    заказ.set("paid_at", сейчас.toISOString());
    заказ.set("event", "sync");
    try { $app.save(заказ); } catch (err) { console.log("[fern] " + err); }
    оплачено++;
  }

  // --- 2. Сверка активных подписок ---
  if (полный) {
    let люди = [];
    try {
      люди = $app.findRecordsByFilter(
        "fern_users", "lava_contract != '' && pro_status != 'refunded'",
        "-updated", 500, 0);
    } catch (err) {
      console.log("[fern] подписки не прочитаны: " + err);
      люди = [];
    }
    for (let i = 0; i < люди.length; i++) {
      const человек = люди[i];
      const контракт = String(человек.get("lava_contract") || "");
      if (!контракт) continue;
      let данные = null;
      try {
        const r = $http.send({
          url: база + "/api/v1/subscriptions/" + encodeURIComponent(контракт),
          method: "GET",
          headers: { "X-Api-Key": apiKey },
          timeout: 20,
        });
        данные = (r && r.statusCode === 200 && r.json) || null;
      } catch (_) { данные = null; }
      // Продавец молчит или не знает такой подписки — НИЧЕГО не трогаем:
      // погасить доступ из-за чужого сбоя хуже, чем подарить лишний день.
      if (!данные) continue;

      const истекает = String(данные.expiredAt || "");
      const статус = String(данные.subscriptionStatus || "").toUpperCase();
      let изменено = false;
      if (истекает) {
        const d = new Date(истекает.replace(" ", "T"));
        const было = String(человек.get("pro_until") || "");
        if (!isNaN(d.getTime()) && было.substring(0, 10) !== d.toISOString().substring(0, 10)) {
          человек.set("pro_until", d.toISOString());
          изменено = true;
        }
      }
      if (статус === "CANCELLED" && String(человек.get("pro_status")) !== "cancelled") {
        человек.set("pro_status", "cancelled");
        изменено = true;
      }
      if (статус === "ACTIVE" && String(человек.get("pro_status")) === "cancelled") {
        // Человек вернулся: подписка снова активна у продавца.
        человек.set("pro_status", "active");
        изменено = true;
      }
      if (изменено) {
        try { $app.save(человек); сверено++; } catch (err) { console.log("[fern] " + err); }
      }
    }
  }

  // --- 3. Сверка магазинных подписок ---
  //
  // Уведомления Google требуют Pub/Sub в консоли, а его включение нам не
  // отдали. Поэтому срок спрашиваем сами: раз в сутки проходим по магазинным
  // заказам и обновляем то, что продлилось или кончилось. Продление доезжает
  // за сутки вместо «когда человек откроет приложение».
  let магазинных = 0;
  if (полный) {
    let заказыМагазинов = [];
    try {
      заказыМагазинов = $app.findRecordsByFilter(
        "fern_orders", "status = 'paid' && (source = 'play' || source = 'apple')",
        "-updated", 500, 0);
    } catch (err) {
      console.log("[fern] магазинные заказы не прочитаны: " + err);
      заказыМагазинов = [];
    }
    for (let i = 0; i < заказыМагазинов.length; i++) {
      const заказ = заказыМагазинов[i];
      const платформа = String(заказ.get("source") || "");
      // У Apple свой путь: их серверное API требует отдельного ключа покупок,
      // которого у нас нет. Там продление приносит сам чек при запуске плюс
      // шестнадцатидневная льгота, включённая в App Store Connect.
      if (платформа !== "play") continue;
      const чек = String(заказ.get("order_key") || "").replace(/^PLAY:/, "");
      if (!чек) continue;
      let вердикт = null;
      try {
        const r = $http.send({
          url: базаПроверки.replace(/\/+$/, "") + "/verify",
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            store: "play", kind: "subscription",
            productId: String(заказ.get("plan")) === "year"
              ? "fern_pro_year" : "fern_pro_month",
            purchaseToken: чек,
            package: $os.getenv("FERN_PLAY_PACKAGE") || "com.fern.app",
          }),
          timeout: 25,
        });
        вердикт = (r && r.json) || null;
      } catch (_) { вердикт = null; }
      if (!вердикт || вердикт.ok !== true) continue;

      let человек = null;
      try {
        человек = $app.findRecordById("fern_users", String(заказ.get("uid") || ""));
      } catch (_) { человек = null; }
      if (!человек) continue;

      let изменено = false;
      if (вердикт.valid === true && вердикт.expiry) {
        const d = new Date(String(вердикт.expiry).replace(" ", "T"));
        const было = String(человек.get("pro_until") || "");
        if (!isNaN(d.getTime()) &&
            было.substring(0, 10) !== d.toISOString().substring(0, 10)) {
          человек.set("pro_until", d.toISOString());
          заказ.set("until", d.toISOString());
          изменено = true;
        }
        const статус = вердикт.cancelled === true ? "cancelled" : "active";
        if (String(человек.get("pro_status")) !== статус) {
          человек.set("pro_status", статус);
          изменено = true;
        }
      } else if (вердикт.valid === false &&
                 String(вердикт.state || "").indexOf("EXPIRED") !== -1 &&
                 String(человек.get("pro_status")) !== "expired") {
        человек.set("pro_status", "expired");
        изменено = true;
      }
      if (изменено) {
        try {
          $app.save(человек);
          $app.save(заказ);
          магазинных++;
        } catch (err) { console.log("[fern] " + err); }
      }
    }
  }

  return e.json(200, {
    ok: true, paid: оплачено, synced: сверено, stores: магазинных,
  });
});

// Кроны зовут тот же роут: логика синхронизации живёт в одном месте и
// проверяется тестом снаружи, а не прячется внутри расписания.
cronAdd("fern_pending", "*/2 * * * *", () => {
  try {
    $http.send({
      url: "http://127.0.0.1:8090/api/fern/sync",
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Api-Key": $os.getenv("LAVA_WEBHOOK_KEY") || "",
      },
      body: "{}",
      timeout: 60,
    });
  } catch (err) {
    console.log("[fern] быстрый проход не прошёл: " + err);
  }
});

cronAdd("fern_full_sync", "17 4 * * *", () => {
  try {
    $http.send({
      url: "http://127.0.0.1:8090/api/fern/sync",
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Api-Key": $os.getenv("LAVA_WEBHOOK_KEY") || "",
      },
      body: JSON.stringify({ full: true }),
      timeout: 300,
    });
  } catch (err) {
    console.log("[fern] суточная сверка не прошла: " + err);
  }
});

// ------------------------------------------------- чеки Play и App Store ---
///
/// Магазинную подписку человек оформляет в кассе магазина, а срок всё равно
/// сводится сюда: иначе купленное в Play не откроется ни в вебе, ни на
/// компьютере, ни в сборке с сайта.
///
/// Чек проверяет локальная служба на 8097 (`play_verify.py`): RS256 для
/// Google и разбор JWS для Apple в JSVM недоступны.
///
/// POST /api/fern/store { platform: "play"|"apple", productId, token }
routerAdd("POST", "/api/fern/store", (e) => {
  const user = e.auth;
  if (!user) return e.json(401, { ok: false, error: "unauthorized" });
  let collection = "";
  try { collection = user.collection().name; } catch (_) { collection = ""; }
  if (collection !== "fern_users") {
    return e.json(401, { ok: false, error: "wrong_account" });
  }

  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const платформа = String(body.platform || "play").toLowerCase();
  const товар = String(body.productId || "").trim();
  const чек = String(body.token || "").trim();
  if (!товар || !чек) return e.json(400, { ok: false, error: "no_receipt" });

  // Тариф узнаём по товару: имена заданы нами в обеих консолях.
  const план = товар.indexOf("year") !== -1 ? "year" : "month";

  // Адрес проверяющей службы можно подменить, но только тому, кто знает ключ
  // вебхука: этим пользуется тест, а снаружи ключа нет.
  const secret = $os.getenv("LAVA_WEBHOOK_KEY") || "";
  const given = e.request.header.get("X-Api-Key") || "";
  let база = $os.getenv("FERN_VERIFY_URL") || "http://127.0.0.1:8097";
  if (secret && given === secret && body.verify_base) {
    база = String(body.verify_base);
  }

  let вердикт = null;
  try {
    const r = $http.send({
      url: база.replace(/\/+$/, "") + "/verify",
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        store: платформа === "apple" ? "appstore" : "play",
        kind: "subscription",
        productId: товар,
        purchaseToken: чек,
        package: $os.getenv("FERN_PLAY_PACKAGE") || "com.fern.app",
        bundleId: $os.getenv("FERN_BUNDLE_ID") || "com.fern.flashcards",
      }),
      timeout: 30,
    });
    вердикт = (r && r.json) || null;
  } catch (err) {
    console.log("[fern] чек не проверен: " + err);
    return e.json(502, { ok: false, error: "verify_unreachable" });
  }

  if (!вердикт || вердикт.ok !== true) {
    // Сбой проверки — НЕ отказ покупателю: у него чек на руках, а у нас
    // молчит Google. Пусть приложение попробует ещё раз позже.
    return e.json(502, { ok: false, error: "verify_failed" });
  }
  if (вердикт.valid !== true) {
    return e.json(400, { ok: false, error: "not_valid", reason: вердикт.reason });
  }

  const срок = String(вердикт.expiry || "");
  if (!срок) return e.json(400, { ok: false, error: "no_expiry" });
  const дата = new Date(срок.replace(" ", "T"));
  if (isNaN(дата.getTime())) return e.json(400, { ok: false, error: "bad_expiry" });

  let out = { s: 500, b: { ok: false, error: "internal" } };
  try {
    $app.runInTransaction((tx) => {
      const человек = tx.findRecordById("fern_users", user.id);
      // Берём максимум: человек мог купить и в магазине, и на lava, и терять
      // оплаченные дни из-за этого он не должен.
      let итог = дата;
      const было = String(человек.get("pro_until") || "");
      if (было) {
        const d = new Date(было.replace(" ", "T"));
        if (!isNaN(d.getTime()) && d.getTime() > дата.getTime()) итог = d;
      }
      человек.set("pro_until", итог.toISOString());
      человек.set("pro_status", вердикт.cancelled === true ? "cancelled" : "active");
      человек.set("pro_source", платформа === "apple" ? "apple" : "play");
      человек.set("pro_plan", план);
      tx.save(человек);

      // Заказ на магазинную подписку один: токен при продлении не меняется,
      // меняется только срок.
      const ключ = (платформа === "apple" ? "APPLE:" : "PLAY:") +
        (вердикт.transactionId || чек);
      let заказ = null;
      try {
        заказ = tx.findFirstRecordByFilter("fern_orders", "order_key = {:k}",
                                           { k: ключ });
      } catch (_) { заказ = null; }
      if (!заказ) {
        заказ = new Record(tx.findCollectionByNameOrId("fern_orders"));
        заказ.set("order_key", ключ);
      }
      заказ.set("uid", человек.id);
      заказ.set("email", String(человек.getString("email") || ""));
      заказ.set("source", платформа === "apple" ? "apple" : "play");
      // Идентификатор, по которому магазин потом присылает продления: у Apple
      // это первая сделка, у Google — тот же токен покупки.
      заказ.set("invoice_id", платформа === "apple"
        ? String(вердикт.originalTransactionId || вердикт.transactionId || чек)
        : чек);
      заказ.set("plan", план);
      заказ.set("status", "paid");
      заказ.set("event", "store_receipt");
      заказ.set("until", итог.toISOString());
      заказ.set("paid_at", new Date().toISOString());
      заказ.set("raw", вердикт);
      tx.save(заказ);

      out = { s: 200, b: { ok: true, until: итог.toISOString().substring(0, 10) } };
    });
  } catch (err) {
    console.log("[fern] чек не записан: " + err);
    return e.json(500, { ok: false, error: "internal" });
  }
  return e.json(out.s, out.b);
});


// -------------------------------------------------- возврат после оплаты ---
///
/// lava.top принимает только адреса https («successful_return_url must be a
/// valid HTTPS URL»), а вернуть человека надо в приложение. Поэтому оплата
/// приводит сюда, а страница открывает `fern://paid` сама. Не сработало
/// (браузер без приложения, чужой телефон) — человек видит понятную строку, а
/// Pro всё равно включится: приложение спрашивает сервер при первом запуске.
///
/// !!! Разметка ИНЛАЙНОМ в каждом обработчике: функции уровня файла в
/// изолированном пуле JSVM не видны, и общая на двоих роняла ответ в 400.
routerAdd("GET", "/api/fern/paid", (e) => {
  return e.html(200, `<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Оплачено</title>
<style>
 body{margin:0;min-height:100vh;display:grid;place-items:center;
      background:#0f1511;color:#dee4de;
      font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
 main{max-width:22rem;padding:2rem;text-align:center}
 h1{font-size:1.35rem;margin:0 0 .75rem}
 p{margin:0 0 1.25rem;color:#c0c9c1}
 a{display:inline-block;padding:.85rem 1.5rem;border-radius:999px;
   background:#8ed5b0;color:#003824;text-decoration:none;font-weight:600}
</style></head><body><main>
<h1>Оплата прошла</h1>
<p>Возвращаемся в Fern. Если приложение не открылось само, откройте его —
подписка уже на месте.</p>
<a href="fern://paid">Открыть Fern</a>
<script>setTimeout(function(){location.href="fern://paid"},400)</script>
</main></body></html>`);
});

routerAdd("GET", "/api/fern/failed", (e) => {
  return e.html(200, `<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Оплата не прошла</title>
<style>
 body{margin:0;min-height:100vh;display:grid;place-items:center;
      background:#0f1511;color:#dee4de;
      font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
 main{max-width:22rem;padding:2rem;text-align:center}
 h1{font-size:1.35rem;margin:0 0 .75rem}
 p{margin:0 0 1.25rem;color:#c0c9c1}
 a{display:inline-block;padding:.85rem 1.5rem;border-radius:999px;
   background:#8ed5b0;color:#003824;text-decoration:none;font-weight:600}
</style></head><body><main>
<h1>Оплата не прошла</h1>
<p>Деньги не списаны. Откройте Fern и попробуйте ещё раз.</p>
<a href="fern://failed">Открыть Fern</a>
<script>setTimeout(function(){location.href="fern://failed"},400)</script>
</main></body></html>`);
});

// --------------------------------------------------- нативный вход Apple ---
///
/// На iPhone вход через браузер отказывает у части людей: у Togetherly за
/// сутки набралось 77 обрывов загрузки `appleid.apple.com` против 33 удачных
/// входов на 57 разных телефонах, притом в журнале сервера за те же сутки одна
/// ошибка — до нас дело просто не доходило. Лечится не браузером, а способом:
/// системный диалог отдаёт подписанный токен, и его мы меняем на сессию.
///
/// Подпись проверяет релей `apns_relay.py` (RS256 и ключи Apple в JSVM
/// недоступны). Аудитории токена он берёт из `APPLE_AUDIENCES`, куда добавлен
/// bundle Fern.
///
/// POST /api/fern/apple { identityToken, nonce?, name? }
///   → 200 { token, record }  — как обычный вход, клиент сохраняет сессию
///   → 4xx { ok: false, reason }
routerAdd("POST", "/api/fern/apple", (e) => {
  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const идентификатор = String(body.identityToken || "").trim();
  const nonce = String(body.nonce || "");

  const отказ = (код, причина) => {
    try {
      $app.logger().warn("fern apple: отказ", "reason", причина);
    } catch (_) {}
    return e.json(код, { ok: false, reason: причина });
  };

  if (!идентификатор) return отказ(400, "нет identityToken");

  let утверждения = {};
  try {
    const r = $http.send({
      url: ($os.getenv("FERN_APPLE_VERIFY_URL") || "http://127.0.0.1:8096") +
        "/apple/verify",
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: идентификатор, nonce: nonce }),
      timeout: 20,
    });
    утверждения = (r && r.json) || {};
  } catch (err) {
    return отказ(502, "проверка токена недоступна: " + String(err));
  }
  if (утверждения.ok !== true) {
    return отказ(401, String(утверждения.reason || "токен не принят"));
  }

  const sub = String(утверждения.sub || "");
  const почта = String(утверждения.email || "").toLowerCase();
  if (!sub) return отказ(401, "в токене нет sub");

  const коллекция = $app.findCollectionByNameOrId("fern_users");
  let человек = null;

  // Человека ищем по `sub`: у одного Apple ID внутри команды он один и тот же,
  // поэтому вошедшие раньше через браузер попадают в свой прежний аккаунт, а
  // не заводят второй.
  try {
    const связка = $app.findFirstRecordByFilter(
      "_externalAuths",
      "provider = 'apple' && providerId = {:sub} && collectionRef = {:col}",
      { sub: sub, col: коллекция.id },
    );
    человек = $app.findRecordById("fern_users", связка.getString("recordRef"));
  } catch (_) { человек = null; }

  // Почта Apple у человека постоянна (в том числе «…@privaterelay.appleid.com»),
  // и ею закрывается случай, когда связки нет, а аккаунт уже заведён почтой.
  if (!человек && почта) {
    try {
      человек = $app.findFirstRecordByFilter("fern_users", "email = {:e}",
                                             { e: почта });
    } catch (_) { человек = null; }
  }

  let создан = false;
  if (!человек) {
    try {
      человек = new Record(коллекция);
      человек.set("email", почта);
      человек.set("emailVisibility", false);
      человек.set("verified", true);
      // Пароль человеку не нужен — он входит системным диалогом, — но поле
      // обязательное: кладём случайный и никому не показываем.
      const случайный = $security.randomString(40);
      человек.set("password", случайный);
      человек.set("passwordConfirm", случайный);
      $app.save(человек);
      создан = true;
    } catch (err) {
      return отказ(500, "аккаунт не создан: " + String(err));
    }
  }

  try {
    $app.findFirstRecordByFilter(
      "_externalAuths",
      "provider = 'apple' && providerId = {:sub} && collectionRef = {:col}",
      { sub: sub, col: коллекция.id },
    );
  } catch (_) {
    try {
      const связка = new Record($app.findCollectionByNameOrId("_externalAuths"));
      связка.set("collectionRef", коллекция.id);
      связка.set("provider", "apple");
      связка.set("providerId", sub);
      связка.set("recordRef", человек.id);
      $app.save(связка);
    } catch (err) {
      // Вход состоится и так: в следующий раз человека найдём по почте.
      console.log("[fern] связка Apple не создана: " + err);
    }
  }

  try {
    return $apis.recordAuthResponse(e, человек, "apple", { created: создан });
  } catch (err) {
    try {
      return e.json(200, {
        token: String(человек.newAuthToken()),
        record: человек.publicExport(),
        created: создан,
      });
    } catch (err2) {
      return отказ(500, "не удалось выдать сессию: " + String(err2));
    }
  }
});

// ------------------------------------- уведомления магазинов о продлении ---
///
/// Без них продление узнаётся только когда человек откроет приложение: талон
/// живёт неделю сверх оплаченного, и молчание дольше недели гасит Pro у того,
/// кто заплатил. Уведомления закрывают этот разрыв.
///
/// Apple шлёт подписанный конверт (Server Notifications V2), Google — сообщение
/// Pub/Sub с base64 внутри. Общее у них одно: доверять содержимому нельзя,
/// поэтому срок всегда перепроверяется у магазина.

/// POST /api/fern/apple-notify — App Store Server Notifications V2.
routerAdd("POST", "/api/fern/apple-notify", (e) => {
  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const конверт = String(body.signedPayload || "");
  if (!конверт) return e.json(400, { ok: false, error: "no_payload" });

  // Адрес проверяющей службы подменяется только тем, кто знает ключ вебхука:
  // этим пользуется тест, снаружи ключа нет.
  const secret = $os.getenv("LAVA_WEBHOOK_KEY") || "";
  const given = e.request.header.get("X-Api-Key") || "";
  let база = $os.getenv("FERN_VERIFY_URL") || "http://127.0.0.1:8097";
  if (secret && given === secret && body.verify_base) {
    база = String(body.verify_base);
  }

  let итог = null;
  try {
    const r = $http.send({
      url: база.replace(/\/+$/, "") + "/apple/notification",
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        signedPayload: конверт,
        bundleId: $os.getenv("FERN_BUNDLE_ID") || "com.fern.flashcards",
      }),
      timeout: 30,
    });
    итог = (r && r.json) || null;
  } catch (err) {
    console.log("[fern] уведомление Apple не разобрано: " + err);
    return e.json(502, { ok: false, error: "verify_unreachable" });
  }
  // Чужое приложение или подделка: отвечаем 200, иначе Apple будет слать
  // это же уведомление сутками.
  if (!итог || итог.valid !== true) {
    return e.json(200, { ok: true, skipped: (итог || {}).reason || "not_valid" });
  }

  const сделка = итог.transaction || {};
  const первый = String(сделка.originalTransactionId || "");
  const срок = String(сделка.expiry || "");
  const отозвано = !!сделка.revocationDate;
  const тип = String(итог.notificationType || "");
  if (!первый) return e.json(200, { ok: true, skipped: "no_transaction" });

  // Кого касается: заказ магазина мы записали при покупке и помним в нём
  // первый идентификатор сделки — по нему и находим человека.
  let заказ = null;
  try {
    заказ = $app.findFirstRecordByFilter(
      "fern_orders", "source = 'apple' && invoice_id = {:t}", { t: первый });
  } catch (_) { заказ = null; }
  if (!заказ) return e.json(200, { ok: true, skipped: "unknown_transaction" });

  let человек = null;
  try {
    человек = $app.findRecordById("fern_users", String(заказ.get("uid") || ""));
  } catch (_) { человек = null; }
  if (!человек) return e.json(200, { ok: true, skipped: "no_account" });

  const сейчас = new Date();
  if (отозвано || тип === "REFUND" || тип === "REVOKE") {
    человек.set("pro_status", "refunded");
    человек.set("pro_until", сейчас.toISOString());
  } else if (срок) {
    const d = new Date(срок.replace(" ", "T"));
    if (!isNaN(d.getTime())) {
      человек.set("pro_until", d.toISOString());
      // Отмена автопродления — не потеря доступа: оплаченное дохаживает.
      человек.set("pro_status",
        тип === "DID_CHANGE_RENEWAL_STATUS" && String(итог.subtype) === "AUTO_RENEW_DISABLED"
          ? "cancelled" : "active");
    }
  } else if (тип === "EXPIRED") {
    человек.set("pro_status", "expired");
  }
  try { $app.save(человек); } catch (err) { console.log("[fern] " + err); }

  заказ.set("event", "apple:" + тип);
  if (срок) заказ.set("until", срок);
  try { $app.save(заказ); } catch (_) {}

  return e.json(200, { ok: true, type: тип, until: срок || null });
});

/// POST /api/fern/play-rtdn — уведомления Google Play через Pub/Sub.
///
/// Google шлёт сообщение с base64 внутри и ждёт 200: любой другой ответ он
/// повторяет часами. Поэтому здесь почти всё кончается ответом «принято» — а
/// что случилось, видно в журнале.
routerAdd("POST", "/api/fern/play-rtdn", (e) => {
  const secret = $os.getenv("FERN_RTDN_KEY") || $os.getenv("LAVA_WEBHOOK_KEY") || "";
  const given = e.request.url.query().get("key") ||
    e.request.header.get("X-Api-Key") || "";
  if (secret && given !== secret) {
    return e.json(401, { ok: false, error: "bad_key" });
  }

  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const данные = String(((body.message || {}).data) || "");
  if (!данные) return e.json(200, { ok: true, skipped: "no_data" });

  let сообщение = {};
  try {
    // base64 в этой сборке JSVM нет, поэтому раскодируем сами: алфавит
    // короткий, а тянуть ради этого службу — лишний прыжок на каждое
    // уведомление.
    const АЛФАВИТ =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let биты = 0, накоплено = 0, байты = [];
    const чистые = данные.replace(/[^A-Za-z0-9+/]/g, "");
    for (let i = 0; i < чистые.length; i++) {
      накоплено = (накоплено << 6) | АЛФАВИТ.indexOf(чистые.charAt(i));
      биты += 6;
      if (биты >= 8) {
        биты -= 8;
        байты.push((накоплено >> биты) & 0xff);
      }
    }
    let текст = "";
    for (let i = 0; i < байты.length; i++) текст += String.fromCharCode(байты[i]);
    // Русских букв в уведомлении Google нет, поэтому посимвольной сборки хватает.
    сообщение = JSON.parse(текст);
  } catch (err) {
    console.log("[fern] RTDN не разобран: " + err);
    return e.json(200, { ok: true, skipped: "bad_base64" });
  }

  let база = $os.getenv("FERN_VERIFY_URL") || "http://127.0.0.1:8097";
  if (secret && given === secret && body.verify_base) {
    база = String(body.verify_base);
  }

  const подписка = сообщение.subscriptionNotification || {};
  const чек = String(подписка.purchaseToken || "");
  const товар = String(подписка.subscriptionId || "");
  if (!чек) return e.json(200, { ok: true, skipped: сообщение.testNotification ? "test" : "not_subscription" });

  let заказ = null;
  try {
    заказ = $app.findFirstRecordByFilter(
      "fern_orders", "source = 'play' && order_key = {:k}",
      { k: "PLAY:" + чек });
  } catch (_) { заказ = null; }
  if (!заказ) return e.json(200, { ok: true, skipped: "unknown_token" });

  // Содержимому уведомления не верим: спрашиваем у Google, что со сроком.
  let вердикт = null;
  try {
    const r = $http.send({
      url: база.replace(/\/+$/, "") + "/verify",
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        store: "play", kind: "subscription",
        productId: товар || String(заказ.get("plan") === "year"
          ? "fern_pro_year" : "fern_pro_month"),
        purchaseToken: чек,
        package: $os.getenv("FERN_PLAY_PACKAGE") || "com.fern.app",
      }),
      timeout: 30,
    });
    вердикт = (r && r.json) || null;
  } catch (err) {
    console.log("[fern] чек по уведомлению не проверен: " + err);
    return e.json(200, { ok: true, skipped: "verify_unreachable" });
  }
  if (!вердикт || вердикт.ok !== true) {
    return e.json(200, { ok: true, skipped: "verify_failed" });
  }

  let человек = null;
  try {
    человек = $app.findRecordById("fern_users", String(заказ.get("uid") || ""));
  } catch (_) { человек = null; }
  if (!человек) return e.json(200, { ok: true, skipped: "no_account" });

  const сейчас = new Date();
  if (вердикт.valid === true && вердикт.expiry) {
    const d = new Date(String(вердикт.expiry).replace(" ", "T"));
    if (!isNaN(d.getTime())) {
      человек.set("pro_until", d.toISOString());
      человек.set("pro_status", вердикт.cancelled === true ? "cancelled" : "active");
      заказ.set("until", d.toISOString());
    }
  } else {
    // Подписка кончилась или отозвана: срок не двигаем, состояние отмечаем.
    человек.set("pro_status",
      String(вердикт.state || "").indexOf("EXPIRED") !== -1 ? "expired" : "cancelled");
  }
  заказ.set("event", "play:" + String(подписка.notificationType || "?"));
  try { $app.save(человек); $app.save(заказ); } catch (err) { console.log("[fern] " + err); }

  return e.json(200, { ok: true, until: вердикт.expiry || null });
});

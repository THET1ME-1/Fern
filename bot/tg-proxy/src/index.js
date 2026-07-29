/**
 * Мост между магазином и ботом, который живёт на российском VPS.
 *
 * Две задачи, обе от одной беды: тот хостинг и внешний мир видят друг друга
 * плохо. Телеграм с него недоступен вовсе (ICMP проходит, TLS не встаёт), а
 * принимать вебхук lava.top неоткуда — порты 80 и 443 заняты чужим сервисом.
 * Cloudflare виден и телеграму, и lava.top, и боту.
 *
 *   /bot<токен>/<метод>  → прокси в api.telegram.org (чужой токен: 403)
 *   POST /lava           → вебхук lava.top, событие ложится в очередь
 *   GET  /pull           → бот забирает события (своим исходящим соединением)
 *   POST /ack            → бот подтверждает обработанные, они стираются
 *
 * Очередь нужна потому, что достучаться до бота снаружи нельзя: он приходит
 * за событиями сам. Секреты (в репозитории их нет):
 *
 *     echo -n "<токен бота>" | npx wrangler secret put TELEGRAM_BOT_TOKEN
 *     echo -n "<ключ для lava.top>" | npx wrangler secret put WEBHOOK_KEY
 *     echo -n "<ключ для бота>" | npx wrangler secret put PULL_KEY
 */

// Событие живёт в очереди неделю: если бот лежал, заказ дождётся его. Ключ
// покупателю всё это время выдаётся вручную (/grant в боте).
const TTL_SECONDS = 7 * 24 * 60 * 60;
const BATCH = 20;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/health') {
      return new Response('alive');
    }
    if (url.pathname === '/lava') {
      return takeOrder(request, env);
    }
    if (url.pathname === '/pull') {
      return pullOrders(request, env);
    }
    if (url.pathname === '/ack') {
      return ackOrders(request, env);
    }
    return proxyTelegram(request, env, url);
  },
};

// Маркер «в очереди что-то есть». Нужен из-за лимита KV: `list()` на бесплатном
// плане отпущено 1000 раз в сутки, а бот заходит за заказами каждые 15 секунд —
// это 5760 обращений, и к обеду воркер начинал отвечать 500 «list() limit
// exceeded», бот молчал. Теперь `list()` зовётся, только когда заказ реально
// пришёл: лёгкий `get()` лимитом не ограничен так жёстко.
const MARKER = 'meta:queue';
const MARKER_EMPTY = 'empty';

/** Вебхук lava.top: сохранить событие целиком и ответить 200. */
async function takeOrder(request, env) {
  if (env.WEBHOOK_KEY && request.headers.get('X-Api-Key') !== env.WEBHOOK_KEY) {
    return new Response('bad key', { status: 401 });
  }
  const body = await request.text();
  if (!body) {
    return new Response('empty', { status: 400 });
  }
  // Ключ упорядочен по времени: бот разбирает очередь в порядке покупок.
  const key = `order:${Date.now()}:${crypto.randomUUID()}`;
  await env.ORDERS.put(key, body, { expirationTtl: TTL_SECONDS });
  // Поднимаем маркер: без него бот не станет заглядывать в очередь и заказ
  // пролежит незамеченным.
  await env.ORDERS.put(MARKER, String(Date.now()));
  // 200 даже на непонятное событие: lava.top повторяет вебхук до двадцати раз,
  // а разбирается с ним всё равно бот.
  return new Response('ok');
}

/** Бот забирает пачку событий. Из очереди они не пропадают до `/ack`. */
async function pullOrders(request, env) {
  if (!authorized(request, env)) {
    return new Response('forbidden', { status: 403 });
  }
  // Пустая очередь — самый частый случай: отвечаем сразу, не тратя list().
  const marker = await env.ORDERS.get(MARKER);
  if (!marker || marker === MARKER_EMPTY) {
    return Response.json({ events: [] });
  }

  const listed = await env.ORDERS.list({ prefix: 'order:', limit: BATCH });
  const events = [];
  for (const item of listed.keys) {
    const payload = await env.ORDERS.get(item.name);
    if (payload !== null) {
      events.push({ key: item.name, payload });
    }
  }
  // Разобрали всё — гасим маркер, следующий заход обойдётся без list().
  if (events.length === 0) {
    await env.ORDERS.put(MARKER, MARKER_EMPTY);
  }
  return Response.json({ events });
}

/** Бот подтверждает обработанные события — только тогда они стираются. */
async function ackOrders(request, env) {
  if (!authorized(request, env)) {
    return new Response('forbidden', { status: 403 });
  }
  let keys = [];
  try {
    ({ keys = [] } = await request.json());
  } catch {
    return new Response('bad json', { status: 400 });
  }
  await Promise.all(keys.map((key) => env.ORDERS.delete(key)));
  return Response.json({ deleted: keys.length });
}

function authorized(request, env) {
  const given = request.headers.get('X-Pull-Key');
  return Boolean(env.PULL_KEY) && given === env.PULL_KEY;
}

/** Прокси в телеграм: пересылаются только запросы со своим токеном. */
async function proxyTelegram(request, env, url) {
  // Формы путей у Telegram две: /bot<токен>/<метод> и /file/bot<токен>/<путь>.
  const parts = url.pathname.match(/^\/(file\/)?bot([^/]+)(\/.*)$/);
  if (!parts) {
    return new Response('not found', { status: 404 });
  }
  const [, filePrefix = '', token, tail] = parts;
  if (!env.TELEGRAM_BOT_TOKEN || token !== env.TELEGRAM_BOT_TOKEN) {
    return new Response('forbidden', { status: 403 });
  }
  const target =
    `https://api.telegram.org/${filePrefix}bot${token}${tail}${url.search}`;
  // Запрос пересылается как есть: long polling держит соединение минутами,
  // свой таймаут тут всё сломает.
  return fetch(target, new Request(target, request));
}

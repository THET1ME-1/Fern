/**
 * Прокси к api.telegram.org для бота, живущего на российском VPS.
 *
 * Телеграм с того хостинга недоступен: ICMP проходит, а TLS-соединение не
 * устанавливается вовсе. Бот в такой сети крутит ретраи вхолостую и молчит.
 * Cloudflare видит Telegram, поэтому запросы идут через него.
 *
 * Прокси не открытый: он пересылает только запросы со своим токеном, чужие
 * получают 403. Токен лежит секретом, в репозитории его нет:
 *
 *     echo -n "<токен>" | npx wrangler secret put TELEGRAM_BOT_TOKEN
 */
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/health') {
      return new Response('alive');
    }

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

    // Запрос пересылается как есть: метод, заголовки и тело менять незачем,
    // а long polling держит соединение минутами — таймаут ставить нельзя.
    return fetch(target, new Request(target, request));
  },
};

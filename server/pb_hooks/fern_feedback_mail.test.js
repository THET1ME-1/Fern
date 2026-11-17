// node server/pb_hooks/fern_feedback_mail.test.js
// Обращение из Fern (17.11.2026): что принимается и как выглядит письмо в ящике.
const assert = require('assert');
const F = require('./fern_feedback_mail.js');

assert.strictEqual(F.problemOf({ kind: 'bug', text: 'Не открывается колода после импорта' }), '');
assert.strictEqual(F.problemOf({ kind: 'payment', text: 'Оплатил, а Pro нет', email: 'a@b.co' }), '');
assert.strictEqual(F.problemOf({ kind: 'spam', text: 'Достаточно длинный текст' }), 'bad_kind');
assert.strictEqual(F.problemOf({ kind: 'bug', text: 'коротко' }), 'too_short');
assert.strictEqual(F.problemOf({ kind: 'bug', text: 'я'.repeat(F.MAX + 1) }), 'too_long');
assert.strictEqual(F.problemOf({ kind: 'bug', text: 'Достаточно длинный текст', email: 'не почта' }), 'bad_email');
// виды — те же, что в приложении (FeedbackKind в app/lib/models/feedback.dart)
assert.deepStrictEqual(Object.keys(F.KINDS).sort(), ['bug', 'idea', 'other', 'payment']);

assert.strictEqual(F.subjectOf({ kind: 'idea', text: 'Тёмная\nтема поярче' }), '[Fern] Идея: Тёмная тема поярче');

const f = { id: 'r1', uid: 'u1', kind: 'bug', text: 'Не открывается', email: 'p@x.io', app: '1.27.0', platform: 'android', lang: 'ru' };
const mail = F.mailOf(f, 'inbox');
assert.deepStrictEqual(mail.from, [{ name: 'p@x.io', email: 'p@x.io' }]);
assert.deepStrictEqual(mail.replyTo, [{ email: 'p@x.io' }]);
assert.ok(mail.bodyValues.b.value.includes('Приложение: Fern 1.27.0, android, язык ru'));
assert.ok(mail.bodyValues.b.value.includes('Аккаунт Fern: u1'));
// без почты письмо от имени Fern, ответить некуда — так и написано
const quiet = F.mailOf({ ...f, email: '', uid: '' }, 'inbox');
assert.deepStrictEqual(quiet.from, [{ name: 'Fern', email: 'support@togetherly.day' }]);
assert.strictEqual(quiet.replyTo, undefined);
assert.ok(quiet.bodyValues.b.value.includes('Ответить: почту не оставили'));
assert.ok(quiet.bodyValues.b.value.includes('Аккаунт Fern: без входа'));
console.log('fern_feedback_mail: всё сходится');

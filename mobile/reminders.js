// Reminders during the Google Play closed test (20 Nov 2026): Google asks that testers really use the app for 14 days.
// Until the date in app.config.js (`testRemindersUntil`), the Android app plans two reminders a day, at 12:30 and 19:30.
// They are planned on the phone itself: nothing is sent to a server and no identifier of the phone is collected.
// Opening the app cancels the reminders of that day (the tester has done their part) and plans the following days.
//
// This file holds the whole decision, with the phone's services passed in, so that it can be run for real in the tests
// with a pretend phone (tests/reminders.test.cjs). App.js only connects it to the real phone.
const REMIND_AT = [[12, 30], [19, 30]];
const REMIND_TEXT = [
  'Merci de tester UPZONE ! Ouvre l’appli aujourd’hui et dis-nous ce que tu en penses.',
  'Un petit tour sur UPZONE ce soir ? Chaque essai nous aide avant la sortie.',
];
const STEP_LIMIT = 5000; // a step that has not answered after 5 s is reported instead of blocking everything silently
const QUESTION_WAIT = 6000; // after 6 s with the app still on screen, Android is not showing its question

function within(promise, ms, label, wait) {
  return Promise.race([promise, new Promise((_, reject) => wait(() => reject(new Error(`timeout:${label}`)), ms))]);
}

// Returns { allowed, diag }. `allowed` false means: notifications are not allowed, the app should invite the person.
// `diag` is a short readout of each step (Android version, the phone's answers, reminders planned, any error); `note`
// receives it after every step, so that a step that never answers is still visible. No personal data.
async function planTestReminders({ Notifications, os, version, until, now = () => Date.now(), isForeground = () => true, note = () => {}, wait = setTimeout }) {
  const d = [];
  const say = (x) => { d.push(x); note(d.join(' ')); };
  const done = (allowed) => ({ allowed, diag: d.join(' ') });
  try {
    if (os !== 'android') { say(`os=${os}`); return done(true); }
    say(`a=${version}`);
    const end = until ? new Date(`${until}T23:59:59`) : null;
    await within(Notifications.cancelAllScheduledNotificationsAsync(), STEP_LIMIT, 'cancel', wait);
    if (!end || isNaN(end) || now() > end.getTime()) { say('until=over'); return done(true); }
    // The channel comes first: since Android 13 the phone only shows the « allow notifications » question once the app
    // has a notification channel (Expo documentation).
    await within(Notifications.setNotificationChannelAsync('rappels', { name: 'Rappels du test', importance: Notifications.AndroidImportance.DEFAULT }), STEP_LIMIT, 'channel', wait);
    say('ch=ok');
    let perm = await within(Notifications.getPermissionsAsync(), STEP_LIMIT, 'get', wait);
    say(`get=${perm.status}/${perm.canAskAgain ? 1 : 0}`);
    if (!perm.granted) {
      // Ask whenever notifications are not allowed yet, as Expo's own example does. The question may stay open as long
      // as the person reads it, so there is no limit while it is on screen. But if 6 s later the app is still in the
      // foreground, Android showed nothing: say so instead of waiting for ever.
      const started = now();
      const asked = Notifications.requestPermissionsAsync();
      const first = await Promise.race([asked.then((p) => ({ p })), new Promise((resolve) => wait(() => resolve({ late: true }), QUESTION_WAIT))]);
      if (first.late && isForeground()) { say('req=silent'); return done(false); }
      perm = first.p || await asked;
      say(`req=${perm.status}/${perm.canAskAgain ? 1 : 0}/${now() - started}ms`);
    }
    if (!perm.granted) return done(false);
    let planned = 0;
    const day = new Date(now()); day.setHours(0, 0, 0, 0);
    for (let n = 1; n <= 30; n += 1) {
      const at0 = new Date(day); at0.setDate(at0.getDate() + n);
      if (at0.getTime() > end.getTime()) break;
      for (let i = 0; i < REMIND_AT.length; i += 1) {
        const at = new Date(at0); at.setHours(REMIND_AT[i][0], REMIND_AT[i][1], 0, 0);
        await within(Notifications.scheduleNotificationAsync({
          content: { title: 'UPZONE', body: REMIND_TEXT[i] },
          trigger: { type: Notifications.SchedulableTriggerInputTypes.DATE, date: at, channelId: 'rappels' },
        }), STEP_LIMIT, 'plan', wait);
        planned += 1;
      }
    }
    say(`plan=${planned}`);
    return done(true);
  } catch (e) {
    say(`err=${String((e && e.message) || e).slice(0, 90)}`);
    return done(false);
  }
}

// What UPZONE's own settings screen can ask the app, inside the app: « status » (are notifications allowed?), « enable »
// (ask; if Android will not ask or the answer is no, open the phone's settings for UPZONE) and « test » (show a
// notification in five seconds, so that anyone can see for themselves that it works). Returns a small state object.
const TEST_TEXT = 'Test réussi : les notifications fonctionnent sur ce téléphone.';
async function notifRequest({ Notifications, action, openSettings = async () => {}, isForeground = () => true, wait = setTimeout }) {
  try {
    await within(Notifications.setNotificationChannelAsync('rappels', { name: 'Rappels du test', importance: Notifications.AndroidImportance.DEFAULT }), STEP_LIMIT, 'channel', wait);
    let perm = await within(Notifications.getPermissionsAsync(), STEP_LIMIT, 'get', wait);
    if (action === 'enable' && !perm.granted) {
      const asked = Notifications.requestPermissionsAsync();
      const first = await Promise.race([asked.then((p) => ({ p })), new Promise((resolve) => wait(() => resolve({ late: true }), QUESTION_WAIT))]);
      if (first.p) perm = first.p; else if (!isForeground()) perm = await asked;
      if (!perm.granted) { await openSettings(); return { allowed: false, opened: true }; }
    }
    if (action === 'test') {
      if (!perm.granted) return { allowed: false, test: 'blocked' };
      await within(Notifications.scheduleNotificationAsync({
        content: { title: 'UPZONE', body: TEST_TEXT },
        trigger: { type: Notifications.SchedulableTriggerInputTypes.TIME_INTERVAL, seconds: 5, channelId: 'rappels' },
      }), STEP_LIMIT, 'test', wait);
      return { allowed: true, test: 'sent' };
    }
    return { allowed: !!perm.granted };
  } catch (e) {
    return { allowed: false, error: String((e && e.message) || e).slice(0, 90) };
  }
}

module.exports = { planTestReminders, notifRequest, REMIND_AT, REMIND_TEXT, TEST_TEXT };

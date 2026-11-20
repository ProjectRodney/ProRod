import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, BackHandler, Linking, Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import Constants from 'expo-constants';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { WebView } from 'react-native-webview';
import * as Notifications from 'expo-notifications';
import * as Updates from 'expo-updates';

const APP_URL = Constants.expoConfig?.extra?.appUrl || 'https://upzoneapp.fr/account.html';
const APP_HOST = new URL(APP_URL).host;
// How the app signs itself to the website: « UPZONEApp/1.0 (base) » as built, « UPZONEApp/1.0 (1a2b3c4d) » once an update
// received over the air is in use. The website shows it at the bottom of the settings, to know what a tester is running.
const APP_MARK = `UPZONEApp/1.0 (${Updates.isEmbeddedLaunch || !Updates.updateId ? 'base' : Updates.updateId.slice(0, 8)})`;
// Pages that stay inside the app: UPZONE itself and its sign-in service. Everything else opens in the browser.
const inside = (url) => {
  try {
    const u = new URL(url);
    if (u.protocol === 'about:' || u.protocol === 'blob:' || u.protocol === 'data:') return true;
    if (u.protocol !== 'https:') return false;
    return u.host === APP_HOST || u.host.endsWith('.supabase.co');
  } catch {
    return false;
  }
};

// Reminders during the Google Play closed test (20 Nov 2026): Google asks that testers really use the app for 14 days.
// Until the date in app.config.js (`testRemindersUntil`), the Android app plans two reminders a day, at 12:30 and 19:30.
// They are planned on the phone itself: nothing is sent to a server and no identifier of the phone is collected.
// Opening the app cancels the reminders of that day (the tester has done their part) and plans the following days.
// After the date, everything is cancelled and the app never asks for the permission again for this purpose.
const REMIND_UNTIL = Constants.expoConfig?.extra?.testRemindersUntil || '';
const REMIND_AT = [[12, 30], [19, 30]];
const REMIND_TEXT = [
  'Merci de tester UPZONE ! Ouvre l’appli aujourd’hui et dis-nous ce que tu en penses.',
  'Un petit tour sur UPZONE ce soir ? Chaque essai nous aide avant la sortie.',
];
Notifications.setNotificationHandler({
  handleNotification: async () => ({ shouldShowBanner: false, shouldShowList: false, shouldPlaySound: false, shouldSetBadge: false }),
});
async function planTestReminders() {
  if (Platform.OS !== 'android') return;
  const end = REMIND_UNTIL ? new Date(REMIND_UNTIL + 'T23:59:59') : null;
  await Notifications.cancelAllScheduledNotificationsAsync();
  if (!end || isNaN(end) || Date.now() > end.getTime()) return;
  let perm = await Notifications.getPermissionsAsync();
  if (!perm.granted && perm.canAskAgain) perm = await Notifications.requestPermissionsAsync();
  if (!perm.granted) return;
  await Notifications.setNotificationChannelAsync('rappels', { name: 'Rappels du test', importance: Notifications.AndroidImportance.DEFAULT });
  const day = new Date(); day.setHours(0, 0, 0, 0);
  for (let n = 1; n <= 30; n += 1) {
    const d = new Date(day); d.setDate(d.getDate() + n);
    if (d.getTime() > end.getTime()) break;
    for (let i = 0; i < REMIND_AT.length; i += 1) {
      const at = new Date(d); at.setHours(REMIND_AT[i][0], REMIND_AT[i][1], 0, 0);
      await Notifications.scheduleNotificationAsync({
        content: { title: 'UPZONE', body: REMIND_TEXT[i] },
        trigger: { type: Notifications.SchedulableTriggerInputTypes.DATE, date: at, channelId: 'rappels' },
      });
    }
  }
}

export default function App() {
  const web = useRef(null);
  const [failed, setFailed] = useState(false);
  const [loading, setLoading] = useState(true);

  const onNavigate = useCallback((request) => {
    if (inside(request.url)) return true;
    Linking.openURL(request.url).catch(() => {});
    return false;
  }, []);
  // Android: the phone's back button goes to the previous screen of UPZONE; on the first screen it leaves the app.
  const canGoBack = useRef(false);
  useEffect(() => {
    if (Platform.OS !== 'android') return undefined;
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      if (canGoBack.current && web.current) { web.current.goBack(); return true; }
      return false;
    });
    return () => sub.remove();
  }, []);
  useEffect(() => { planTestReminders().catch(() => {}); }, []);
  const retry = () => { setFailed(false); setLoading(true); web.current?.reload(); };

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.screen} edges={['top', 'left', 'right']}>
        <StatusBar style="dark" />
        <WebView
          ref={web}
          source={{ uri: APP_URL }}
          style={[styles.web, failed && styles.hidden]}
          originWhitelist={['https://*']}
          onShouldStartLoadWithRequest={onNavigate}
          applicationNameForUserAgent={APP_MARK}
          allowsInlineMediaPlayback
          mediaPlaybackRequiresUserAction={false}
          mediaCapturePermissionGrantType="grantIfSameHostElsePrompt"
          sharedCookiesEnabled
          allowsBackForwardNavigationGestures
          pullToRefreshEnabled
          setSupportMultipleWindows={false}
          onNavigationStateChange={(state) => { canGoBack.current = state.canGoBack; }}
          onLoadEnd={() => setLoading(false)}
          onError={() => { setLoading(false); setFailed(true); }}
          onHttpError={(e) => { if (e.nativeEvent.statusCode >= 500) setFailed(true); }}
          onContentProcessDidTerminate={() => web.current?.reload()}
        />
        {loading && !failed ? <View style={styles.cover}><ActivityIndicator size="large" color="#5005b0" /></View> : null}
        {failed ? (
          <View style={styles.cover}>
            <Text style={styles.title}>UPZONE</Text>
            <Text style={styles.text}>Impossible de charger UPZONE. Vérifie ta connexion internet.</Text>
            <Pressable style={styles.button} onPress={retry} accessibilityRole="button">
              <Text style={styles.buttonText}>Réessayer</Text>
            </Pressable>
          </View>
        ) : null}
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#fffadd' },
  web: { flex: 1, backgroundColor: '#fffadd' },
  hidden: { opacity: 0 },
  cover: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center', padding: 32, backgroundColor: '#fffadd' },
  title: { fontSize: 34, fontWeight: '900', color: '#e20066', marginBottom: 16 },
  text: { fontSize: 17, lineHeight: 24, textAlign: 'center', color: '#1c1530', marginBottom: 24 },
  button: { backgroundColor: '#fffc00', paddingVertical: 14, paddingHorizontal: 28, borderRadius: 15 },
  buttonText: { fontSize: 17, fontWeight: '700', color: '#111' },
});

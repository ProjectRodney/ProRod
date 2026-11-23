import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, AppState, BackHandler, Linking, Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import Constants from 'expo-constants';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { WebView } from 'react-native-webview';
import * as Notifications from 'expo-notifications';
import * as Updates from 'expo-updates';
import { planTestReminders } from './reminders';

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

// Test reminders: the whole decision is in reminders.js (run for real in the tests with a pretend phone).
const REMIND_UNTIL = Constants.expoConfig?.extra?.testRemindersUntil || '';
Notifications.setNotificationHandler({
  handleNotification: async () => ({ shouldShowBanner: false, shouldShowList: false, shouldPlaySound: false, shouldSetBadge: false }),
});
// What happened, in a few characters: shown in the app's settings and in the invitation below.
let notifDiag = '';
let planning = false;
async function runReminders(onNote) {
  if (planning) return { allowed: true, skipped: true };
  planning = true;
  try {
    return await planTestReminders({
      Notifications, os: Platform.OS, version: Platform.Version, until: REMIND_UNTIL,
      isForeground: () => AppState.currentState === 'active',
      note: (text) => { notifDiag = text; onNote?.(); },
    });
  } finally { planning = false; }
}
// When Android will not show its own question (or the person said no), the app says why it asks and opens the phone's
// settings for UPZONE, where notifications can be switched on. Once per opening of the app, during the test only.
let invited = false;
function inviteToAllow() {
  if (invited || Platform.OS !== 'android') return;
  invited = true;
  Alert.alert(
    'Rappels du test',
    `Pour recevoir un petit rappel les jours où tu n’as pas encore ouvert UPZONE, autorise les notifications.\n\n[${notifDiag}]`,
    [{ text: 'Plus tard', style: 'cancel' }, { text: 'Autoriser', onPress: () => { Linking.openSettings().catch(() => {}); } }],
  );
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
  // The website shows the readout at the bottom of the settings (window.__upzoneNotif).
  const tellSite = useCallback(() => { web.current?.injectJavaScript(`window.__upzoneNotif=${JSON.stringify(notifDiag)};true;`); }, []);
  useEffect(() => {
    runReminders(tellSite).then((r) => { tellSite(); if (!r.allowed) inviteToAllow(); });
    // Back from the phone's settings (or from Android's own question): plan the reminders now, without a second invitation.
    const sub = AppState.addEventListener('change', (state) => { if (state === 'active') runReminders(tellSite).then(tellSite); });
    return () => sub.remove();
  }, [tellSite]);
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
          onLoadEnd={() => { setLoading(false); tellSite(); }}
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

import { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, Linking, Pressable, StyleSheet, Text, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import Constants from 'expo-constants';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { WebView } from 'react-native-webview';

const APP_URL = Constants.expoConfig?.extra?.appUrl || 'https://projectrodney.github.io/ProRod/account.html';
const APP_HOST = new URL(APP_URL).host;
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

export default function App() {
  const web = useRef(null);
  const [failed, setFailed] = useState(false);
  const [loading, setLoading] = useState(true);

  const onNavigate = useCallback((request) => {
    if (inside(request.url)) return true;
    Linking.openURL(request.url).catch(() => {});
    return false;
  }, []);
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
          applicationNameForUserAgent="UPZONEApp/1.0"
          allowsInlineMediaPlayback
          mediaPlaybackRequiresUserAction={false}
          mediaCapturePermissionGrantType="grantIfSameHostElsePrompt"
          sharedCookiesEnabled
          allowsBackForwardNavigationGestures
          pullToRefreshEnabled
          setSupportMultipleWindows={false}
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

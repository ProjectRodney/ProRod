// The Android test reminders, run for real with a pretend phone (23 Nov 2026). No emulator: the phone's services are
// replaced by stand-ins whose answers each test chooses, and the app's own code (mobile/reminders.js, mobile/App.js) runs.
const test=require('node:test'),assert=require('node:assert'),fs=require('node:fs'),path=require('node:path'),Module=require('node:module');
const {planTestReminders,notifRequest,TEST_TEXT}=require('../mobile/reminders.js');
const NOW=new Date('2026-11-23T11:00:00').getTime();

// A pretend phone. `before` / `after`: what it answers before and after the question; `hang`: a step that never answers.
function phone({before={status:'undetermined',granted:false,canAskAgain:true},after={status:'granted',granted:true,canAskAgain:true},hang=null,fail=null}={}){
 const log=[],never=new Promise(()=>{});
 const step=(name,value)=>{log.push(name);if(fail===name)return Promise.reject(new Error('boom '+name));if(hang===name)return never;return Promise.resolve(value);};
 return {log,planned:[],Notifications:{
  AndroidImportance:{DEFAULT:3},SchedulableTriggerInputTypes:{DATE:'date',TIME_INTERVAL:'interval'},
  cancelAllScheduledNotificationsAsync:()=>step('cancel'),
  setNotificationChannelAsync:()=>step('channel'),
  getPermissionsAsync:()=>step('get',before),
  requestPermissionsAsync:()=>step('request',after),
  scheduleNotificationAsync(x){this._p.push(x);return step('plan');},_p:[],
 }};
}
// Timers fire at once in these tests, so a « never answers » step is reported immediately instead of after 5 s.
const fast=(fn)=>{setImmediate(fn);};
const run=(p,extra={})=>planTestReminders({Notifications:p.Notifications,os:'android',version:34,until:'2026-12-12',now:()=>NOW,wait:fast,...extra});

test('first opening: the phone is asked, the person allows, reminders are planned from tomorrow to the last day',async()=>{
 const p=phone(),r=await run(p);
 assert.equal(r.allowed,true);
 assert.deepEqual(p.log.slice(0,4),['cancel','channel','get','request'],'channel before the question');
 const planned=p.Notifications._p;
 assert.equal(planned.length,38,'19 days x 2 (24 Nov to 12 Dec)');
 assert.equal(planned[0].trigger.date.toISOString(),new Date('2026-11-24T12:30:00').toISOString());
 assert.equal(planned[37].trigger.date.toISOString(),new Date('2026-12-12T19:30:00').toISOString());
 assert.match(r.diag,/^a=34 ch=ok get=undetermined\/1 req=granted\/1\/\d+ms plan=38$/);
});

test('the phone says « do not ask again » before any question was shown: the app asks anyway',async()=>{
 const p=phone({before:{status:'denied',granted:false,canAskAgain:false}}),r=await run(p);
 assert.ok(p.log.includes('request'));assert.equal(r.allowed,true);
});

test('the person refuses, or the phone refuses without showing anything: not allowed, nothing planned, the app must invite',async()=>{
 const p=phone({after:{status:'denied',granted:false,canAskAgain:false}}),r=await run(p);
 assert.equal(r.allowed,false);assert.equal(p.Notifications._p.length,0);
 assert.match(r.diag,/get=undetermined\/1 req=denied\/0\/\d+ms$/);
});

test('the question never answers while the app stays on screen: reported as silent, the app must invite',async()=>{
 const p=phone({hang:'request'}),r=await run(p,{isForeground:()=>true});
 assert.equal(r.allowed,false);assert.match(r.diag,/req=silent$/);
});

test('the question is on screen (the app is behind it): the app waits for the answer instead of inviting on top of it',async()=>{
 const p=phone();let release;const answer=new Promise(res=>{release=res;});
 p.Notifications.requestPermissionsAsync=()=>answer;
 const pending=run(p,{isForeground:()=>false});
 setTimeout(()=>release({status:'granted',granted:true,canAskAgain:true}),30);
 const r=await pending;assert.equal(r.allowed,true);assert.match(r.diag,/plan=38$/);
});

test('already allowed (switched on in the phone settings): no question, reminders planned',async()=>{
 const p=phone({before:{status:'granted',granted:true,canAskAgain:true}}),r=await run(p);
 assert.ok(!p.log.includes('request'));assert.equal(r.allowed,true);assert.match(r.diag,/get=granted\/1 plan=38$/);
});

test('a step that fails or never answers is reported, never swallowed',async()=>{
 for(const [opt,re] of [[{fail:'channel'},/err=boom channel$/],[{hang:'channel'},/err=timeout:channel$/],[{hang:'get'},/err=timeout:get$/],[{hang:'cancel'},/err=timeout:cancel$/]]){
  const r=await run(phone(opt));assert.equal(r.allowed,false);assert.match(r.diag,re);
 }
});

test('after the last day everything is cancelled and nothing is asked; on iPhone nothing happens at all',async()=>{
 const late=phone(),r=await planTestReminders({Notifications:late.Notifications,os:'android',version:34,until:'2026-12-12',now:()=>new Date('2026-12-13T09:00:00').getTime(),wait:fast});
 assert.deepEqual(late.log,['cancel']);assert.equal(r.allowed,true);assert.match(r.diag,/until=over$/);
 const ios=phone(),r2=await planTestReminders({Notifications:ios.Notifications,os:'ios',version:'18',until:'2026-12-12',wait:fast});
 assert.deepEqual(ios.log,[]);assert.equal(r2.allowed,true);
});

test('every step is noted as it happens, so a blocked step is visible in the settings',async()=>{
 const notes=[];await run(phone({hang:'request'}),{note:t=>notes.push(t)});
 assert.deepEqual(notes,['a=34','a=34 ch=ok','a=34 ch=ok get=undetermined/1','a=34 ch=ok get=undetermined/1 req=silent']);
});

// --- The app's start-up wiring, run for real: App.js is compiled as the phone would and started with stand-ins. ---
function startApp({before,after,hang,appState='active'}={}){
 // Compiled with the site's own build tool (esbuild), so this runs wherever the tests run, without the phone app's packages.
 const file=path.join(__dirname,'..','mobile','App.js');
 const code=require('esbuild').transformSync(fs.readFileSync(file,'utf8'),{loader:'jsx',format:'cjs',jsx:'automatic',sourcefile:file}).code;
 const p=phone({before,after,hang});
 const seen={alerts:[],injected:[],opened:0,listeners:[]};
 const notif=Object.assign(p.Notifications,{setNotificationHandler(){}});
 const effects=[];
 const webProps={};
 const React={createElement:(type,props,...kids)=>{if(type==='W')Object.assign(webProps,props);return {type,props:props||{},kids};},useRef:(v)=>({current:v}),useState:(v)=>[v,()=>{}],useCallback:(f)=>f,useEffect:(f)=>{effects.push(f);},Fragment:'frag'};
 const webRef={current:{injectJavaScript:(js)=>seen.injected.push(js),reload(){},goBack(){}}};
 React.useRef=(v)=>(v===null?webRef:{current:v});
 const mocks={
  'react':React,'react/jsx-runtime':{jsx:React.createElement,jsxs:React.createElement,Fragment:'frag'},
  'react-native':{ActivityIndicator:'A',Alert:{alert:(t,m,b)=>seen.alerts.push({t,m,b})},AppState:{currentState:appState,addEventListener:(e,f)=>{seen.listeners.push(f);return {remove(){}};}},BackHandler:{addEventListener:()=>({remove(){}})},Linking:{openURL:()=>Promise.resolve(),openSettings:()=>{seen.opened++;return Promise.resolve();}},Platform:{OS:'android',Version:34},Pressable:'P',StyleSheet:{create:(x)=>x},Text:'T',View:'V'},
  'expo-status-bar':{StatusBar:'S'},'expo-constants':{__esModule:true,default:{expoConfig:{extra:{testRemindersUntil:'2099-12-31',appUrl:'https://upzoneapp.fr/account.html'}}}},
  'react-native-safe-area-context':{SafeAreaProvider:'SP',SafeAreaView:'SV'},'react-native-webview':{WebView:'W'},
  'expo-notifications':notif,'expo-updates':{isEmbeddedLaunch:false,updateId:'01a2080f-ef01'},
  './reminders':require('../mobile/reminders.js'),
 };
 const m=new Module(file);m.filename=file;m.paths=Module._nodeModulePaths(path.dirname(file));
 m.require=(id)=>{if(id in mocks)return mocks[id];throw new Error('unexpected import in App.js: '+id);};
 m._compile(code,file);
 const App=m.exports.default;App();effects.forEach(f=>f());
 const fromPage=(data,url='https://upzoneapp.fr/account.html')=>webProps.onMessage({nativeEvent:{data:typeof data==='string'?data:JSON.stringify(data),url}});
 return {seen,p,fromPage,settle:()=>new Promise(r=>setTimeout(r,60))};
}

test('app start, the phone refuses without a question: the app shows its own invitation, with the readout, and « Autoriser » opens the phone settings',async()=>{
 const a=startApp({after:{status:'denied',granted:false,canAskAgain:false}});await a.settle();
 assert.equal(a.seen.alerts.length,1);
 const al=a.seen.alerts[0];
 assert.equal(al.t,'Rappels du test');
 assert.match(al.m,/autorise les notifications/);
 assert.match(al.m,/\[a=34 ch=ok get=undetermined\/1 req=denied\/0\/\d+ms\]/);
 assert.deepEqual(al.b.map(x=>x.text),['Plus tard','Autoriser']);
 al.b[1].onPress();assert.equal(a.seen.opened,1);
 assert.ok(a.seen.injected.some(js=>js.includes('window.__upzoneNotif="a=34 ch=ok get=undetermined/1 req=denied/0/')),'the settings page receives the readout');
});

test('app start, the person allows: no invitation, reminders planned, the readout says how many',async()=>{
 const a=startApp();await a.settle();
 assert.equal(a.seen.alerts.length,0);
 assert.ok(a.p.Notifications._p.length>0);
 assert.ok(a.seen.injected.some(js=>/plan=\d+/.test(js)));
});

test('back from the phone settings with notifications switched on: reminders are planned, no second invitation',async()=>{
 const a=startApp({after:{status:'denied',granted:false,canAskAgain:false}});await a.settle();
 assert.equal(a.seen.alerts.length,1);assert.equal(a.p.Notifications._p.length,0);
 a.p.Notifications.getPermissionsAsync=()=>Promise.resolve({status:'granted',granted:true,canAskAgain:true});
 a.seen.listeners.forEach(f=>f('active'));await a.settle();
 assert.ok(a.p.Notifications._p.length>0,'planned after coming back');
 assert.equal(a.seen.alerts.length,1,'still one invitation only');
});

// --- UPZONE's settings screen asks the app: status, turn on, send a test ---
const ask=(p,action,extra={})=>notifRequest({Notifications:p.Notifications,action,wait:fast,...extra});

test('settings: « status » says whether notifications are allowed, without asking anything',async()=>{
 const on=phone({before:{status:'granted',granted:true,canAskAgain:true}});
 assert.deepEqual(await ask(on,'status'),{allowed:true});assert.ok(!on.log.includes('request'));
 const off=phone();assert.deepEqual(await ask(off,'status'),{allowed:false});assert.ok(!off.log.includes('request'));
});

test('settings: « Envoyer un test » plans one notification five seconds later, only if notifications are allowed',async()=>{
 const on=phone({before:{status:'granted',granted:true,canAskAgain:true}});
 assert.deepEqual(await ask(on,'test'),{allowed:true,test:'sent'});
 const sent=on.Notifications._p;assert.equal(sent.length,1);
 assert.equal(sent[0].content.body,TEST_TEXT);
 assert.deepEqual(sent[0].trigger,{type:'interval',seconds:5,channelId:'rappels'});
 const off=phone();assert.deepEqual(await ask(off,'test'),{allowed:false,test:'blocked'});assert.equal(off.Notifications._p.length,0);
});

test('settings: « Activer » asks Android; if the answer is no or Android stays silent, the phone settings for UPZONE open',async()=>{
 let opened=0;const open=async()=>{opened++;};
 const yes=phone();assert.deepEqual(await ask(yes,'enable',{openSettings:open}),{allowed:true});assert.equal(opened,0);
 const no=phone({after:{status:'denied',granted:false,canAskAgain:false}});
 assert.deepEqual(await ask(no,'enable',{openSettings:open}),{allowed:false,opened:true});assert.equal(opened,1);
 const silent=phone({hang:'request'});
 assert.deepEqual(await ask(silent,'enable',{openSettings:open,isForeground:()=>true}),{allowed:false,opened:true});assert.equal(opened,2);
});

test('settings: a phone service that fails is reported in the state, never thrown',async()=>{
 const r=await ask(phone({fail:'get'}),'status');assert.equal(r.allowed,false);assert.match(r.error,/boom get/);
});

test('app: a message from UPZONE\'s settings gets an answer in the page; anything else is ignored',async()=>{
 const a=startApp({before:{status:'granted',granted:true,canAskAgain:true}});await a.settle();
 a.seen.injected.length=0;
 a.fromPage({upzone:'notif',action:'test'});await a.settle();
 assert.ok(a.seen.injected.some(js=>js.includes('window.__upzoneNotifState={"allowed":true,"test":"sent"}')&&js.includes("dispatchEvent(new Event('upzone-notif'))")));
 assert.ok(a.p.Notifications._p.some(x=>x.content.body===TEST_TEXT));
 a.seen.injected.length=0;const before=a.p.Notifications._p.length;
 a.fromPage('not json');a.fromPage({upzone:'notif',action:'delete-everything'});a.fromPage({other:1});
 a.fromPage({upzone:'notif',action:'test'},'https://example.org/evil.html');
 await a.settle();
 assert.equal(a.seen.injected.length,0,'no answer to unknown requests or to a page that is not UPZONE');
 assert.equal(a.p.Notifications._p.length,before);
});

test('website: inside the app the settings show the app\'s own notification row; in a browser nothing changes',()=>{
 const web=fs.readFileSync(path.join(__dirname,'..','src','account.js'),'utf8'),tu=fs.readFileSync(path.join(__dirname,'..','src','tu.js'),'utf8');
 assert.match(web,/const appNotifReady=\(\)=>\/UPZONEApp\/\.test\(navigator\.userAgent\|\|''\)&&!!window\.ReactNativeWebView&&typeof window\.__upzoneNotifState==='object'&&!!window\.__upzoneNotifState;/);
 assert.match(web,/function pushBlock\(\)\{if\(appNotifReady\(\)\)return appNotifBlock\(\);const st=pushSupport\(\);/);
 assert.match(web,/data-action="app-notif-test"/);assert.match(web,/data-action="app-notif-enable"/);
 assert.match(web,/postMessage\(JSON\.stringify\(\{upzone:'notif',action\}\)\)/);
 assert.ok(tu.includes('actives-y les notifications, puis reviens ici'));
});

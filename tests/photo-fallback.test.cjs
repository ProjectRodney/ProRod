// 21 Nov 2026: on some Android phones the system photo picker hands the app a photo it cannot read (every format fails).
// The same photo chosen through the phone's file browser reads fine: the app tests each pick and offers that second way.
const test=require('node:test'),assert=require('node:assert'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');
const app=read('src/account.js'),tu=read('src/tu.js');

test('each chosen photo is tested with a tiny read before it is kept',async()=>{
 const src=app.match(/async function photoReadable\(file\)\{.*?\n/)[0];
 const ctx={};vm.runInNewContext(src+';this.photoReadable=photoReadable;',ctx);
 const ok={slice:()=>({arrayBuffer:async()=>new ArrayBuffer(16)})};
 const denied={slice:()=>({arrayBuffer:async()=>{throw new Error('NotReadableError');}})};
 const empty={slice:()=>({arrayBuffer:async()=>new ArrayBuffer(0)})};
 assert.equal(await ctx.photoReadable(ok),true);
 assert.equal(await ctx.photoReadable(denied),false);
 assert.equal(await ctx.photoReadable(empty),false,'an empty file is not a photo');
});

test('an unreadable pick opens a second way: the file browser, with no type filter, checked here',()=>{
 assert.match(app,/<input class="photo-input" id="photo-files" type="file">/,'no « accept »: Android then opens its file browser');
 assert.match(app,/fromFiles&&file\.type&&!file\.type\.startsWith\('image\/'\)/,'what the file browser returns must be an image');
 assert.match(app,/if\(!\(await photoReadable\(file\)\)\)\{input\.value='';pendingPhoto=null;/,'an unreadable file is never kept');
 assert.equal((app.match(/\$\{photoFallback\(\)\}/g)||[]).length,2,'shown in the first profile form and in « Modifier le profil »');
 // Both forms save a photo picked that way.
 assert.equal((app.match(/form\.querySelector\('#photo'\)\?\.files\?\.\[0\]\|\|pendingPhoto/g)||[]).length,2);
 // The usual picker stays the first choice.
 assert.equal((app.match(/id="photo" name="photo" type="file" accept="image\/\*"/g)||[]).length,2);
});

test('the messages exist in English, « vous » and « tu »',()=>{
 for(const s of ['Votre téléphone n’a pas laissé l’application lire cette photo.','Choisissez un fichier image (une photo).','Utilisez « Choisir depuis mes fichiers », ou essayez une autre photo.']){
  assert.ok(app.includes(s),s);assert.ok(tu.includes(s),'tu: '+s);
 }
 assert.ok(app.includes('Choose from my files'));
 assert.match(read('public/member-design.css'),/\.photo-fallback\{/);
});

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
 assert.equal((app.match(/const file=pendingPhoto\|\|form\.querySelector\('#photo'\)\?\.files\?\.\[0\]/g)||[]).length,2,'the in-memory copy is the one saved');
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

test('the photo is decoded from an in-memory copy and its type comes from its first bytes',()=>{
 const src=app.match(/function photoKind\(b\)\{.*?\n/)[0];
 const ctx={};vm.runInNewContext(src+';this.photoKind=photoKind;',ctx);
 const bytes=(...a)=>Uint8Array.from([...a,0,0,0,0,0,0,0,0,0,0,0,0]).slice(0,12);
 assert.equal(ctx.photoKind(bytes(0xff,0xd8,0xff,0xe1)),'image/jpeg');
 assert.equal(ctx.photoKind(bytes(0x89,0x50,0x4e,0x47)),'image/png');
 assert.equal(ctx.photoKind(Uint8Array.from([0x52,0x49,0x46,0x46,1,2,3,4,0x57,0x45,0x42,0x50])),'image/webp');
 assert.equal(ctx.photoKind(Uint8Array.from([0,0,0,0x18,0x66,0x74,0x79,0x70,0x68,0x65,0x69,0x63])),'image/heic');
 assert.equal(ctx.photoKind(bytes(0x68,0x65,0x6c,0x6c)),'','a text file is not an image');
 assert.match(app,/const c=await photoCopy\(file\);mem=c\.blob;/);
 assert.match(app,/source=await createImageBitmap\(mem\);/);
 assert.doesNotMatch(app,/createImageBitmap\(file\)/,'never decoded straight from the phone\'s file handle');
 assert.match(app,/kept=\(await photoCopy\(file\)\)\.blob/,'the preview uses the copy too');
});

test('a failed decode shows a short technical code, without any personal data',()=>{
 assert.match(app,/entry\[0\]==='photo_unreadable'&&photoDiag\?` \[\$\{photoDiag\}\]`:''/);
 const diag=app.match(/async function prepareImage\(file\)\{.*?\n/)[0];
 assert.doesNotMatch(diag,/file\.name|user\.|email/,'no file name, no account');
});

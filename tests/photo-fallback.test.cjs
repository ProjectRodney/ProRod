// 21 Nov 2026: on some Android phones the system photo picker hands the app a photo it cannot read (every format fails).
// The same photo chosen through the phone's file browser reads fine: the app tests each pick and offers that second way.
const test=require('node:test'),assert=require('node:assert'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');
const app=read('src/account.js'),tu=read('src/tu.js');

// Helpers taken from the app, run here with fake files.
function helpers(){
 const names=['const PHOTO_PIECE','function photoKind','function photoWhole','async function photoPieces','async function photoCopy'];
 const src=names.map(n=>app.split('\n').find(l=>l.startsWith(n))).join('\n');
 const ctx={Blob,Uint8Array,String,Math,Object,Error};vm.runInNewContext(src+';this.photoCopy=photoCopy;this.photoWhole=photoWhole;',ctx);return ctx;
}
const jpeg=n=>{const u=new Uint8Array(n);u.set([0xff,0xd8,0xff,0xe0]);u[n-2]=0xff;u[n-1]=0xd9;return u;};
// A file as a phone hands it over: `whole` says whether one full read works, `upTo` how many bytes can be read in pieces.
const phoneFile=(bytes,{whole=true,upTo=bytes.length}={})=>({size:bytes.length,type:'image/jpeg',
 arrayBuffer:async()=>{if(!whole)throw Object.assign(new Error('x'),{name:'NotReadableError'});return bytes.buffer.slice(0);},
 slice:(a,b)=>({arrayBuffer:async()=>{if(a>=upTo)throw Object.assign(new Error('x'),{name:'NotReadableError'});return bytes.slice(a,Math.min(b,upTo)).buffer;}})});

test('a photo the phone will not hand over whole is read piece by piece, and kept only if complete',async()=>{
 const h=helpers(),big=jpeg(700*1024);
 const normal=await h.photoCopy(phoneFile(big));
 assert.equal(normal.blob.size,big.length);assert.equal(normal.how,'');
 // The tester's case: one full read is refused, pieces are allowed.
 const pieces=await h.photoCopy(phoneFile(big,{whole:false}));
 assert.equal(pieces.blob.size,big.length);assert.equal(pieces.kind,'image/jpeg');
 assert.match(pieces.how,/^r=NotReadableError p=716800\/716800$/);
 // Pieces stop half way: the picture is cut off, it is refused (never a half photo on a profile).
 await assert.rejects(h.photoCopy(phoneFile(big,{whole:false,upTo:300*1024})),e=>e.message==='photo_unreadable'&&/p=307200\/716800/.test(e.how));
 // Nothing can be read at all.
 await assert.rejects(h.photoCopy(phoneFile(big,{whole:false,upTo:0})),e=>e.message==='photo_unreadable');
 assert.equal(h.photoWhole(jpeg(100),'image/jpeg'),true);
 assert.equal(h.photoWhole(new Uint8Array(100),'image/jpeg'),false);
 assert.equal(h.photoWhole(new Uint8Array(100),''),false,'an unknown type read in pieces is never trusted');
});

test('an unreadable pick opens a second way: the file browser, with no type filter, checked here',()=>{
 assert.match(app,/<input class="photo-input" id="photo-files" type="file">/,'no « accept »: Android then opens its file browser');
 assert.match(app,/fromFiles&&file\.type&&!file\.type\.startsWith\('image\/'\)/,'what the file browser returns must be an image');
 assert.match(app,/if\(!kept\)\{input\.value='';pendingPhoto=null;/,'an unreadable file is never kept');
 assert.match(app,/let kept=null;try\{kept=\(await photoCopy\(file\)\)\.blob;\}/,'the whole photo is copied as soon as it is picked');
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

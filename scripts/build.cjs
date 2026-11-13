const fs = require('node:fs');
const esbuild = require('esbuild');
esbuild.buildSync({entryPoints:['src/account.js'],bundle:true,minify:true,format:'iife',platform:'browser',target:['safari15','chrome100'],outfile:'public/account.bundle.js',legalComments:'eof'});
esbuild.buildSync({entryPoints:['src/admin.js'],bundle:true,minify:true,format:'iife',platform:'browser',target:['safari15','chrome100'],outfile:'public/admin.bundle.js',legalComments:'eof'});
fs.cpSync('public','dist',{recursive:true});
// Stamp the published service worker with a fingerprint of the app shell, so every release changes sw.js and phones pick it up.
{const crypto=require('node:crypto');const sw=fs.readFileSync('dist/sw.js','utf8');const list=JSON.parse(sw.match(/const ASSETS = (\[[^\]]*\]);/)[1].replace(/'/g,'"'));
const h=crypto.createHash('sha256');for(const f of list)h.update(fs.readFileSync('dist/'+f.replace(/^\.\//,'')));
const stamped=sw.replace(/const CACHE = 'prorod-shell-v(\d+)';/,(m,v)=>`const CACHE = 'prorod-shell-v${v}-${h.digest('hex').slice(0,10)}';`);
if(stamped===sw)throw new Error('service worker cache name not found');fs.writeFileSync('dist/sw.js',stamped);}

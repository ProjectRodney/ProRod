const fs = require('node:fs');
const esbuild = require('esbuild');
esbuild.buildSync({entryPoints:['src/account.js'],bundle:true,minify:true,format:'iife',platform:'browser',target:['safari15','chrome100'],outfile:'public/account.bundle.js',legalComments:'eof'});
esbuild.buildSync({entryPoints:['src/admin.js'],bundle:true,minify:true,format:'iife',platform:'browser',target:['safari15','chrome100'],outfile:'public/admin.bundle.js',legalComments:'eof'});
fs.cpSync('public','dist',{recursive:true});

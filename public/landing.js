// Welcome page of the site. People who already use UPZONE on this phone (installed app, earlier sign-in or visit) and
// every link that carries something for the app (QR code, e-mail link) go straight to the app; ?landing=1 shows the page.
(function(){
  var q=new URLSearchParams(location.search),h=location.hash||'';
  var has=function(k){try{return !!localStorage.getItem(k);}catch(e){return false;}};
  var standalone=navigator.standalone===true||(window.matchMedia&&matchMedia('(display-mode: standalone)').matches);
  var forApp=q.has('venue')||q.has('start')||q.has('code')||/access_token=|error=|type=/.test(h);
  var known=has('prorod-auth')||has('upzone-visited')||has('upzone-accounts')||has('upzone-passkey-phone');
  if(!q.has('landing')&&(forApp||standalone||known)){location.replace('./account.html'+location.search+h);return;}
  function apply(lang){document.documentElement.lang=lang;var n=document.querySelectorAll('[data-fr]');for(var i=0;i<n.length;i++)n[i].textContent=n[i].getAttribute(lang==='en'?'data-en':'data-fr');var b=document.querySelectorAll('[data-lang]');for(var j=0;j<b.length;j++)b[j].setAttribute('aria-pressed',String(b[j].getAttribute('data-lang')===lang));}
  document.addEventListener('DOMContentLoaded',function(){
    apply(document.documentElement.lang==='en'?'en':'fr');
    document.addEventListener('click',function(e){var b=e.target.closest&&e.target.closest('[data-lang]');if(!b)return;var l=b.getAttribute('data-lang');try{localStorage.setItem('prorod-lang',l);}catch(x){}apply(l);});
  });
})();

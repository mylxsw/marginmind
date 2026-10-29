// No JavaScript-to-native message handlers are installed. Apple executes these
// in a private WKContentWorld. Other engines keep DOM observation counters on
// the page's global object; page code can inspect or change these heuristics,
// but there is no application bridge for it to discover or call.
import 'dart:convert';

const browserProbeScript = r'''
(() => {
  const key = '__marginmindObservation';
  if (!globalThis[key]) {
    const s = {changes: 0, interactions: 0, network: performance.getEntriesByType('resource').length};
    new PerformanceObserver(list => s.network += list.getEntries().length).observe({entryTypes:['resource']});
    document.addEventListener('pointerdown', () => s.interactions++, true);
    new MutationObserver(() => s.changes++).observe(document, {subtree:true,childList:true,attributes:true,characterData:true});
    globalThis[key] = s;
  }
  return JSON.stringify({url:location.href,title:document.title,dom:globalThis[key].changes,
    network:globalThis[key].network,interactions:globalThis[key].interactions,complete:document.readyState === 'complete'});
})()
''';

const browserCaptureScript = r'''
(() => {
  const resources = new Set();
  for (const node of document.querySelectorAll('img,source,link[rel="stylesheet"],video[poster]')) {
    const value = node.currentSrc || node.src || node.href || node.poster;
    if (value && /^(https?:|blob:|data:image\/)/i.test(value)) resources.add(value);
  }
  for (const entry of performance.getEntriesByType('resource')) {
    if (['img','css','link'].includes(entry.initiatorType) && /^https?:/i.test(entry.name)) resources.add(entry.name);
  }
  return JSON.stringify({url:location.href,title:document.title,
    dom:'<!DOCTYPE html>\n'+document.documentElement.outerHTML,resources:Array.from(resources)});
})()
''';

/// Only the clone is changed. Async results are polled because Android and
/// WebView2 evaluate APIs do not await JavaScript promises.
String browserDocumentScript(String readability, String token, {required bool original}) =>
    '''
(() => {
  $readability
  const key = ${jsonEncode(token)}, original = $original;
'''
    r'''
  const abort = new AbortController(), x = scrollX, y = scrollY;
  const job = {cancel: () => {abort.abort(); scrollTo(x,y);}};
  globalThis[key] = job;
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  (async () => {
    try {
      if (original) {
        let bottom = false;
        try {
          for (let step=0; step<80; step++) {
            if (abort.signal.aborted) throw Error('cancelled');
            scrollTo(0, step * Math.max(200, innerHeight * .8));
            await delay(150);
            if (scrollY + innerHeight >= document.documentElement.scrollHeight - 2) {
              const height = document.documentElement.scrollHeight;
              await delay(250);
              if (height === document.documentElement.scrollHeight) {bottom=true; break;}
            }
          }
          if (!bottom) throw Error('scroll_limit');
        } finally {scrollTo(x,y);}
      }
      if (document.documentElement.outerHTML.length > 16*1024*1024) throw Error('dom_limit');
      const clone = document.cloneNode(true), source = document.querySelectorAll('img');
      clone.querySelectorAll('img').forEach((node,i) => {
        const live = source[i];
        node.setAttribute('src', live.currentSrc || live.src || '');
        node.removeAttribute('srcset');
      });
      const liveElements=document.body.querySelectorAll('*'), clonedElements=clone.body.querySelectorAll('*');
      liveElements.forEach((node,i)=>{
        const style=getComputedStyle(node);
        if(style.display==='none'||style.visibility==='hidden') clonedElements[i].remove();
      });
      // DOM values and hidden UI must not leak into a snapshot.
      clone.querySelectorAll('input,textarea,select,button,script,noscript,template,iframe,object,embed,base,link,meta,source,video,audio').forEach(n=>n.remove());
      clone.querySelectorAll('form').forEach(n=>n.replaceWith(...n.childNodes));
      clone.querySelectorAll('[hidden],[aria-hidden="true"]').forEach(n=>n.remove());
      const clean = root => {
        root.querySelectorAll('*').forEach(n => {
          for (const a of [...n.attributes]) {
            if (!['src','href','alt','title','colspan','rowspan','id','class','lang','dir'].includes(a.name)) n.removeAttribute(a.name);
          }
          if (n.hasAttribute('href')) {
            try {
              const u = new URL(n.getAttribute('href'), document.baseURI);
              if (!['http:','https:','mailto:'].includes(u.protocol) || u.username || u.password) n.removeAttribute('href');
              else n.setAttribute('href',u.href);
            } catch (_) {n.removeAttribute('href');}
          }
        });
        root.querySelectorAll('style,svg,math').forEach(n=>n.remove());
      };
      clean(clone);
      let article = new Readability(clone.cloneNode(true), {disableJSONLD:true,maxElemsToParse:50000}).parse();
      if (!article || !article.textContent.trim()) {
        if(!original) throw Error('no_content');
        article={content:clone.body.innerHTML};
      }
      const body = document.implementation.createHTMLDocument('');
      body.body.innerHTML = article.content;
      clean(body);
      const resources = {}, diagnostics = [], byUrl = new Map();
      let total=0, count=0;
      for (const root of [body,clone]) {
        for (const img of root.querySelectorAll('img')) {
          let uri;
          try {uri = new URL(img.getAttribute('src'),document.baseURI);} catch (_) {img.removeAttribute('src');continue;}
          if (uri.username || uri.password || !/^(https?:|blob:|data:)$/.test(uri.protocol)) {img.removeAttribute('src');continue;}
          if (uri.href.split('#')[0]===location.href.split('#')[0]) {img.removeAttribute('src');diagnostics.push('image_unavailable');continue;}
          if (!byUrl.has(uri.href)) {
            let path=null;
            if (count++ < 64) {
              try {
                const timer=setTimeout(()=>abort.abort(),30000);
                let response, bytes;
                try {
                  response=await fetch(uri.href,{credentials:'include',signal:abort.signal,referrerPolicy:'no-referrer'});
                  if (!response.ok || Number(response.headers.get('content-length'))>5*1024*1024) {
                    await response.body?.cancel();throw Error('image_failed');
                  }
                  const reader=response.body.getReader(), chunks=[]; let length=0;
                  try {
                    while (true) {
                      const {done,value}=await reader.read(); if (done) break;
                      length+=value.length;
                      if (length>5*1024*1024 || total+length>32*1024*1024) throw Error('image_limit');
                      chunks.push(value);
                    }
                  } finally {await reader.cancel();reader.releaseLock();}
                  bytes=new Uint8Array(length);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.length;}
                } finally {clearTimeout(timer);}
                // Raster data stays opaque; SVG is reduced to static markup.
                let ext=null;
                if(bytes[0]===137&&bytes[1]===80&&bytes[2]===78&&bytes[3]===71) ext='png';
                else if(bytes[0]===255&&bytes[1]===216&&bytes[2]===255) ext='jpg';
                else if(String.fromCharCode(...bytes.slice(0,3))==='GIF') ext='gif';
                else if(String.fromCharCode(...bytes.slice(0,4))==='RIFF'&&String.fromCharCode(...bytes.slice(8,12))==='WEBP') ext='webp';
                else {
                  const svg=new DOMParser().parseFromString(new TextDecoder().decode(bytes),'image/svg+xml');
                  if(svg.documentElement.localName==='svg'&&!svg.querySelector('parsererror')) {
                    svg.querySelectorAll('script,foreignObject,iframe,object,embed,style,animate,animateMotion,animateTransform,set').forEach(n=>n.remove());
                    svg.querySelectorAll('*').forEach(n=>{for(const a of [...n.attributes]) {
                      if(/^on/i.test(a.name)||a.name==='style'||/url\s*\(/i.test(a.value)||
                        (/(^|:)href$/i.test(a.name)&&!a.value.startsWith('#'))) n.removeAttribute(a.name);
                    }});
                    bytes=new TextEncoder().encode(new XMLSerializer().serializeToString(svg.documentElement));ext='svg';
                  }
                }
                if(!ext) throw Error('image_type');
                total+=bytes.length;path='resources/image-'+count+'.'+ext;
                let binary=''; for(let i=0;i<bytes.length;i+=8192) binary+=String.fromCharCode(...bytes.slice(i,i+8192));
                resources[path]=btoa(binary);
              } catch (_) {diagnostics.push('image_unavailable');}
            } else diagnostics.push('image_limit');
            byUrl.set(uri.href,path);
          }
          const path=byUrl.get(uri.href);
          if(path) img.setAttribute('src',path); else img.removeAttribute('src');
        }
      }
      const meta=clone.createElement('meta');meta.setAttribute('http-equiv','Content-Security-Policy');
      meta.setAttribute('content',"default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; form-action 'none'");
      clone.head.prepend(meta);
      job.result={url:location.href,title:document.title,html:body.body.innerHTML,
        snapshot:'<!doctype html>\n'+clone.documentElement.outerHTML,resources,diagnostics};
    } catch (_) {job.result={error:'capture_failed'};}
  })();
  return '{}';
})()
''';

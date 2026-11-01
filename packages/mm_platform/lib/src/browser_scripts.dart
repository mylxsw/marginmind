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
  const abort = new AbortController(), x = scrollX, y = scrollY, initialUrl = location.href;
  // Leave time for serialization and the Dart-side 45 second deadline.
  const imageDeadline = performance.now() + 40000;
  let printHost, printStyle;
  const cleanupPrint = () => {printHost?.remove(); printStyle?.remove();};
  const restore = () => {if(original && location.href===initialUrl) scrollTo(x,y);};
  const job = {stage: original ? 'scrolling' : 'extracting', cancel: () => {abort.abort(); cleanupPrint(); restore();}};
  globalThis[key] = job;
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  (async () => {
    try {
      if (original) {
        let bottom = false;
        try {
          for (let step=0; step<80; step++) {
            if (abort.signal.aborted || location.href!==initialUrl) throw Error('cancelled');
            scrollTo(0, step * Math.max(200, innerHeight * .8));
            await delay(150);
            if (scrollY + innerHeight >= document.documentElement.scrollHeight - 2) {
              const height = document.documentElement.scrollHeight;
              await delay(250);
              if (height === document.documentElement.scrollHeight) {bottom=true; break;}
            }
          }
          if (!bottom) throw Error('scroll_limit');
        } finally {restore();}
      }
      if (document.documentElement.outerHTML.length > 16*1024*1024) throw Error('dom_limit');
      job.stage='extracting';
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
        const fallback = clone.querySelector('main,article,[role="main"]') || clone.body;
        fallback.querySelectorAll('nav,aside,header,footer,[role="navigation"],[role="banner"],[role="contentinfo"]').forEach(n=>n.remove());
        article={content:fallback.innerHTML};
      }
      const body = document.implementation.createHTMLDocument('');
      body.body.innerHTML = article.content;
      clean(body);
      const resources = {}, diagnostics = [], byUrl = new Map();
      let total=0, count=0;
      job.stage='images';
      for (const root of [body,clone]) {
        for (const img of root.querySelectorAll('img')) {
          if(abort.signal.aborted || location.href!==initialUrl) {abort.abort();throw Error('cancelled');}
          let uri;
          try {uri = new URL(img.getAttribute('src'),document.baseURI);} catch (_) {img.removeAttribute('src');continue;}
          if (uri.username || uri.password || !/^(https?:|blob:|data:)$/.test(uri.protocol)) {img.removeAttribute('src');continue;}
          if (uri.href.split('#')[0]===location.href.split('#')[0]) {img.removeAttribute('src');diagnostics.push('image_unavailable');continue;}
          if (!byUrl.has(uri.href)) {
            let path=null;
            if (performance.now() >= imageDeadline) diagnostics.push('image_unavailable');
            else if (count++ < 64) {
              try {
                const imageAbort = new AbortController();
                const cancelImage = () => imageAbort.abort();
                abort.signal.addEventListener('abort',cancelImage,{once:true});
                const timer=setTimeout(cancelImage,Math.min(10000,imageDeadline-performance.now()));
                let response, bytes;
                try {
                  response=await fetch(uri.href,{credentials:'include',signal:imageAbort.signal,referrerPolicy:'no-referrer'});
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
                } finally {
                  clearTimeout(timer);
                  abort.signal.removeEventListener('abort',cancelImage);
                }
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
      job.stage='serializing';
      meta.setAttribute('content',"default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; form-action 'none'");
      clone.head.prepend(meta);
      if(abort.signal.aborted || location.href!==initialUrl) throw Error('cancelled');
      // Print a separate, isolated article. Site CSS must never shrink the
      // entire PDF to accommodate a desktop sidebar or an oversized table.
      job.preparePrint = async () => {
        cleanupPrint();
        printHost = document.createElement('div');
        printHost.id = key + '_print';
        printHost.style.display = 'none';
        const shadow = printHost.attachShadow({mode:'closed'});
        const style = document.createElement('style');
        style.textContent = `
          :host {color:#202124; font:13pt/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;}
          article {display:block; width:auto; margin:0; overflow-wrap:anywhere;}
          h1,h2,h3,h4,h5,h6 {line-height:1.3; break-after:avoid; margin:1.3em 0 .55em;}
          h1 {font-size:24pt; margin-top:0;} h2 {font-size:19pt;} h3 {font-size:16pt;}
          h4,h5,h6 {font-size:13pt;}
          p,ul,ol,blockquote,figure,pre,table {margin:0 0 1em;}
          p,li {orphans:3; widows:3;}
          a {color:inherit; text-decoration:underline;}
          img {max-width:100%; height:auto; max-height:680pt; object-fit:contain;}
          figure {margin-left:0; margin-right:0;}
          figcaption {font-size:11pt; color:#555;}
          blockquote {margin-left:0; padding-left:14pt; border-left:2pt solid #ddd;}
          pre {white-space:pre-wrap; overflow-wrap:anywhere; padding:10pt; background:#f5f5f5;}
          pre,code {font-family:ui-monospace,monospace; font-size:11pt;}
          table {width:100%; table-layout:fixed; border-collapse:collapse; font-size:11pt;}
          th,td {border:0.5pt solid #ddd; padding:6pt; overflow-wrap:anywhere;}
          thead {display:table-header-group;} tr {break-inside:avoid;}
          hr {border:0; border-top:0.5pt solid #ddd; margin:18pt 0;}
        `;
        const articleNode = document.createElement('article');
        articleNode.innerHTML = body.body.innerHTML;
        // A title is frequently outside Readability's extracted content.
        if (!articleNode.querySelector('h1') && document.title.trim()) {
          const heading = document.createElement('h1');
          heading.textContent = document.title;
          articleNode.prepend(heading);
        }
        for (const img of articleNode.querySelectorAll('img')) {
          const path = img.getAttribute('src'), bytes = resources[path];
          if (!bytes) {img.remove(); continue;}
          const ext = path.split('.').pop();
          const mime = ext==='svg' ? 'image/svg+xml' : ext==='jpg' ? 'image/jpeg' : 'image/'+ext;
          img.src = 'data:'+mime+';base64,'+bytes;
        }
        shadow.append(style,articleNode);
        printStyle = document.createElement('style');
        printStyle.textContent = `@media print {
          @page {size:A4; margin:36pt;}
          html,body {display:block!important; width:auto!important; min-width:0!important;
            max-width:none!important; height:auto!important; margin:0!important; padding:0!important;
            overflow:visible!important; background:white!important; transform:none!important; zoom:1!important;}
          body > * {display:none!important;}
          body > #${printHost.id} {display:block!important; position:static!important;
            width:auto!important; margin:0!important; padding:0!important;}
        }`;
        document.head.append(printStyle);
        document.body.append(printHost);
        await Promise.all([...articleNode.querySelectorAll('img')].map(img=>img.decode().catch(()=>{})));
      };
      job.result={url:initialUrl,title:document.title,html:body.body.innerHTML,
        snapshot:'<!doctype html>\n'+clone.documentElement.outerHTML,resources,diagnostics};
    } catch (_) {job.result={error:'capture_failed'};}
  })();
  return '{}';
})()
''';

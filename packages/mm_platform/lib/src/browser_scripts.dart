// No JavaScript-to-native message handlers are installed. Apple executes these
// in a private WKContentWorld. Other engines keep DOM observation counters on
// the page's global object; page code can inspect or change these heuristics,
// but there is no application bridge for it to discover or call.
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

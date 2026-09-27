const ENDPOINT = 'http://127.0.0.1:8000/api/extension/review';
const DOCUMENT_ENDPOINT = 'http://127.0.0.1:8000/api/extension/document';
function supported(url) {
  try { const u = new URL(url); return u.protocol === 'https:' && u.hostname === 'chatgpt.com'; }
  catch { return false; }
}
chrome.action.onClicked.addListener(async tab => {
  if (!tab.id || !supported(tab.url)) {
    await chrome.action.setBadgeText({tabId:tab.id, text:'GPT'});
    await chrome.action.setTitle({tabId:tab.id, title:'Open chatgpt.com, then click PromptZero again.'});
    return;
  }
  try {
    await chrome.scripting.executeScript({target:{tabId:tab.id}, files:['content.js']});
    await chrome.action.setBadgeText({tabId:tab.id, text:''});
  } catch {
    await chrome.action.setBadgeText({tabId:tab.id, text:'!'});
    await chrome.action.setTitle({tabId:tab.id, title:'Reload ChatGPT, then click PromptZero again.'});
  }
});
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || !sender.tab || sender.frameId !== 0 || !supported(sender.url)) return false;
  if (message?.type === 'promptzero.document') {
    if (typeof message.name !== 'string' || !Array.isArray(message.bytes) || message.bytes.length > 4000000) { respond({error:'Choose a PDF, TXT, or Markdown file under 4 MB.'}); return false; }
    const form = new FormData(); form.append('document', new Blob([new Uint8Array(message.bytes)]), message.name);
    fetch(DOCUMENT_ENDPOINT,{method:'POST',credentials:'omit',redirect:'error',signal:AbortSignal.timeout(20000),headers:{'X-PromptZero-Client':'extension-v1'},body:form})
      .then(async response=>{const data=await response.json();if(!response.ok)throw new Error(data.detail||'Document conversion failed.');respond({data});})
      .catch(error=>respond({error:error.message==='Failed to fetch'?'Start PromptZero with ./run.sh, then retry.':error.message}));
    return true;
  }
  if (message?.type !== 'promptzero.review' || typeof message.prompt !== 'string' || !message.prompt.trim() || message.prompt.length > 20000) {
    respond({error:'Enter a draft between 1 and 20,000 characters.'}); return false;
  }
  // Fixed endpoint and payload; the page cannot use this as an arbitrary fetch proxy.
  fetch(ENDPOINT, {
    method:'POST', credentials:'omit', redirect:'error', signal:AbortSignal.timeout(15000),
    headers:{'Content-Type':'application/json', 'X-PromptZero-Client':'extension-v1'},
    body:JSON.stringify({prompt:message.prompt, budget:1024, protocol:1})
  }).then(async response => {
    const data = await response.json();
    if (!response.ok) throw new Error(typeof data.detail === 'string' ? data.detail : 'The compiler rejected this draft.');
    const saved=Math.max(0,Number(data?.metrics?.saved)||0); chrome.action.setBadgeText({tabId:sender.tab.id,text:saved?`-${Math.min(saved,999)}`:''}); chrome.action.setBadgeBackgroundColor?.({tabId:sender.tab.id,color:'#59d98e'}); respond({data});
  }).catch(error => respond({error:error.name === 'TimeoutError' ? 'Compiler timed out. Try a shorter draft.' : (error.message === 'Failed to fetch' ? 'Start PromptZero with ./run.sh, then retry. The extension connects only to 127.0.0.1:8000.' : error.message)}));
  return true;
});

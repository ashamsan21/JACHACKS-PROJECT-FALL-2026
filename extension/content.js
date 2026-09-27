(() => {
  const hostId = 'promptzero-extension-panel';
  const existing = document.getElementById(hostId);
  if (existing) { existing.dispatchEvent(new Event('promptzero-toggle')); return; }
  const host = document.createElement('div'); host.id = hostId;
  host.style.cssText = 'position:fixed;right:18px;bottom:18px;z-index:2147483647;';
  const root = host.attachShadow({mode:'open'});
  root.innerHTML = `<style>
    :host{all:initial;color-scheme:dark}*{box-sizing:border-box}section{width:min(440px,calc(100vw - 36px));max-height:85vh;overflow:auto;background:#12181e;color:#e5e9ed;border:1px solid #3a4b40;border-radius:15px;box-shadow:0 18px 70px #0009;font:14px/1.6 system-ui,sans-serif;padding:20px}header{display:flex;align-items:center;gap:10px}h2{font-size:18px;letter-spacing:-.6px;margin:0}small{display:block;color:#96a3b0;font-size:12px}button{font:inherit;border-radius:7px;border:1px solid #3c4943;background:#202b25;color:#cbf8da;padding:8px 12px;cursor:pointer}button:disabled{opacity:.4;cursor:default}button:focus-visible{outline:2px solid #b3f5c9;outline-offset:3px}#close{margin-left:auto;padding:3px 10px;background:none;color:#9ba8b4}#status{margin:14px 0;color:#b9c5d0}#status.error{color:#f5b7a4}.row{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}#analyze,#apply{background:#b3f5c9;color:#14271c;border-color:#b3f5c9}#stats{color:#b3f5c9;font:20px/1.6 ui-monospace,monospace;padding:12px 0;border-top:1px solid #303a44}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:14px/1.8 system-ui,sans-serif;margin:9px 0}#locks{background:#1b2a22;border:1px solid #35503f;border-radius:7px;padding:9px 12px;margin:12px 0;font-size:12px}details{border-top:1px solid #303a44;padding:10px 0}summary{cursor:pointer;color:#cad6e0}li{margin:7px 0}ul{padding-left:20px;font-size:12px;color:#aab8c6}.change{padding:10px 0;border-bottom:1px solid #28323b}.change small{color:#b3f5c9}.change p{font-size:12px;margin:5px 0;white-space:pre-wrap}.vocab{display:flex;gap:7px;flex-wrap:wrap}.vocab button{padding:5px 8px;font-size:12px}.doc{margin-top:15px;padding-top:14px;border-top:1px solid #303a44}#markdown{max-height:180px;overflow:auto;background:#0d1217;padding:10px;border-radius:7px;font-size:11px}del{color:#c2a29c}#restore{display:none}[hidden]{display:none!important}.foot{margin-top:15px;padding-top:12px;border-top:1px solid #303a44;font-size:11px;color:#8494a3}
    </style><section role="dialog" aria-label="PromptZero draft review"><header><h2>p∅ PromptZero</h2><small>PROMPT COPILOT</small><button id="close" aria-label="Close PromptZero">×</button></header><div id="status" role="status" aria-live="polite">Review your current draft before you send it.</div><small>Your draft and selected document go only to the local Jac compiler. Nothing is sent automatically.</small><div class="row"><button id="analyze">Fix wording</button><button id="restore">Undo replacement</button></div><div id="review" hidden><div id="stats"></div><small>ESTIMATED DRAFT TOKENS · NOT TOTAL CHATGPT USAGE</small><pre id="optimized"></pre><div id="locks"></div><div id="vocabulary" hidden><small>WORD FINDER · CLICK TO ADD</small><div class="vocab" id="vocabButtons"></div></div><details><summary id="issueTitle">Observations</summary><ul id="issues"></ul></details><details><summary>Context diff</summary><div id="diff"></div></details><div class="row"><button id="apply">Use optimized</button><button id="copy">Copy optimized</button></div></div><div class="doc"><strong>PDF → Markdown</strong><small>Text PDFs, TXT, or MD · local · 4 MB max</small><div class="row"><button id="chooseDoc">Choose file</button><input id="document" type="file" accept=".pdf,.txt,.md" hidden></div><div id="documentResult" hidden><pre id="markdown"></pre><div class="row"><button id="copyMarkdown">Copy Markdown</button><button id="insertMarkdown">Add to draft</button></div></div></div><div class="foot">Jac rules · no model calls · never sends your message<br>Review every replacement and vocabulary suggestion before sending.</div></section>`;
  document.documentElement.append(host);
  const $ = id => root.getElementById(id);
  let snapshot = null, review = null, undo = null, pending = false, generation = 0;
  function composer() {
    // Deliberately avoid generic contenteditable selectors that might match conversation editing.
    return [...document.querySelectorAll('#prompt-textarea, textarea[data-id="root"]')].find(e => e.getClientRects().length && !e.disabled && (e.tagName === 'TEXTAREA' || e.isContentEditable));
  }
  function read(editor) { return editor.tagName === 'TEXTAREA' ? editor.value : editor.innerText; }
  function status(text, error=false) { $('status').textContent=text; $('status').className=error?'error':''; }
  function current(saved) { return saved && saved.editor.isConnected && saved.url===location.href && composer()===saved.editor && read(saved.editor)===saved.text; }
  function check() {
    if (review && !current(snapshot)) { $('apply').disabled=true; $('copy').disabled=true; status('Your draft or conversation changed. Analyze it again.'); }
    if (undo && !current(undo)) { undo=null; $('restore').style.display='none'; }
  }
  const interval = setInterval(check,500);
  function close() { generation++; clearInterval(interval); document.removeEventListener('input',check,true); host.remove(); }
  $('close').onclick=close; host.addEventListener('promptzero-toggle',close);
  document.addEventListener('input',check,true);
  root.addEventListener('keydown',e=>{if(e.key==='Escape'){e.stopPropagation();close();}});
  $('analyze').onclick=async(event)=>{
    if(!event.isTrusted)return;
    if(pending)return;
    const editor=composer();
    if(!editor){status('ChatGPT’s draft editor was not found. Open a conversation and try again.',true);return;}
    const text=read(editor);
    if(!text.trim()){status('Write a prompt in ChatGPT first.',true);return;}
    if(text.length>20000){status('Use a draft of 20,000 characters or fewer.',true);return;}
    snapshot={editor,text,url:location.href};review=null;pending=true;const request=++generation;
    $('review').hidden=true;$('analyze').disabled=true;status('Running the Jac compiler…');
    try{
      const response=await chrome.runtime.sendMessage({type:'promptzero.review',prompt:text});
      if(request!==generation)return;
      if(response?.error)throw new Error(response.error);
      const data=response?.data;
      if(data?.protocol!==1 || typeof data.optimized!=='string' || !Array.isArray(data.diff) || !Array.isArray(data.issues) || !data.metrics || data.original!==text.trim())throw new Error('Unexpected compiler response. Update the backend and extension together.');
      review=data;$('optimized').textContent=data.optimized;
      $('stats').textContent=`💾 ${Math.max(0,data.metrics.saved)} tokens saved · ~${data.metrics.before} → ~${data.metrics.after}`;
      $('locks').textContent=data.lock_summary;
      $('issueTitle').textContent=`Observations (${data.issues.length})`;$('issues').replaceChildren();
      for(const issue of data.issues){const li=document.createElement('li');li.textContent=`${issue.title}: ${issue.detail}`;$('issues').append(li);}
      $('diff').replaceChildren();
      for(const change of data.diff){const row=document.createElement('div');row.className='change';const label=document.createElement('small');label.textContent=change.kind.toUpperCase();row.append(label);const p=document.createElement('p');p.textContent=change.original;row.append(p);if(change.result!==change.original){const after=document.createElement('p');after.textContent=`→ ${change.result || '(Removed duplicate)'}`;row.append(after);}$('diff').append(row);}
      $('review').hidden=false;$('apply').disabled=!data.can_apply;$('copy').disabled=false;
      $('vocabButtons').replaceChildren();
      for(const item of data.vocabulary||[]){const b=document.createElement('button');b.textContent=item.term;b.title=item.meaning;b.onclick=()=>{const editor=composer();if(!editor)return;replace(editor,`${read(editor).trim()} ${item.insert}`);status(`Added “${item.term}”. Review the draft, then fix wording again.`);};$('vocabButtons').append(b);}
      $('vocabulary').hidden=!data.vocabulary?.length;
      status(data.can_apply?'Review the changes. Use optimized replaces the draft without sending.':data.apply_reason);
      check();
    }catch(error){if(request===generation)status(error.message || 'Connection failed. Start the local PromptZero server and retry.',true);}
    finally{if(request===generation){pending=false;$('analyze').disabled=false;}}
  };
  function replace(editor,text){
    editor.focus();
    if(editor.tagName==='TEXTAREA'){
      Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(editor,text);
      editor.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertReplacementText',data:text}));
    }else{
      const selection=window.getSelection(),range=document.createRange();range.selectNodeContents(editor);selection.removeAllRanges();selection.addRange(range);
      // Native editing updates ProseMirror and its undo history. No Enter or submit event.
      if(!document.execCommand('insertText',false,text))throw new Error('This editor blocked replacement. Copy the optimized text and paste it manually.');
    }
    if(read(editor).trim()!==text.trim())throw new Error('Replacement could not be verified. Check your draft; use the editor’s Undo if needed.');
  }
  $('apply').onclick=(event)=>{
    if(!event.isTrusted)return;
    if(!review?.can_apply || !current(snapshot)){check();return;}
    try{
      const saved=snapshot;replace(saved.editor,review.optimized);
      undo={editor:saved.editor,text:read(saved.editor),url:saved.url,original:saved.text};review=null;
      $('apply').disabled=true;$('copy').disabled=true;$('restore').style.display='inline-block';status('Draft replaced. Review it in ChatGPT, then send when you’re ready.');
    }catch(error){status(error.message,true);}
  };
  $('restore').onclick=(event)=>{
    if(!event.isTrusted)return;
    if(!current(undo)){status('Draft changed after replacement. Use ChatGPT’s Undo to avoid overwriting your edits.',true);return;}
    try{const saved=undo;replace(saved.editor,saved.original);undo=null;$('restore').style.display='none';status('Original draft restored. Nothing was sent.');}catch(error){status(error.message,true);}
  };
  $('copy').onclick=async(event)=>{if(!event.isTrusted)return;if(!review || !current(snapshot)){check();return;}try{await navigator.clipboard.writeText(review.optimized);status('Copied. Paste into ChatGPT when ready.');}catch{status('Clipboard access failed. Select the optimized text above and copy it.',true);}};
  let markdown='';
  $('chooseDoc').onclick=()=>$('document').click();
  $('document').onchange=async()=>{const file=$('document').files[0];if(!file)return;if(file.size>4000000){status('Choose a file smaller than 4 MB.',true);return;}status('Converting document to Markdown…');const bytes=Array.from(new Uint8Array(await file.arrayBuffer()));const response=await chrome.runtime.sendMessage({type:'promptzero.document',name:file.name,bytes});if(response?.error){status(response.error,true);return;}markdown=response.data.markdown;$('markdown').textContent=markdown;$('documentResult').hidden=false;status(`Converted ${file.name} to Markdown locally.`);};
  $('copyMarkdown').onclick=async()=>{await navigator.clipboard.writeText(markdown);status('Markdown copied.');};
  $('insertMarkdown').onclick=()=>{const editor=composer();if(!editor){status('ChatGPT’s draft editor was not found.',true);return;}const next=`${read(editor).trim()}\n\n---\n\n${markdown}`.trim();if(next.length>20000){status('The converted document is too large to add to this draft. Copy it instead.',true);return;}replace(editor,next);status('Markdown added to the draft. Nothing was sent.');};
  $('analyze').focus();
})();

let submitted=0,inputs=0;
const $=id=>document.getElementById(id);
function editor(){const e=document.createElement($('mode').value==='rich'?'div':'textarea');e.id='prompt-textarea';e.setAttribute('aria-label','Draft');if(e.tagName==='DIV'){e.contentEditable='true';e.setAttribute('role','textbox');e.textContent='Could you please explain gravity. Include exactly 3 examples.';}else e.value='Could you please explain gravity. Include exactly 3 examples.';e.addEventListener('input',()=>{$('inputs').textContent=`Editor input events: ${++inputs}`;});$('editor-slot').replaceChildren(e);}
editor();$('mode').onchange=editor;
$('composer').onsubmit=e=>{e.preventDefault();$('sent').textContent=`Messages submitted: ${++submitted}`;};
$('navigate').onclick=()=>history.pushState({},'',`/?conversation=${Date.now()}`);
window.chrome={runtime:{sendMessage:async message=>{const response=await fetch('/review',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({prompt:message.prompt,protocol:1,budget:1024})});const data=await response.json();return response.ok?{data}:{error:data.detail};}}};
$('open').onclick=()=>{const script=document.createElement('script');script.src='/content.js';document.body.append(script);};

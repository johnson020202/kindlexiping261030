/* One data source and one deterministic daily selection for web, PNG and Kindle. */
'use strict';
const books = window.BOOKS;
const flat = books.flatMap((book, bookIndex) => book.excerpts.map((excerpt, excerptIndex) => ({...excerpt, book, bookIndex, excerptIndex})));
const $ = id => document.getElementById(id);
let current;
function localDate(date = new Date()) { return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`; }
function dailyIndex(date = localDate()) {
  // FNV-1a, no network, timer or account required. Same date => same excerpt.
  let hash = 2166136261;
  for (const char of `kindlexiping261030:v1:${date}`) { hash ^= char.charCodeAt(0); hash = Math.imul(hash,16777619); }
  return (hash >>> 0) % flat.length;
}
function show(index, persist = true) {
  current = (index + flat.length) % flat.length;
  const item = flat[current];
  $('quote').textContent = item.text;
  $('book').textContent = `《${item.book.title}》`;
  $('author').textContent = `${item.book.author}${item.book.translator ? ' 著 · ' + item.book.translator + ' 译' : ' 著'}`;
  $('chapter').textContent = item.chapter;
  $('counter').textContent = `${String(current+1).padStart(4,'0')} / ${flat.length}`;
  $('day-mark').textContent = current === dailyIndex() ? '今日摘抄' : '自由翻阅';
  document.title = `${item.book.title} · 栖息`;
  if (persist) try { localStorage.setItem('kindlexiping.position',String(current)); } catch (_) {}
}
function showToday() { show(dailyIndex()); }
function tick() {
  const d = new Date();
  $('clock').textContent = `${d.getFullYear()} 年 ${d.getMonth()+1} 月 ${d.getDate()} 日\n${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')} · ${['星期日','星期一','星期二','星期三','星期四','星期五','星期六'][d.getDay()]}`;
  $('date-top').textContent = `${localDate(d)} / A QUIET MOMENT`;
  if ($('day-mark').textContent === '今日摘抄') show(dailyIndex(d),false);
}
function library(filter = '') {
  const query = filter.trim().toLowerCase();
  $('book-list').replaceChildren();
  const matches = books.map((book,index)=>({book,index})).filter(({book}) => `${book.title}${book.author}${book.translator || ''}`.toLowerCase().includes(query));
  if (!matches.length) { $('book-list').innerHTML = '<p class="no-results">书架里暂时找不到这本书</p>'; return; }
  for (const {book,index} of matches) {
    const button = document.createElement('button'); button.className='book-item';
    const number = document.createElement('span'); number.className='index'; number.textContent=String(index+1).padStart(3,'0');
    const title = document.createElement('span'); title.className='book-title'; title.textContent=book.title;
    const count = document.createElement('small'); count.textContent=`${book.excerpts.length} 段原文`; title.append(count);
    const author = document.createElement('span'); author.className='book-author'; author.textContent=`${book.author}${book.translator ? '\n'+book.translator+' 译':''}`;
    button.append(number,title,author); button.onclick=()=>{show(index*50);$('books').close();}; $('book-list').append(button);
  }
}
$('previous').onclick=()=>show(current-1); $('next').onclick=()=>show(current+1); $('today').onclick=showToday;
$('library').onclick=()=>{library();$('books').showModal();$('search').focus();}; $('close-library').onclick=()=>$('books').close();
$('books').addEventListener('click',event=>{if(event.target===$('books')) $('books').close();});
$('search').oninput=event=>library(event.target.value);
$('export').onclick=()=>{const item=flat[current],params=new URLSearchParams({quote:item.text,book:item.book.title,author:$('author').textContent,date:$('clock').textContent.replace('\n',' · ')});window.location.href=`poster.html?${params}`;};
document.addEventListener('keydown',event=>{if($('books').open || event.target.tagName==='INPUT')return; if(event.key==='ArrowLeft')show(current-1);if(event.key==='ArrowRight')show(current+1);if(event.key==='Home')showToday();});
let touchStart;
document.addEventListener('touchstart',event=>{touchStart=event.changedTouches[0].clientX;},{passive:true});
document.addEventListener('touchend',event=>{if(touchStart===undefined || $('books').open)return;const distance=event.changedTouches[0].clientX-touchStart;if(Math.abs(distance)>65)show(current+(distance<0?1:-1));touchStart=undefined;},{passive:true});
if(!Array.isArray(books)||books.length!==100||flat.length<5000) { $('quote').textContent='内容库尚未生成，请先运行 make content。'; throw new Error('Invalid content library'); }
show(dailyIndex());tick();setInterval(tick,15000);

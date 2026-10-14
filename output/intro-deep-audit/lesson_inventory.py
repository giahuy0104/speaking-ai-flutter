import json, hashlib, re
from pathlib import Path
from collections import Counter
ROOT=Path(__file__).resolve().parents[2]
def read(p): return json.loads((ROOT/p).read_text(encoding='utf-8-sig'))
def norm(t): return re.sub(r'\s+', ' ', t).strip()
def sha(t): return hashlib.sha256(norm(t).encode()).hexdigest()
names=['assistant_core','listening_common']+[f'listening_{a}' for a in ['3_5','6_7','8_10','11_12','13_15']]+[f'challenge_{a}' for a in ['3_5','6_7','8_10','11_12','13_15']]
prompts=[]
for name in names:
    m=read(f'assets/data/{name}_audio.json')
    if m.get('enabled',True):
        for p in m['prompts']:
            if p.get('enabled',True): prompts.append(dict(p,manifest=f'assets/data/{name}_audio.json'))
gap=read('assets/data/homi_gap66_audio.json')['prompts']
bykey={p['key']:p for p in prompts}
def lookup(text,locale='vi-VN',key=None):
    p=bykey.get(key) if key else None
    if p and (p['locale']!=locale or p.get('text') and p.get('textHash')!=sha(text)): p=None
    if not key:
        matches=[p for p in prompts if p['locale']==locale and p.get('textHash')==sha(text)]
        p=matches[0] if len(matches)==1 else None
    if p:
        f=ROOT/p['asset']; b=f.read_bytes() if f.exists() else b''
        return {'route':'MP3','key':p['key'],'asset':p['asset'],'manifest':p['manifest'],'bytesVerified':bool(b) and hashlib.sha256(b).hexdigest()==p['sha256'] and (not p.get('sizeBytes') or len(b)==p['sizeBytes'])}
    # Underlying MAIN service can still match the homi_gap66 text.
    if not key:
        matches=[p for p in gap if p.get('enabled') and (p.get('locale')==locale or locale in p.get('lookupLocales',[])) and (p.get('text')==text.strip() or text.strip() in p.get('lookupTexts',[]))]
        if matches:
            p=matches[0]
            return {'route':'MP3-gap66','key':p['key'],'asset':p.get('asset')}
    return {'route':'TTS','requestedKey':key}
def speak(text,title,key=None):
    # Screen probes keyed budget first, then keyless budget when key absent.
    r=lookup(text,key=key)
    if r['route']!='TTS': return [dict(text=text,locale='vi-VN',**r)]
    if title not in text: return [dict(text=text,locale='vi-VN',**lookup(text))]
    before,after=text.split(title,1)
    return [dict(text=t.strip(),locale=loc,**lookup(t.strip(),loc)) for t,loc in [(before,'vi-VN'),(title,'en-US'),(after,'vi-VN')] if t.strip()]
records=[]
for g in read('assets/data/listening_lessons.json')['groups']:
 for topic in g['topics']:
  for l in topic['lessons']:
    title=l.get('titleEn','').strip() or l['titleVi'].strip()
    pre=f"Chủ đề {topic['number']}. " if l['number']==1 else ''
    pre+=f"Bài đầu tiên là {title}. " if l['number']==1 else f"Bài này là {title}. "
    hook=l['entry']['text'].strip()
    text=norm(pre+hook+' Bắt đầu nhé.')
    key=f"listening.lesson.{l['id']}.intro.vi"
    hk=f"listening.lesson.{l['id']}.hook.vi"
    has_hook=l['entry']['kind']=='hook' and lookup(hook,key=hk)['route']!='TTS'
    if has_hook:
        lead=re.sub(r'\.\s*$','',text[:text.index(hook)].strip())
        fresh=speak(lead,title)+speak(hook,title,hk)+speak(text[text.index(hook)+len(hook):].strip(),title)
    else: fresh=speak(text,title,key)
    variants={
      'fresh':fresh,
      'core_resume':speak(f'Mình học tiếp bài {title} nhé.',title,f"listening.lesson.{l['id']}.resume.vi"),
      'relearn_all_stars':speak(f'Mình học lại bài {title} nhé.',title,f"listening.lesson.{l['id']}.relearn.vi"),
      'challenge_resume':speak('Mình tiếp tục câu thử thách nhé.',title,'listening.challenge.resume.vi'),
    }
    if l.get('songTitle'):
      variants['song_resume']=speak(f"Mình nghe lại bài hát {l['songTitle']} nhé.",title,f"listening.lesson.{l['id']}.song_resume.vi")
    for n in range(1,len(l['sentences'])+1):
      young=g['startAge']<=10
      t=f'Bài này bạn còn {n} Ngôi sao chưa chinh phục.'+(' Mình cùng thử nhé!' if young else '')
      variants[f'relearn_remaining_stars_{n}']=speak(t,title,f"listening.lesson.remaining_stars.{n}.{'young' if young else 'older'}.vi")
    records.append({'age':f"{g['startAge']}-{g['endAge']}",'topic':topic['number'],'topicTitle':topic['titleVi'],'lesson':l['number'],'id':l['id'],'title':title,'entryKind':l['entry']['kind'],'usesSplitHook':has_hook,'fullIntroAvailable':lookup(text,key=key),'variants':variants})
summary={'lessons':len(records),'freshWithTts':sum(any(p['route']=='TTS' for p in r['variants']['fresh']) for r in records),'splitHooks':sum(r['usesSplitHook'] for r in records),'hookEntries':sum(r['entryKind']=='hook' for r in records),'ttsSegmentsByVariant':dict(Counter(k for r in records for k,v in r['variants'].items() for p in v if p['route']=='TTS'))}
(ROOT/'output/intro-deep-audit/lesson-agent.json').write_text(json.dumps({'method':'Static screen-routing + text-hash and asset checksum audit. Root also tests production factory.','summary':summary,'lessons':records},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(summary))

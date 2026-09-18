const {execFileSync} = require('child_process');
const files = process.argv.slice(2);
if (files[0] === '--stage') {
  const rules = {
    'lib/features/listening/application/lesson_media_service.dart': h => !/rewindPlayback|Ứng dụng cần quyền micro/.test(h),
    'lib/features/listening/presentation/lesson_challenge_screen.dart': h => /Bạn trả lời nhé/.test(h),
    'lib/features/listening/presentation/lesson_practice_screen.dart': (_,i) => [2,3,5,6,7,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,41,42,43,44,45,46,47,48,49,50,51,52,53].includes(i),
    'lib/features/conversation/presentation/conversation_controller.dart': (_,i) => [0,1,13].includes(i),
    'lib/features/vocabulary/presentation/vocabulary_home_screen.dart': (_,i) => i <= 20 || (i >= 34 && i <= 44),
    'test/features/listening/lesson_guided_flow_test.dart': h => /for \(final command|class _GatedModelVoicePromptService/.test(h),
    'test/features/listening/lesson_media_service_test.dart': h => !/AudioInterruptionMode/.test(h),
    'test/features/vocabulary/vocabulary_home_screen_test.dart': h => /MAIN vocabulary prompt failure|class _FailingJourneyVoicePromptService/.test(h),
  };
  for (const [file, select] of Object.entries(rules)) {
    const parts = execFileSync('git', ['diff','--no-color','--unified=0','HEAD','--',file],{encoding:'utf8'}).split(/(?=^@@ )/m);
    const selected = parts.slice(1).filter(select);
    const base = execFileSync('git',['show','HEAD:'+file],{encoding:'utf8'}).split('\n');
    for (const h of [...selected].reverse()) {
      const match = h.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/);
      const oldStart = Number(match[1]);
      const oldCount = match[2] === undefined ? 1 : Number(match[2]);
      const lines = h.split('\n').slice(1).filter(l=>l.startsWith('+')).map(l=>l.slice(1));
      const removed = h.split('\n').slice(1).filter(l=>l.startsWith('-')).map(l=>l.slice(1));
      const at = oldCount ? oldStart-1 : oldStart;
      if (base.slice(at,at+oldCount).join('\n') !== removed.join('\n')) throw Error('Hunk mismatch '+file);
      base.splice(at,oldCount,...lines);
    }
    const content = base.join('\n').trimEnd()+'\n';
    const oid = execFileSync('git',['hash-object','-w','--stdin'],{input:content,encoding:'utf8'}).trim();
    execFileSync('git',['update-index','--cacheinfo','100644,'+oid+','+file]);
    console.log('Staged '+selected.length+' hunks: '+file);
  }
  process.exit(0);
}
for (const file of files) {
  const diff = execFileSync('git', ['diff', '--no-color', '--unified=0', '--', file], {encoding:'utf8'});
  console.log('\nFILE '+file);
  const hunks = diff.split(/(?=^@@ )/m).slice(1);
  hunks.forEach((h,i)=> console.log(i + ': ' + h.split('\n')[0] + '\n  '+h.split('\n').slice(1,4).join(' ').slice(0,200)));
}

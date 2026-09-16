// Standalone, user-approved 50-line regeneration. Never edits Flutter or live assets.
// Default: dry run. --prepare freezes a plan; --preflight is read-only API access.
// --generate creates one paid request per missing line; uncertain requests never retry.
// --verify is entirely local. Existing audio from other batches is NOT reused.
import {readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync, unlinkSync} from 'node:fs';
import {resolve, dirname, relative, isAbsolute, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const batch = resolve(root, 'deliverables/vocabulary50-eleven-v3-2026-09-16');
const args = process.argv.slice(2);
const option = name => args.includes(name) ? args[args.indexOf(name) + 1] : undefined;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const check = (ok, message) => { if (!ok) throw new Error(message); };
const json = path => JSON.parse(readFileSync(path, 'utf8'));
const writeJsonNew = (path, value) => writeFileSync(path, JSON.stringify(value, null, 2) + '\n', {flag: 'wx'});
const profiles = {
  vi: {voiceId: '5CVDNcIPiOYgRUQuxXd7', speed: 0.9},
  en: {voiceId: 'Nhs7eitvQWFTQBsf0yiT', speed: 0.75},
};
const texts = [
  'Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?',
  'Bạn muốn học nội dung khác hay học tiếp?',
  'Mình nghe tiếp nhé.',
  'Mình tạm dừng nhé.',
  'Đây là câu đầu tiên. Mình nghe lại nhé.',
  'Mình học xong lượt này trước nhé.',
  'Đã có nội dung mới cho bạn. Bắt đầu học thôi!',
  'Mình học tiếp Danh sách hôm nay nhé.',
  'Bạn muốn học nội dung khác hay học lại?',
  'Mình cùng nghe nhé.',
  'Chưa có nội dung ở phần này. Bạn muốn học Ngôi sao hay Luyện lại?',
  'Bạn muốn học Ngôi sao hay Luyện lại?',
  'Bạn đã nghe hết rồi. Bạn muốn học nội dung khác hay học lại?',
  'Mình cùng luyện lại nhé. Bắt đầu thôi!',
  'Mình luyện tiếp nhé.',
  'Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?',
  'Mình đã luyện xong rồi. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?',
  'Không có nội dung cần luyện lại. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?',
  'Mình cùng nghe Ngôi sao nhé.',
  'Bạn chưa có Ngôi sao nào. Bạn muốn học phần Ba mẹ đã thêm hay Luyện lại?',
  'Bạn muốn học phần Ba mẹ đã thêm hay Luyện lại?',
  'Bạn đã nghe hết Ngôi sao rồi. Bạn muốn học nội dung khác hay học lại?',
  'Giọng của bạn đây.',
  'Bạn nói lại nhé.',
  'Đến lượt bạn.',
  'Bạn thử nói nhé.',
  'Nói lại câu này.',
  'Bạn nói tiếng Anh nhé.',
  'Đúng rồi!',
  'Mình thử lại nhé.',
  'HOMI nói mẫu nhé.',
  'HOMI chưa nghe rõ. Bạn nói lại nhé.',
  'Bạn thử lại nhé.',
  'Bạn thử trả lời nhé.',
  'Great!',
  'Thử lại nhé.',
  'HOMI nói đáp án nhé.',
  'Nghe câu đúng nhé.',
  'Exactly.',
  'Try again.',
  'HOMI chưa nghe rõ. Thử lại nhé.',
  'Giỏi lắm!',
  'Tốt lắm!',
  'Nghe lại rồi thử nhé.',
  'Mình nghe câu đúng nhé.',
  'Mình thử một lần nhé.',
  'Good job!',
  'Nice.',
  'Good.',
  'One more time.',
];
const english = new Set([35, 39, 40, 47, 48, 49, 50]);
const prompts = texts.map((text, index) => {
  const number = index + 1, language = english.has(number) ? 'en' : 'vi';
  const id = `VOCAB50-${String(number).padStart(3, '0')}`;
  return {number, id, text, language, ...profiles[language],
    usage: number > 41 ? 'reserve-variant' : number === 6 ? 'current-but-deprecated-in-spec' : 'current',
    file: `audio/${id}.${language}.mp3`};
});
const expected = {provider: 'elevenlabs', modelId: 'eleven_v3', profiles, prompts};
const signature = hash(JSON.stringify(expected));
let secret = '';

function output(path) {
  const full = resolve(batch, path), rel = relative(batch, full);
  check(rel && !rel.startsWith('..') && !isAbsolute(rel), 'Unsafe batch output.');
  return full;
}
function walk(path) {
  return readdirSync(path, {withFileTypes: true}).flatMap(entry => {
    const full = resolve(path, entry.name);
    return entry.isDirectory() ? walk(full) : entry.isFile() ? [full] : [];
  });
}
function baseline() {
  const live = ['assets/data/main_assistant_audio.json', 'assets/data/curriculum_audio.json'];
  const catalog = live.flatMap(path => json(resolve(root, path)).prompts);
  const paths = [...walk(resolve(root, 'lib')).filter(path => path.endsWith('.dart')),
    ...walk(resolve(root, 'assets/data')), resolve(root, 'pubspec.yaml'),
    ...catalog.filter(p => texts.includes(p.text)).map(p => resolve(root, p.asset))];
  return [...new Set(paths)].sort().map(path => ({
    path: relative(root, path).split(sep).join('/'), sha256: hash(readFileSync(path)),
  }));
}
function assertPreserved(plan) {
  for (const entry of plan.baseline) {
    check(hash(readFileSync(resolve(root, entry.path))) === entry.sha256,
      `Existing application file changed: ${entry.path}`);
  }
}
function getPlan() {
  const plan = json(output('plan.json'));
  check(plan.signature === signature && hash(JSON.stringify({provider: plan.provider,
    modelId: plan.modelId, profiles: plan.profiles, prompts: plan.prompts})) === signature,
  'Plan differs from the approved 50 lines.');
  assertPreserved(plan);
  return plan;
}
function settings(prompt) {
  return {text: prompt.text, model_id: 'eleven_v3', language_code: prompt.language,
    seed: 164109, voice_settings: {stability: 0.5, similarity_boost: 0.75, speed: 1.0}};
}
function probe(path) {
  const result = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_entries',
    'format=duration:stream=codec_name,sample_rate,channels', '-of', 'json', path], {encoding: 'utf8'}));
  const duration = Number(result.format.duration), stream = result.streams[0];
  check(Number.isFinite(duration) && duration > 0 && duration < 45 && stream?.codec_name === 'mp3',
    'Invalid MP3 or duration.');
  return {duration, sampleRate: Number(stream.sample_rate), channels: stream.channels};
}
function verify(prompt, decode = true) {
  const receipt = json(output(`receipts/${prompt.id}.final.json`));
  const source = json(output(`receipts/${prompt.id}.source.json`));
  check(source.signature === signature && source.voiceId === prompt.voiceId &&
    JSON.stringify(source.request) === JSON.stringify(settings(prompt)) && source.requestId,
  `Incorrect source request: ${prompt.id}`);
  check(hash(readFileSync(output(`sources/${prompt.id}.source.mp3`))) === source.sourceSha256,
    `Incorrect source checksum: ${prompt.id}`);
  const file = output(prompt.file), bytes = readFileSync(file), info = probe(file);
  const sourceInfo = probe(output(`sources/${prompt.id}.source.mp3`));
  check(receipt.id === prompt.id && receipt.signature === signature && receipt.speed === prompt.speed &&
    receipt.voiceId === prompt.voiceId && receipt.modelId === 'eleven_v3' && receipt.text === prompt.text &&
    receipt.sha256 === hash(bytes) && receipt.bytes === bytes.length && bytes.length <= 2 * 1024 * 1024 &&
    receipt.durationSeconds === info.duration && receipt.sourceDurationSeconds === sourceInfo.duration &&
    receipt.speedMethod === 'ffmpeg-atempo-once' && info.sampleRate === 44100 && info.channels === 1 &&
    Math.abs(info.duration - sourceInfo.duration / prompt.speed) <= 0.25,
  `Output verification failed: ${prompt.id}`);
  if (decode) execFileSync('ffmpeg', ['-hide_banner', '-v', 'error', '-xerror', '-i', file, '-f', 'null', '-'], {stdio: 'pipe'});
  return receipt;
}
function readSecret() {
  const path = option('--api-key-file');
  check(path, 'Provide --api-key-file outside the workspace.');
  const absolute = resolve(path), rel = relative(root, absolute);
  check(rel.startsWith('..') || isAbsolute(rel), 'API key must remain outside workspace.');
  const content = readFileSync(absolute, 'utf8').replace(/^\uFEFF/u, '').trim();
  const keys = [...content.matchAll(/\bsk_[a-zA-Z0-9_-]+\b/gu)].map(m => m[0]);
  secret = keys.length === 1 ? keys[0] : content;
  check(secret && !/\s/u.test(secret), 'Expected exactly one API key.');
}
async function getApi(path, optionalPermission = false) {
  const response = await fetch(`https://api.elevenlabs.io${path}`, {
    headers: {'xi-api-key': secret}, redirect: 'error', signal: AbortSignal.timeout(30_000)});
  const body = await response.json();
  if (!response.ok && optionalPermission && body.detail?.status === 'missing_permissions') return null;
  check(response.ok, `Read-only preflight ${path} HTTP ${response.status}; API detail not logged.`);
  return body;
}
async function preflight() {
  readSecret();
  const subscription = await getApi('/v1/user/subscription');
  const remaining = subscription.character_limit - subscription.character_count;
  check(remaining >= texts.reduce((sum, text) => sum + [...text].length, 0), 'Not enough included character quota.');
  const models = await getApi('/v1/models');
  check(models.some(m => m.model_id === 'eleven_v3' && m.can_do_text_to_speech), 'Eleven v3 unavailable.');
  const voiceReadChecks = [];
  for (const profile of Object.values(profiles)) {
    // voices_read is not required for TTS using a user-supplied voice ID.
    // No permission changes: creation is still authorized/validated by the TTS endpoint.
    const voice = await getApi(`/v1/voices/${profile.voiceId}`, true);
    check(voice === null || voice.voice_id === profile.voiceId, 'Requested voice unavailable.');
    voiceReadChecks.push({voiceId: profile.voiceId, status: voice ? 'verified' : 'voices_read_not_granted'});
  }
  console.log(JSON.stringify({status: 'PREFLIGHT_OK', modelId: 'eleven_v3', profiles,
    remainingCharacters: remaining, plannedCharacters: texts.reduce((sum, text) => sum + [...text].length, 0), voiceReadChecks}));
}
async function generateOne(prompt) {
  const sourceFile = output(`sources/${prompt.id}.source.mp3`);
  const sourceReceipt = output(`receipts/${prompt.id}.source.json`);
  const attemptPath = output(`attempts/${prompt.id}.json`);
  if (!existsSync(sourceFile)) {
    check(!existsSync(attemptPath), `Uncertain previous attempt for ${prompt.id}; inspect provider history before retrying.`);
    writeJsonNew(attemptPath, {id: prompt.id, startedAt: new Date().toISOString(), signature, request: settings(prompt)});
    // Exactly one POST, no network retries and no redirects carrying credentials.
    const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${prompt.voiceId}?output_format=mp3_44100_128`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(120_000),
      headers: {'xi-api-key': secret, 'Content-Type': 'application/json', Accept: 'audio/mpeg'},
      body: JSON.stringify(settings(prompt)),
    });
    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      const status = String(error.detail?.status ?? 'request_rejected').replace(/[^a-zA-Z0-9_-]/g, '');
      writeJsonNew(output(`attempts/${prompt.id}.failure.json`), {httpStatus: response.status, status});
      throw new Error(`ElevenLabs HTTP ${response.status} (${status}); stopped at ${prompt.id}, no automatic retry.`);
    }
    check(response.headers.get('content-type')?.includes('audio/'), 'Expected audio response.');
    const bytes = Buffer.from(await response.arrayBuffer());
    check(bytes.length > 1000, 'Audio response unexpectedly short.');
    writeFileSync(sourceFile, bytes, {flag: 'wx'});
    writeJsonNew(sourceReceipt, {id: prompt.id, signature, provider: 'elevenlabs', voiceId: prompt.voiceId,
      request: settings(prompt), requestId: response.headers.get('request-id'),
      historyItemId: response.headers.get('history-item-id'), characterCost: response.headers.get('character-cost'),
      createdAt: new Date().toISOString(), sourceSha256: hash(bytes)});
  }
  const source = json(sourceReceipt);
  check(source.signature === signature && source.voiceId === prompt.voiceId &&
    JSON.stringify(source.request) === JSON.stringify(settings(prompt)) &&
    source.sourceSha256 === hash(readFileSync(sourceFile)), 'Cached source failed verification.');
  const target = output(prompt.file);
  check(!existsSync(target), `Output already exists without verification: ${prompt.id}`);
  execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-n', '-i', sourceFile,
    '-af', `atempo=${prompt.speed}`, '-map_metadata', '-1', '-c:a', 'libmp3lame',
    '-b:a', '128k', '-ar', '44100', '-ac', '1', target], {stdio: 'pipe'});
  const duration = probe(target).duration, sourceDuration = probe(sourceFile).duration;
  check(Math.abs(duration - sourceDuration / prompt.speed) <= 0.25, 'Speed verification failed.');
  const bytes = readFileSync(target);
  writeJsonNew(output(`receipts/${prompt.id}.final.json`), {...prompt, signature, provider: 'elevenlabs',
    modelId: 'eleven_v3', sha256: hash(bytes), bytes: bytes.length, sourceDurationSeconds: sourceDuration,
    durationSeconds: duration, speedMethod: 'ffmpeg-atempo-once', playbackRate: 1,
    requestId: source.requestId, characterCost: source.characterCost, createdAt: new Date().toISOString()});
  return verify(prompt);
}
function finish(plan, receipts) {
  assertPreserved(plan);
  const summary = {status: 'GENERATED_NOT_ACTIVATED', provider: 'elevenlabs', modelId: 'eleven_v3',
    total: receipts.length, vi: receipts.filter(r => r.language === 'vi').length,
    en: receipts.filter(r => r.language === 'en').length, current: 41, reserve: 9, profiles,
    characters: texts.reduce((sum, text) => sum + [...text].length, 0),
    bytes: receipts.reduce((sum, r) => sum + r.bytes, 0),
    durationSeconds: receipts.reduce((sum, r) => sum + r.durationSeconds, 0),
    protectedFilesUnchanged: plan.baseline.length, acousticHumanReview: false, prompts: receipts};
  const manifest = output('manifest.json');
  if (!existsSync(manifest)) writeJsonNew(manifest, summary);
  else check(JSON.stringify(json(manifest)) === JSON.stringify(summary), 'Completed manifest differs.');
  const csv = ['number,id,language,text,usage,file,voiceId,speed,sha256', ...receipts.map(r =>
    [r.number,r.id,r.language,r.text,r.usage,r.file,r.voiceId,r.speed,r.sha256]
      .map(value => '"' + String(value).replaceAll('"', '""') + '"').join(','))].join('\r\n');
  if (!existsSync(output('danh-sach-50-cau.csv'))) writeFileSync(output('danh-sach-50-cau.csv'), '\uFEFF' + csv + '\r\n', {flag: 'wx'});
  const markdown = `# HOMI — 50 audio Bộ từ vựng\n\n` +
    `Đã tạo mới ${summary.total} MP3 bằng ElevenLabs Eleven v3: 43 tiếng Việt (0,9x), 7 tiếng Anh (0,75x).\n\n` +
    `- Voice Việt: \`5CVDNcIPiOYgRUQuxXd7\`.\n- Voice Anh: \`Nhs7eitvQWFTQBsf0yiT\`.\n` +
    `- Dùng [API Create speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert), từng câu riêng.\n` +
    `- Tốc độ nguồn yêu cầu 1.0; đầu ra chỉnh đúng một lần bằng FFmpeg atempo, giữ cao độ. Phát MP3 ở 1.0x.\n` +
    `- Không đổi manifest, mã nguồn hoặc audio đang hoạt động trong app; chưa tích hợp bộ mới.\n` +
    `- Câu 1–41: luồng hiện tại. Câu 42–50: biến thể dự phòng, không tự bật luân phiên.\n` +
    `- Câu 6 vẫn giữ theo danh sách đã duyệt, dù tài liệu redesign yêu cầu bỏ. Câu 27 giữ bản không có “nhé”.\n` +
    `- Kiểm tra đủ file, giải mã, checksum, model, voice, tốc độ; chưa nghe kiểm định từng câu bằng người.\n` +
    `- ${summary.characters} ký tự; ${summary.durationSeconds.toFixed(3)} giây; ${summary.bytes} byte.\n\n` +
    `## Danh sách\n\n| STT | Ngôn ngữ | Nội dung | Audio | Nhóm |\n|---|---|---|---|---|\n` +
    receipts.map(r => `| ${r.number} | ${r.language} | ${r.text} | [${r.id}](${resolve(batch,r.file).split(sep).join('/')}) | ${r.usage} |`).join('\n') + '\n';
  if (!existsSync(output('README.md'))) writeFileSync(output('README.md'), markdown, {flag: 'wx'});
  const {prompts: _, ...compact} = summary;
  console.log(JSON.stringify(compact, null, 2));
}
async function main() {
  check(prompts.length === 50 && new Set(texts).size === 50 && prompts.filter(p => p.language === 'en').length === 7,
    'Expected the approved 50 unique lines, 43 vi + 7 en.');
  if (args.includes('--prepare')) {
    check(!existsSync(batch), 'Batch folder exists; do not overwrite it.');
    const protectedFiles = baseline();
    mkdirSync(batch, {recursive: true});
    for (const folder of ['audio','sources','receipts','attempts']) mkdirSync(output(folder));
    writeJsonNew(output('plan.json'), {...expected, signature, createdAt: new Date().toISOString(), baseline: protectedFiles});
    console.log(JSON.stringify({status:'PREPARED', total:50, vi:43, en:7, characters:texts.reduce((n,t)=>n+[...t].length,0), protectedFiles:protectedFiles.length}));
    return;
  }
  if (args.includes('--preflight')) { await preflight(); return; }
  if (!args.includes('--generate') && !args.includes('--verify')) {
    console.log(JSON.stringify({mode:'dry-run', ...expected, characters:texts.reduce((n,t)=>n+[...t].length,0)}, null, 2));
    return;
  }
  execFileSync('ffmpeg', ['-version'], {stdio:'ignore'});
  execFileSync('ffprobe', ['-version'], {stdio:'ignore'});
  const plan = getPlan(), receipts = [], generate = args.includes('--generate');
  const limit = Number(option('--limit') ?? '50');
  check(Number.isInteger(limit) && limit >= 1 && limit <= 50, 'Limit must be 1..50.');
  const lock = output('generation.lock');
  if (generate) { readSecret(); writeFileSync(lock, String(process.pid), {flag:'wx'}); }
  let created = 0;
  try {
    for (const prompt of prompts) {
      let receipt;
      if (existsSync(output(`receipts/${prompt.id}.final.json`))) receipt = verify(prompt);
      else {
        check(generate, `Missing final audio: ${prompt.id}`);
        if (created >= limit) break;
        assertPreserved(plan);
        console.log(`GENERATING ${prompt.number}/50 ${prompt.id} [${prompt.language}, ${prompt.speed}x]`);
        receipt = await generateOne(prompt);
        created++;
      }
      receipts.push(receipt);
      console.log(`VERIFIED ${prompt.number}/50 ${prompt.id} ${receipt.durationSeconds.toFixed(3)}s`);
    }
    assertPreserved(plan);
    if (receipts.length === 50) finish(plan, receipts);
    else console.log(JSON.stringify({status:'PARTIAL', verified:receipts.length, created}));
  } finally {
    secret = '';
    if (generate) unlinkSync(lock);
  }
}
main().catch(error => {
  const message = String(error.message ?? error);
  console.error(secret ? message.replaceAll(secret, '[REDACTED]') : message);
  process.exitCode = 1;
});

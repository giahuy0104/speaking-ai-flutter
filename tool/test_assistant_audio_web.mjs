import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const source = readFileSync(new URL('../web/index.html', import.meta.url), 'utf8').match(/<script>([\s\S]*?)<\/script>/u)[1];
const players = [];
const revoked = [];
let autoplayFailure = false;
class Audio {
  constructor(url) { this.url = url; players.push(this); }
  play() { return autoplayFailure ? Promise.reject(new Error('autoplay denied')) : Promise.resolve(); }
  pause() { this.paused = true; }
  removeAttribute() { this.removed = true; }
}
const context = vm.createContext({
  window: { speechSynthesis: { cancel() {} } }, Audio, Blob,
  URL: { createObjectURL() { return `blob:${players.length}`; }, revokeObjectURL(url) { revoked.push(url); } },
});
vm.runInContext(source, context);
const api = context.window;
const first = api.innotrikAuthoredPromptPlayAndWait(new Uint8Array([1,2]));
assert.equal(players[0].playbackRate, 1);
let done = false;
first.then(() => done = true);
await Promise.resolve();
assert.equal(done, false);
players[0].onended();
assert.equal(await first, 'completed');
assert.equal(revoked.length, 1);
const canceled = api.innotrikAuthoredPromptPlayAndWait(new Uint8Array([1]));
api.innotrikVoicePromptStop();
assert.equal(await canceled, 'cancelled');
const old = api.innotrikAuthoredPromptPlayAndWait(new Uint8Array([1]));
const staleFinish = players.at(-1).onended;
const next = api.innotrikAuthoredPromptPlayAndWait(new Uint8Array([1]));
assert.equal(await old, 'cancelled');
staleFinish();
assert.equal(players.at(-1).paused, undefined);
players.at(-1).onended();
await next;
autoplayFailure = true;
await assert.rejects(api.innotrikAuthoredPromptPlayAndWait(new Uint8Array([1])), /autoplay denied/u);
assert.equal(revoked.length, 5);
console.log('PASS: completion, stop, stale callbacks, autoplay errors; all Blob URLs released.');

"""Offline audio DSP experiment; no uploads, hardware access or app changes.
Requires Python + numpy, ffmpeg and Dart. Run --help for paths.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import wave

import numpy as np

RATE = 16000
ROOT = Path(__file__).resolve().parents[2]
FILTERS = {
    'spectral': 'afftdn=nr=8:nf=-40:tn=1:gs=6',
    'spectral_moderate': 'afftdn=nr=12:nf=-30:tn=1:gs=6',
    'highpass_spectral': 'highpass=f=80,afftdn=nr=8:nf=-40:tn=1:gs=6',
}


def command(args, data=None, cwd=None):
    return subprocess.run(args, input=data, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=True, cwd=cwd).stdout


def pcm(x):
    return np.rint(np.clip(x, -1, 32767 / 32768) * 32768).astype('<i2').tobytes()


def read(path):
    return np.frombuffer(Path(path).read_bytes(), dtype='<i2').astype(float) / 32768


def decode(path, ffmpeg):
    data = command([ffmpeg, '-v', 'error', '-i', str(path), '-ac', '1',
                    '-ar', str(RATE), '-f', 's16le', '-'])
    return np.frombuffer(data, dtype='<i2').astype(float) / 32768


def rms(x):
    return np.sqrt(np.mean(x * x) + 1e-20)


def score(reference, output, mask=None):
    if mask is not None:
        reference, output = reference[mask], output[mask]
    reference = reference - reference.mean()
    output = output - output.mean()
    gain = np.dot(reference, output) / max(np.dot(reference, reference), 1e-20)
    target = gain * reference
    return float(10 * np.log10((np.dot(target, target) + 1e-20) /
                               (np.sum((output - target) ** 2) + 1e-20)))


def align(x, lag, length):
    if lag >= 0:
        x = x[lag:]
    else:
        x = np.pad(x, (-lag, 0))
    return np.pad(x, (0, max(0, length - len(x))))[:length]


def latency(clean, filtered):
    # One fixed alignment per clip/method, measured on its CLEAN control.
    nfft = 1 << (len(clean) + len(filtered) - 1).bit_length()
    corr = np.fft.irfft(np.fft.rfft(filtered, nfft) *
                        np.conj(np.fft.rfft(clean, nfft)), nfft)
    lags = np.arange(-1600, 1601)
    return int(lags[np.argmax(corr[lags % nfft])])


def wav(path, x):
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm(x))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--dart', default=shutil.which('dart'))
    parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    parser.add_argument('--rnnoise-model', type=Path,
                        help='Optional FFmpeg-compatible .rnnn file; never downloaded by this script')
    args = parser.parse_args()
    assert args.dart and args.ffmpeg, 'Dart and ffmpeg are required'
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    filters = dict(FILTERS)
    if args.rnnoise_model:
        shutil.copyfile(args.rnnoise_model, out / 'rnnoise.rnnn')
        for name, mix in [('rnnoise_blend', .6), ('rnnoise_full', 1)]:
            filters[name] = f'aresample=48000,arnndn=m=rnnoise.rnnn:mix={mix},aresample=16000'
    work = out / 'pcm'
    work.mkdir(exist_ok=True)
    rng = np.random.default_rng(20261023)
    # Fixed, auditable sample set; assets are authored voices, not child captures.
    sources = []
    for language in ('en', 'vi'):
        matches = sorted((ROOT / 'assets/audio/listening-6-7').glob(
            f'listening.sentence.C67-L1-*.{language}.mp3'))
        assert len(matches) >= 4
        sources.extend(matches[i] for i in np.linspace(0, len(matches)-1, 4, dtype=int))
    decoded = [decode(p, args.ffmpeg) for p in sources]
    records, jobs, timing, provenance = [], [], [], []
    for index, (source, speech) in enumerate(zip(sources, decoded)):
        active = np.abs(speech) > max(np.max(np.abs(speech)) * .02, 1e-5)
        speech = speech * (10 ** (-23 / 20) / rms(speech[active]))
        # Half have no added lead-in, half 600 ms; original asset pauses remain.
        lead = 0 if index % 2 else 9600
        clean = np.pad(speech, (lead, 9600))
        blocks = np.pad(clean, (0, (-len(clean)) % 320)).reshape(-1, 320)
        powers = np.mean(blocks ** 2, axis=1)
        mask = np.repeat(powers > powers.max() * .01, 320)[:len(clean)]
        n = len(clean)
        t = np.arange(n) / RATE
        white = rng.normal(size=n)
        spectrum = np.fft.rfft(rng.normal(size=n))
        freqs = np.fft.rfftfreq(n, 1 / RATE)
        rumble = np.fft.irfft(spectrum / (1 + (freqs / 180) ** 2), n)
        fan = rumble + .6 * np.sin(2*np.pi*60*t) + .2*np.sin(2*np.pi*120*t)
        rustle = rumble * (.1 + (np.sin(2*np.pi*1.7*t) > .6) * 2) + .12*white
        other = np.resize(decoded[(index + 3) % len(decoded)], n)
        noises = {'hiss': white, 'fan': fan, 'rustle': rustle, 'other_voice': other}
        provenance.append({'id': index, 'asset': str(source.relative_to(ROOT)),
                           'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                           'lead_ms': lead / 16, 'duration_s': n/RATE})
        variants = [('clean', None, clean)]
        for name, noise in noises.items():
            for snr in (5, 10, 20):
                noise = noise / rms(noise[mask])
                mixture = clean + noise * rms(clean[mask]) / 10 ** (snr/20)
                assert np.max(np.abs(mixture)) < .99, 'Mixture must not clip'
                variants.append((name, snr, mixture))
        for noise, snr, mixture in variants:
            stem = f'{index:02d}-{noise}-{snr}'
            input_path = work / f'{stem}.raw'
            input_path.write_bytes(pcm(mixture))
            paths = {}
            for method in ('current_normalizer', 'existing_frontend', *filters):
                output = work / f'{stem}-{method}.raw'
                paths[method] = output
                src = input_path
                if method in filters:
                    src = work / f'{stem}-{method}-filtered.raw'
                    start = time.perf_counter()
                    filtered = command([args.ffmpeg, '-v', 'error', '-f', 's16le',
                        '-ar', str(RATE), '-ac', '1', '-i', str(input_path),
                        '-af', filters[method], '-f', 's16le', '-'], cwd=out)
                    timing.append(time.perf_counter() - start)
                    src.write_bytes(filtered)
                jobs.append({'input': str(src), 'output': str(output),
                             'preprocess': method == 'existing_frontend'})
            records.append({'clip': index, 'noise': noise, 'snr': snr,
                            'clean': clean, 'mask': mask, 'input': input_path,
                            'paths': paths})
    manifest = out / 'jobs.json'
    manifest.write_text(json.dumps(jobs))
    command([args.dart, str(Path(__file__).with_name('process_baselines.dart')), str(manifest)])
    rows, delays, controls, previews = [], {}, [], {}
    for record in records:
        if record['noise'] != 'clean':
            continue
        for method, path in record['paths'].items():
            output = read(path)
            lag = latency(record['clean'], output)
            delays[record['clip'], method] = lag
            output = align(output, lag, len(record['clean']))
            controls.append({'clip': record['clip'], 'method': method,
                'lag_samples': lag, 'si_sdr_db': score(record['clean'], output, record['mask'])})
    for rec in records:
        if rec['noise'] == 'clean':
            continue
        clean, mask = rec['clean'], rec['mask']
        mixture = read(rec['input'])
        base = score(clean, mixture, mask)
        for method, path in rec['paths'].items():
            raw = read(path)
            output = align(raw, delays[rec['clip'], method], len(clean))
            gain = np.dot(clean[mask], output[mask]) / np.dot(clean[mask], clean[mask])
            # Known silence; exclude final 100 ms to avoid alignment padding.
            pause_reduction = 20*np.log10(rms(mixture[-6400:-1600]) /
                                          rms(output[-6400:-1600] / max(abs(gain), 1e-8)))
            value = score(clean, output, mask)
            rows.append({'clip': rec['clip'], 'noise': rec['noise'], 'snr_db': rec['snr'],
                'method': method, 'input_si_sdr_db': base, 'output_si_sdr_db': value,
                'improvement_db': value-base, 'pause_reduction_db': float(pause_reduction),
                'clipped_samples': int(np.sum(np.abs(raw) >= .999)),
                'length_delta_samples': len(raw)-len(clean)})
            if rec['clip'] in (0, 2, 4, 6) and rec['noise'] == 'fan' and rec['snr'] == 10:
                # Same projection gain as the reference for a fair listening comparison.
                preview = out / 'preview' / f"clip-{rec['clip']}"
                preview.mkdir(parents=True, exist_ok=True)
                wav(preview / '01-clean.wav', clean)
                wav(preview / '02-noisy.wav', mixture)
                wav(preview / f'03-{method}.wav', output / max(abs(gain), 1e-8))
                previews[rec['clip'], 'clean'] = clean
                previews[rec['clip'], 'noisy'] = mixture
                previews[rec['clip'], method] = output / max(abs(gain), 1e-8)
    for method in ('clean', 'noisy', 'current_normalizer', *filters):
        clips = [np.concatenate([previews[i, method], np.zeros(4800)]) for i in (0, 2, 4, 6)]
        wav(out / 'preview' / f'comparison-{method}.wav', np.concatenate(clips))
    with (out/'metrics.csv').open('w') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = {'seed': 20261023, 'sources': provenance, 'filters': filters,
               'ffmpeg_version': command([args.ffmpeg, '-version']).decode().splitlines()[0],
               'mixtures': len(records)-len(sources), 'measurements': len(rows),
               'clean_controls': controls, 'ffmpeg_seconds_median': float(np.median(timing)),
               'groups': []}
    if args.rnnoise_model:
        summary['rnnoise_model_sha256'] = hashlib.sha256(args.rnnoise_model.read_bytes()).hexdigest()
    baseline = {(r['clip'], r['noise'], r['snr_db']): r['output_si_sdr_db']
                for r in rows if r['method'] == 'current_normalizer'}
    for noise in ('hiss', 'fan', 'rustle', 'other_voice'):
        for method in ('current_normalizer', 'existing_frontend', *filters):
            group = [r for r in rows if r['noise']==noise and r['method']==method]
            values = [r['improvement_db'] for r in group]
            paired = [r['output_si_sdr_db'] - baseline[r['clip'], r['noise'], r['snr_db']]
                      for r in group]
            summary['groups'].append({'noise':noise,'method':method,
                'median_improvement_db': float(np.median(values)),
                'worst_improvement_db': min(values),
                'regressions_over_1db': sum(v < -1 for v in values),
                'median_improvement_vs_current_db': float(np.median(paired)),
                'worst_improvement_vs_current_db': min(paired),
                'regressions_vs_current_over_1db': sum(v < -1 for v in paired),
                'median_pause_reduction_db': float(np.median([r['pause_reduction_db'] for r in group]))})
    summary['clipped_samples'] = sum(r['clipped_samples'] for r in rows)
    summary['length_delta_range'] = [min(r['length_delta_samples'] for r in rows),
                                    max(r['length_delta_samples'] for r in rows)]
    (out/'results.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps({k:v for k,v in summary.items() if k not in ('sources','clean_controls')}, indent=2))


if __name__ == '__main__':
    main()

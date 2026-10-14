import json
import os
import sys
sys.stdout.reconfigure(encoding='utf-8')
import subprocess
from pathlib import Path
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
import numpy as np
import torch
import transformers.utils.import_utils as import_utils
# We decode with ffmpeg; optional torchaudio DLLs are not needed here.
import_utils.is_torchaudio_available = lambda: False
import transformers.utils as transformer_utils
transformer_utils.is_torchaudio_available = lambda: False
from transformers import WhisperProcessor, WhisperForConditionalGeneration

torch.set_num_threads(4)
name = 'openai/whisper-small'
processor = WhisperProcessor.from_pretrained(name, local_files_only=True)
model = WhisperForConditionalGeneration.from_pretrained(name, local_files_only=True)
files = [
 'ban-da-hoan-thanh-khoa-hoc-roi-ban-muon-hoc-lai-chu-de-so-may.mp3',
 'ban-chon-chu-de-tu-so-1-den-so-10-nhe.mp3',
 'co-10-chu-de-ban-muon-chon-chu-de-so-may.mp3',
]
rows = []
for file in files:
    path = Path('C:/Users/DELL/Downloads') / file
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '1', '-ar', '16000', '-'], capture_output=True, check=True).stdout
    features = processor(np.frombuffer(raw, dtype=np.float32), sampling_rate=16000, return_tensors='pt')
    with torch.inference_mode():
        ids = model.generate(features.input_features, language='vi', task='transcribe', max_new_tokens=128)
    text = processor.batch_decode(ids, skip_special_tokens=True)[0]
    rows.append({'file': file, 'transcript': text})
    print(json.dumps(rows[-1], ensure_ascii=False), flush=True)
Path(__file__).with_name('transcripts.json').write_text(json.dumps(rows, indent=2, ensure_ascii=False), encoding='utf-8')

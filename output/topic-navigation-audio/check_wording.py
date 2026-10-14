import os
import sys
import json
import subprocess
from pathlib import Path
sys.stdout.reconfigure(encoding='utf-8')
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
import numpy as np
import torch
import transformers.utils.import_utils as imports
import transformers.utils as utils
imports.is_torchaudio_available = lambda: False
utils.is_torchaudio_available = lambda: False
from transformers import AutoProcessor, AutoModelForCTC
torch.set_num_threads(4)
name = 'nguyenvulebinh/wav2vec2-base-vietnamese-250h'
processor = AutoProcessor.from_pretrained(name, local_files_only=True)
model = AutoModelForCTC.from_pretrained(name, local_files_only=True)
path = Path('C:/Users/DELL/Downloads/co-10-chu-de-ban-muon-chon-chu-de-so-may.mp3')
raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '1', '-ar', '16000', '-'])
inputs = processor(np.frombuffer(raw, dtype=np.float32), sampling_rate=16000, return_tensors='pt')
with torch.inference_mode():
    logits = model(**inputs).logits
transcript = processor.batch_decode(torch.argmax(logits, dim=-1))[0]
result = {'file': path.name, 'transcript': transcript}
Path(__file__).with_name('wording-check.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))

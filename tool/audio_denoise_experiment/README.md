# Thử nghiệm khử nhiễu bản thu local

Tool thí nghiệm độc lập, không được import vào runtime app. Không dùng điện thoại/HOMI, không upload audio, không tự tải model. Mục tiêu là so sánh trước khi quyết định tích hợp bộ lọc vào app.

## Chạy

Cần Python 3 + NumPy (lượt đo dùng 3.12 / NumPy 2.3.5), Flutter/Dart SDK của dự án và FFmpeg có `afftdn`, `arnndn` (lượt đo dùng FFmpeg 9.0.2).

```sh
python3 tool/audio_denoise_experiment/run.py \
  --dart /path/to/flutter/bin/dart \
  --rnnoise-model /path/to/std.rnnn \
  --output /path/to/experiment-output
python3 -m unittest discover -s tool/audio_denoise_experiment -p 'test_*.py' -v
dart analyze tool/audio_denoise_experiment/process_baselines.dart
flutter test --no-pub test/core_audio_pcm_speech_preprocessor_test.dart test/features/listening/lesson_wav_normalizer_test.dart
```

Bỏ `--rnnoise-model` để chỉ thử các bộ lọc phổ. Model đã dùng: `std.rnnn`, bản RNNoise gốc được chuyển cho FFmpeg, từ [richardpl/arnndn-models](https://github.com/richardpl/arnndn-models/blob/0fda24c46d78f0207d820bb970fbe85c1971b39c/std.rnnn). SHA-256: `6b8943dc4a9b6b24425873992a44f29c0577503276456af46a8854774faeb294`. Đây không phải xác nhận về chất lượng model RNNoise mới nhất. Không thêm model hoặc FFmpeg vào app/dependency mobile.

## Phương pháp

- 8 clip authored từ assets (4 EN, 4 VI), 4 kiểu nhiễu và 3 mức SNR 5/10/20 dB: 96 hỗn hợp. Có clip thêm 600 ms trước câu và clip không thêm; giữ khoảng nghỉ vốn có trong asset. Seed 20261023.
- Nhiễu tổng hợp: xì trắng, ù/quạt (low-pass + 60/120 Hz), rustle thay đổi theo thời gian; tiếng nói chồng lấy từ clip khác làm đối chứng khó. Không coi các tín hiệu này là bản ghi môi trường thực tế.
- Baseline 1 gọi **normalizer Dart hiện có**. Baseline 2 thử **PcmSpeechPreprocessor hiện có + normalizer**; baseline 2 thuộc nhánh thu khác, không khẳng định toàn bộ app đang dùng nó.
- Ba cấu hình FFmpeg: spectral nhẹ, spectral vừa, high-pass 80 Hz + spectral. Hai cấu hình RNNoise: mix 0.6 và 1.0. Mỗi candidate đều qua normalizer giống baseline.
- Không trim khoảng im lặng ở baseline để giữ timeline đo. Không mô phỏng hiệu ứng NS/AEC của điện thoại/firmware HOMI; thử nghiệm bắt đầu từ PCM16 mono 16 kHz.
- RNNoise dùng resample 16→48→16 kHz, không tạo lại dải âm đã mất của Bluetooth. Không tự động đưa bản lọc vào ASR.

## Đọc kết quả

`results.json` ghi nguồn/hash, config, model hash, phiên bản FFmpeg, latency của control sạch và tổng hợp. `metrics.csv` chứa từng phép đo. `jobs.json` ghi lệnh gọi baseline, `pcm/` chứa dữ liệu tái lập. `preview/comparison-*.wav` là 4 câu EN/VI nối lại, cùng thứ tự ở mỗi file.

SI-SDR đo độ giống reference trong vùng có tiếng nói, loại ảnh hưởng gain cố định. Căn chỉnh độ trễ cố định theo control sạch cho từng clip/bộ lọc; không tìm latency tối ưu từ mỗi hỗn hợp nhiễu. Mask vùng nói lấy từ reference chỉ để đánh giá, **không đưa reference/mask vào bộ lọc**. Giảm âm lượng toàn bộ hoặc chỉ làm im khoảng nghỉ không được tính là cải thiện SI-SDR vùng nói. Unit tests kiểm tra các tính chất này.

`median_improvement_vs_current_db` so sánh từng mẫu với normalizer hiện có. Các field `improvement_db`/`median_improvement_db` so với hỗn hợp chưa xử lý. Không trộn hai mốc. `pause_reduction_db` đo giảm nền ở khoảng im lặng, đã bù gain giọng nói, loại vùng padding căn chỉnh ở cuối; không phải mức khử nhiễu trong lúc nói.

SI-SDR nhạy với thay đổi pha/EQ; không thay thế nghe đánh giá, intelligibility hoặc ASR accuracy. Không dùng điểm thấp của high-pass để khẳng định người nghe thấy kém hơn. Thời gian FFmpeg trên Mac có overhead khởi động process, không phải benchmark tốc độ/pin Android/iOS. RNNoise có padding block ở đầu ra; bản preview căn chỉnh/cắt theo chiều dài reference để so sánh, chưa phải implementation trim cho mobile.

## Kết quả lượt 23/10/2026

Xem `../../../docs/session-artifacts/2026-10-23-audio-denoise/summary.md` và các audio/log cùng thư mục. Chưa tích hợp vào runtime: cần đánh giá thêm bằng câu trẻ nói thật và đo độ chính xác nhận dạng trước khi dùng lọc cho chấm bài. Có thể thu mẫu giọng nói bằng mic máy tính để mở rộng benchmark, không bắt buộc có HOMI; Bluetooth/firmware vẫn cần kiểm tra riêng nếu triển khai capture realtime sau này.

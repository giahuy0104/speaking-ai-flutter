# Bản cập nhật 4 topic Alphabet / Numbers — content 4.2

Nguồn: `AIV0_HOMI_PATCH_Thay_doi_4_Topic_Alphabet_Numbers_gui_IT (1).docx`.
Lựa chọn của người dùng: tái sử dụng audio hiện có, **giữ và chuyển tiến độ**;
không áp dụng đề xuất reset dữ liệu test trong tài liệu.

## Phạm vi

| Nhóm tuổi / topic | Các bài sau cập nhật |
| --- | --- |
| 3–5 / Alphabet | A to E Letters; F to J Letters |
| 3–5 / Numbers | One to Five; Six to Ten; Count With Me |
| 6–7 / ABC Words | K to O Letters; P to T Letters; U to Z Letters |
| 6–7 / Numbers Around Me | Numbers 11-15; Numbers 16-20; Numbers in Life |

Giữ 5 nhóm tuổi, 15 level, 50 topic và 109 bài. Nội dung active còn 565 Core
và 565 Challenge. 46 topic / 98 bài ngoài phạm vi được kiểm tra SHA-256 không đổi.
Sáu Core trong U–Z; các bài còn lại trong phạm vi có năm Core.

## Audio và định danh

- Giữ nguyên target ID, Challenge ID và URL audio EN/VI theo nội dung, dù prefix
  ID còn chỉ bài/nhóm tuổi cũ. Không suy ra chủ sở hữu từ prefix target ID.
- Count With Me chuyển từ `c35-l1-t02-b02` sang `c35-l1-t02-b03`; vẫn dùng
  `C35-L1-T02-B02_SONG` và URL bài hát gốc. Bốn bài hát khác không đổi.
- Không tạo, tải lên hoặc xóa audio. Chín tên bài mới chưa có bản thu riêng;
  dùng fallback TTS hiện có (phần tên tiếng Anh dùng giọng tiếng Anh).
- Không đổi pipeline, gain, cue ting hoặc logic đánh giá Core/Challenge.

## Chuyển dữ liệu trên thiết bị

`assets/data/listening_topic_patch_v42.json` lưu snapshot bốn topic cũ/mới,
56 vị trí target được giữ/chuyển, 36 target deprecated và hash dữ liệu ngoài phạm vi.
Mỗi store chuyển dữ liệu trước khi sử dụng; chạy lại không chuyển hai lần.

- Progress chuyển theo target, không copy vị trí câu/số bài. Snapshot gốc nằm dưới
  `__topic-patch-v41::`; marker `__listening-topic-patch-v42` ngăn chuyển lại.
- Giữ trạng thái từng Core, sao và quyền truy cập đã mở. Quyền truy cập cũ không
  đồng nghĩa đã hoàn thành Core mới. Nhóm 6–7 không phụ thuộc hoàn thành nhóm 3–5.
- Reset con trỏ/rotation Challenge chỉ với bài thay đổi; trạng thái Challenge
  của Count With Me và Numbers in Life giữ nguyên.
- Next bảo vệ một lượt học đã chuyển thay vì reset ngay; chọn Học lại rõ ràng
  vẫn dùng hành vi reset hiện tại. Bằng chứng Core đã xử lý trong dữ liệu legacy
  không có đánh giá chi tiết được giữ riêng, không tự nâng thành đạt/ngôi sao.
- Vocabulary giữ entry ID, thời điểm nhận sao, audio path và liên kết phiên học;
  source lesson/star slot cập nhật theo vị trí mới. Parent/Today không đổi.
- Target deprecated vẫn giữ sao/ghi âm lịch sử dưới nguồn `LEGACY-V41`, nhưng
  không vào Review mới hoặc phiên Review đang dở.
- History chuyển metadata, không đổi đường dẫn hoặc xóa bản ghi vật lý.
- Điểm Resume cũ được backup. Nếu target bị bỏ hoặc chuyển sang nhóm tuổi khác,
  không tự mở nội dung sai/đổi tuổi; người dùng chọn lại bài trong nhóm hiện tại.
- Không hạ phiên bản app trên dữ liệu đã chuyển nếu chưa sao lưu các store.
  Snapshot phục vụ đối chiếu/khôi phục có kiểm soát, không phải tự động rollback.

## Tái tạo và kiểm thử

Chạy `node tool/patch_listening_topics_v42.mjs` để áp lại patch metadata.
Script kiểm tra nguồn và tính bất biến, chạy lại cho kết quả giống nhau.
Nếu dùng các generator curriculum cũ, phải áp patch này sau đó; không phát hành
catalog cũ cùng marker migration 4.2.

Các test bao phủ nội dung/manifest không đổi ngoài phạm vi, remap Core/Challenge,
Count With Me/Song Resume, sao/bản ghi/Review, cursor khi tách bài, Next/Học lại,
quyền mở khóa, checkpoint đồng thời và UI/golden theo số bài/câu mới.

Kết quả kiểm tra trong workspace: **664 test pass** cho listening, vocabulary,
home, voice navigation và curriculum audio; `flutter analyze` các phần này
không có lỗi/cảnh báo. Log: `output/topic-patch-regression-final.log` và
`output/topic-patch-analysis.log`. Chưa build/cài APK hoặc xác nhận trên điện thoại
cho riêng bản patch nội dung này.

Trước phát hành cần test trên điện thoại đã có tiến độ 4.1: nâng cấp không xóa
dữ liệu; kiểm tra Resume, sao/bản ghi, Count With Me bài 3 và TTS chín tên bài mới
(cả offline khi thiết bị đã có giọng TTS). Không dùng cài đặt sạch để thay thế
bài test migration này.

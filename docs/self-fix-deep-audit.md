# Bao cao ra soat sau phien ban tu sua

Ngay ra soat: 2026-09-24

Nhanh goc: `audio-24th9`

Nhanh ra soat: `self-fix-audio-vocabulary`

## 1. Ket luan

Da doi chieu lai:

- Toan bo prompt trong `phienbantusua.md`.
- Ban va lifecycle ghi am lesson `bbd37967`.
- Ban va disconnect/reconnect HFP `614dda18`.
- Ma nguon, test va cac commit da dua vao nhanh tu sua.

Ban sua ban dau dung huong. Hai dot ra soat sau da tim them cac race khi dispose,
trang thai Review mo lai qua som, file ghi am tam khong duoc don, auto-follow
gianh lai scroll cua nguoi dung va hai khoang ho kiem thu. Cac diem nay da duoc
sua tai nguon hoac khoa bang test rieng. Khong dung delay tuy y, khong them co
global, khong thay secret va khong publish.

Muc 1 da duoc gop vao muc 8. Muc 8 va 9 van la goi state-machine MAIN/Challenge
cho senior Flutter/Dart, khong nam trong nhanh tu sua nay va chua duoc danh dau
hoan thanh.

## 2. Khoang ho tim thay trong dot ra soat sau

### 2.1 HFP revalidation co the song sot qua disconnect

Trang thai truoc khi sua:

- `_acquire()` da kiem tra `_connectionGeneration` quanh native start.
- Nhung `_revalidate()` chua kiem tra generation nay.
- Mot scope dang giu lease co the bat dau revalidate, scope khac disconnect,
  sau do revalidate cu van tra thanh cong.
- Khi revalidate that bai, scoped caller co the con giu token ownership cu.

Sua dut diem:

- Kiem tra connection generation truoc va sau native revalidation.
- Neu revalidation bi vo hieu hoa hoac that bai, release va xoa dung token cua
  scoped caller.
- Them regression test cho revalidate dang cho, disconnect tu scope khac,
  reconnect va start moi.

Commit: `3e4fcd08 fix: cancel stale HFP route revalidation`

### 2.2 Fireworks Review khong dung khi MAIN gianh quyen

Trang thai truoc khi sua:

- Timer va animation duoc don khi dispose.
- Nhung `pauseForMainAssistant` chua huy overlay, nen phao hoa co the con chay
  sau khi MAIN da takeover.

Sua dut diem:

- Gom cleanup timer/animation vao mot helper dung chung.
- Goi cleanup khi dispose va khi MAIN pause.
- Reset cac trang thai preparing/processing khi pause.
- Them test dung trong luc fireworks dang hien.

Commit: `945b5a46 fix: stop review celebration on MAIN`

### 2.3 Vocabulary auto-follow giu highlight cu khi cho lua chon

Trang thai truoc khi sua:

- Entry cuoi cung van duoc highlight sau khi audio da ket thuc.
- Highlight co the ton tai vo thoi han neu luong dang cho voice choice.

Sua dut diem:

- Xoa active entry ngay sau khi ket thuc queue item, truoc khi hoi lua chon.
- Generation hien co van chan callback cuon muon.
- Them test giu choice prompt pending va xac nhan highlight da bien mat.

Commit: `37a5acbe fix: clear completed vocabulary playback highlight`

### 2.4 Nut Bai hat V4 co the vuot khoa lesson lien tiep

Trang thai truoc khi sua:

- Nut Bai hat da ton trong khoa Level.
- Nhung no chua ton trong khoa lesson theo thu tu, nen co the mo mot song
  milestone chua du dieu kien.

Sua dut diem:

- Dung cung `ListeningCurriculumFlow.lessonUnlocked` nhu danh sach lesson.
- Song legacy van giu contract cu.
- Them test V4 song bi khoa va cap nhat test direct-open voi progress hop le.

Commit: `72931b64 fix: respect V4 song lesson locks`

### 2.5 Test Previous/Next chua chung minh thu tu day du

Ma product hien tai da dung. Test cu chi kiem tra mot phan audio key va so lan
mo mic, chua chung minh mic mo sau cue.

Da bo sung event-order assertion chinh xac:

```text
boundary lead -> English -> Vietnamese -> repeat cue -> record
```

Khong sua product code.

Commit: `17b9d761 test: assert boundary replay audio order`

### 2.6 Coordinator dispose co the de pending HFP start bao thanh cong

Trang thai truoc khi sua:

- `dispose()` chi dat `_disposed` khi operation cua no den luot trong queue.
- Native start dang cho co the hoan tat truoc operation dispose va tra thanh
  cong cho caller trong luc coordinator toan cuc da duoc yeu cau huy.

Sua dut diem:

- Tang connection generation ngay khi dispose duoc yeu cau.
- Pending acquire/revalidate khong the tao ownership sau moc nay.
- Them regression test dispose coordinator trong luc native start dang cho.

Commit: `51486ea5 fix: cancel HFP starts during coordinator disposal`

### 2.7 Review mo lai nut ghi am trong luc feedback con dang phat

Trang thai truoc khi sua:

- Cac ket qua unclear/no-response/retry ha `_busy` truoc khi feedback xong.
- UI hien idle va co the bat dau them mot capture chong len feedback.

Sua dut diem:

- Giu processing/busy den khi feedback ket thuc va retry capture moi bat dau.
- Reset processing khi stop/evaluation loi.
- Test chan feedback, xac nhan nut disabled va khong co recorder thu hai.

Commit: `3cce6445 fix: keep Review recording locked during feedback`

### 2.8 Challenge de lai file ghi am tam

Challenge co `saveToHistory: false`, nhung file Android va raw/normalized iOS
khong co owner don sau khi playback va scoring ket thuc.

Sua dut diem:

- Theo doi ownership tung attempt.
- Chi xoa sau khi playback va scoring deu da dung xong file.
- Don ca raw va normalized iOS; normalization loi thi phat file goc truoc roi
  moi xoa.
- Cleanup la best-effort, khong che ket qua hoc neu filesystem loi.
- Don ca stale start, MAIN va dispose.

Commit: `b8244837 fix: clean up transient Challenge recordings`

### 2.9 Review de lai ban ghi sai va co nguy co xoa file retry dang ghi

Ban ghi dung duoc giu de lam audio Ngoi sao. Ban ghi sai/khong ro khong duoc
tham chieu nhung truoc day khong bi xoa. Vi cac retry co the dung lai cung path,
xoa o cuoi feedback se co nguy co xoa file ma retry moi dang ghi.

Sua dut diem:

- Xoa ban ghi khong duoc giu truoc khi khoi dong retry moi.
- Giu ban ghi dung sau khi path da vao session.
- Don capture iOS tra ve muon cua stop cu ma khong cham Apple Speech turn moi.
- Test Android/iOS, stale stop va thu tu `delete old -> start retry`.

Commit: `ccdaaa34 fix: discard failed Review recordings`

### 2.10 Auto-follow gianh lai scroll ngay khi nguoi dung tha tay

Trang thai truoc khi sua:

- ScrollStart do keo tay dung auto-follow dung cach.
- ScrollEnd lai lap tuc schedule entry hien tai, keo nguoi dung tro ve vi tri cu.

Sua dut diem:

- Khi ket thuc drag chi nhan lai quyen auto-follow.
- Khong cuon lai entry cu; lan chuyen entry audio tiep theo van schedule nhu cu.
- Test viewport nho va giu nguyen scroll offset sau khi tha tay.

Commit: `3a98339f fix: preserve user scroll during vocabulary playback`

### 2.11 Bai hat thieu test cho progress va duong Back

Product code da dung: song V4 dung lesson ID hien co, khong tao model thu hai va
khong ghi progress khi chi mo route. Da bo sung test xac nhan khong tu complete
va Back di dung chuoi song/lesson -> danh sach bai -> man chon Chu de.

Commit: `337c04cc test: verify topic song return path`

## 3. Danh gia tung prompt tu sua

| Muc | Ket qua ra soat | Trang thai |
| --- | --- | --- |
| 1 | La mot phan cua contract resume o muc 8, khong duoc sua rieng. | Ngoai pham vi |
| 2 | Fireworks dung shared widget/thoi luong; da bo sung cleanup khi MAIN takeover. | Dat sau `2041ef38`, `945b5a46` |
| 3 | Text dung co che tap-to-start/tap-to-stop; processing khoa het feedback; file attempt sai duoc don truoc retry. | Dat sau `b5b2dcac`, `3cce6445`, `ccdaaa34` |
| 4 | Challenge iOS dung finalize/normalize cua lesson, fallback path cu, khong ghi history; file tam duoc don sau moi consumer. | Dat o Dart sau `227cc777`, `b8244837`; con test native/device |
| 5 | Luong product da dung; test bay gio chung minh day du thu tu va mic. | Dat sau `17b9d761` |
| 6 | Dung stable entry ID, key theo journey, viewport/generation guard; khong gianh lai scroll sau drag va da xoa stale highlight. | Dat sau `5cb2c295`, `37a5acbe`, `3a98339f` |
| 7 | Tai su dung dung song/lesson ID, khong tao model/progress thu hai; ton trong Level/sequential lock va co test Back. | Dat sau `ccbc67a3`, `72931b64`, `337c04cc` |
| 8 | Resume/replay/MAIN theo module la state-machine chung, can senior Flutter/Dart. | Chua lam co chu dich |
| 9 | Challenge lifecycle, typed result, idempotent progress va owner context. | Chua lam co chu dich |

Luu y cho muc 6: Review practice la man rieng. Khi dang lam bai ghi am Review,
danh sach o Vocabulary Home khong con hien de cuon. Auto-follow ap dung cho luc
collection tren Vocabulary Home dang phat, dung voi kien truc hien tai.

## 4. Danh gia hai commit audio

### 4.1 Lifecycle ghi am lesson

Da xac nhan cac invariant sau trong ma va test:

- Start/stop/cancel/dispose deu vo hieu hoa pending start bang generation.
- Generation duoc kiem tra sau cac await quan trong.
- Route HFP duoc xac nhan lai o bien playback-to-capture.
- Route duoc kiem tra lai sau `recorder.start`.
- Late start bi cancel va file khong duoc bao la capture hop le.
- Route-loss cua capture cu khong huy capture moi.
- Fallback built-in mic chi xay ra theo nhanh co kiem soat.

Khong tim thay them ban va tam thoi trong pham vi Dart nay.

### 4.2 Disconnect/reconnect va handoff HFP

Da xac nhan native mutation di qua coordinator queue; disconnect vo hieu hoa
pending acquire tren moi scope; connect cho teardown cu; old release khong dong
route cua owner moi. Khoang ho revalidation va dispose toan coordinator da duoc
sua o `3e4fcd08` va `51486ea5`.

## 5. iOS Challenge normalization

Static audit xac nhan:

- Challenge goi `resolveLessonRecording`, cung pipeline voi lesson.
- iOS native `normalizeLessonRecording` gioi han file 12 giay.
- Muc tieu gated RMS la -21 dB, max gain 28 dB va peak headroom -1 dB.
- Chi file nho moi duoc nang; file du lon khong bi khuech dai them.
- Source chi bi xoa sau khi normalized output duoc ghi thanh cong.
- Normalizer loi thi playback dung file hop le ban dau.
- Transcript on-device va contract khong luu history duoc giu nguyen.
- Raw/normalized Challenge file chi duoc don sau khi playback va scoring xong.

Day khong con la cach tang volume co dinh. Tuy nhien Windows khong the chay
XCTest/AVAudioSession, nen van can macOS va iPhone that de xac nhan am luong,
clipping va route H20.

## 6. Kiem tra da chay

Flutter focused suites:

- Lesson media lifecycle.
- iOS streaming speech input.
- HFP route recovery va coordinator.
- Coordinated voice prompt service.
- Challenge va guided lesson flow.
- Vocabulary Review practice va Vocabulary Home.
- Topic listening va song entry.

Ket qua: 241 test cases da pass trong cac file muc tieu.

Android native:

```text
:app:testDebugUnitTest
HfpRouteReadinessTest
HfpRouteDispatchTest
BUILD SUCCESSFUL
```

Static checks:

```text
flutter analyze --no-pub
No issues found
```

Gradle co canh bao deprecated Kotlin/AGP va mot so Android API. Day la technical
debt san co cho viec nang AGP 10, khong phai loi behavior cua task audio va khong
nen tron vao cac commit sua nay.

## 7. Kiem tra con bat buoc tren thiet bi

1. Android H20: ghi 5 cau lien tiep, nghe feedback va bat dau cau tiep theo.
2. Android va iOS: cancel ngay luc route dang mo; khong co recorder khoi dong muon.
3. Android va iOS: disconnect/reconnect H20 it nhat 5 chu ky, khong roi ve loa/mic dien thoai.
4. iPhone H20: nghe lai Challenge voi file nho va file du lon; khong clipping.
5. macOS/Xcode: chay native XCTest lien quan audio session va normalizer.
6. Muc 8/9: test khoa man hinh, Challenge pop/commit va MAIN owner context sau khi senior hoan thanh.

## 8. Nguyen tac tich hop tiep theo

- Khong giao nhanh nay cho nguoi thue; ho lam nhanh rieng tu `audio-24th9`.
- Chi cherry-pick tung commit muc 8/9 sau khi xem diff va nghiem thu.
- Khong merge mu quang ca nhanh state-machine.
- Khong publish/build release/thay secret trong dot ra soat nay.
- File lock Gradle local hien co khong thuoc task va khong duoc commit.

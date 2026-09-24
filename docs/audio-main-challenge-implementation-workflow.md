# Quy trinh nhanh tu sua va tich hop phan thue ngoai

## 1. Pham vi da chot

Nhanh goc: `audio-24th9`.

Nhanh tu sua: `self-fix-audio-vocabulary`.

Nhanh `audio-24th9` duoc giu nguyen. Nhanh tu sua chi gom:

- Hai ban va audio da co san: lifecycle ghi am va HFP reconnect.
- Cac muc tu sua 2 den 7 trong `phienbantusua.md`.
- Muc 5 chi kiem chung; khong sua product code neu ma hien tai da dung. Co the
  tao commit test-only neu test cu chua xac nhan du thu tu audio va mo mic.

Khong lam tren nhanh nay:

- Muc 1 vi da duoc gop vao contract cua muc 8.
- Muc 8: Dung, MAIN hoi, Resume va Replay theo tung module.
- Muc 9: Challenge den cuoi bai, lifecycle va owner context.

Muc 8 va 9 la mot goi state-machine rieng cho senior Flutter/Dart. Sau khi nguoi
duoc thue sua va chu san pham nghiem thu, chi dua cac commit dat yeu cau ve nhanh
tu sua. Khong giao nhanh `self-fix-audio-vocabulary` cho nguoi duoc thue.

## 2. Cach tao lai nhanh tu dau

```powershell
git switch audio-24th9
git status --short
git switch -c self-fix-audio-vocabulary
```

Khong dung `git add .` hoac `git add -A`. File local sau khong thuoc task va
khong duoc dua vao commit:

```text
third_party/google_mlkit_commons/android/.gradle/9.0-milestone-1/fileHashes/fileHashes.lock
```

## 3. Thu tu commit cua nhanh tu sua

Tinh den luc cap nhat tai lieu nay, nhanh co cac commit sau theo dung thu tu:

```text
9c719c74 fix: stabilize HFP recording lifecycle
4748ef37 fix: serialize HFP disconnect reconnect handoff
b5b2dcac fix: align vocabulary review recording states
2041ef38 feat: celebrate correct vocabulary review answers
227cc777 fix: normalize iOS challenge recording playback
5cb2c295 feat: follow active vocabulary entries
ccbc67a3 feat: open songs from topic journey
da283f55 docs: record self-fix integration workflow
3e4fcd08 fix: cancel stale HFP route revalidation
945b5a46 fix: stop review celebration on MAIN
37a5acbe fix: clear completed vocabulary playback highlight
72931b64 fix: respect V4 song lesson locks
17b9d761 test: assert boundary replay audio order
```

Chi tiet:

1. Cherry-pick ban va lifecycle ghi am `bbd37967`.
2. Cherry-pick ban va HFP reconnect `614dda18`.
3. Dong bo text va state ghi am Vocabulary Review.
4. Them phao hoa khi Review tra loi dung.
5. Tai su dung finalize/normalize cho playback ban ghi Challenge tren iOS.
6. Kiem chung Previous/Next o bien. Khong sua product code; them test-only
   commit `17b9d761` de xac nhan du thu tu lead, EN, VI, cue va mic.
7. Them auto-follow cho Ba me da them, Ngoi sao va Luyen lai.
8. Them nut Bai hat tren card Chu de, dieu huong bang ID toi lesson/song hien co.

Ket qua ra soat sau va rui ro con lai duoc ghi tai
`docs/self-fix-deep-audit.md`.

Moi phan phai co test rieng va commit rieng. Khong squash vi can rollback tung
phan doc lap.

## 4. Kiem tra sau moi phan

```powershell
flutter test --no-pub --concurrency=1 <test-file-cua-phan>
flutter analyze --no-pub <cac-file-da-sua>
git diff --check
git status --short
git add -- <chi-cac-file-cua-phan>
git diff --cached --check
git commit -m "<commit-message>"
```

Neu test that bai thi khong commit va khong chuyen sang phan ke tiep. Khong thay
doi secret, signing, bundle id, cau hinh publish hoac noi dung bai hoc.

## 5. Kiem tra tong nhanh tu sua

Chay cac test muc tieu theo tung file de tranh Dart compiler het heap tren may
Windows:

```powershell
flutter test --no-pub --concurrency=1 test/core_audio_hfp_route_coordinator_test.dart
flutter test --no-pub --concurrency=1 test/features/listening/lesson_media_service_test.dart
flutter test --no-pub --concurrency=1 test/features/vocabulary/vocabulary_practice_screen_test.dart
flutter test --no-pub --concurrency=1 test/features/vocabulary/vocabulary_home_screen_test.dart
flutter test --no-pub --concurrency=1 test/features/listening/topic_listening_screen_test.dart
flutter analyze --no-pub
git diff --check origin/audio-24th9...HEAD
git log --oneline origin/audio-24th9..HEAD
git status --short
```

Test thiet bi van bat buoc cho H20 va iOS. Test tu dong khong thay the duoc viec
kiem tra Bluetooth route, am luong that va lifecycle khi khoa man hinh.

## 6. Quy trinh cho muc 8 va 9 do nguoi thue sua

Nguoi duoc thue lam tren nhanh rieng tao tu cung base `audio-24th9`, khong tao tu
`main` neu `main` khong chua dung base audio:

```powershell
git fetch origin
git switch audio-24th9
git pull --ff-only origin audio-24th9
git switch -c main-challenge-state-fix
```

Yeu cau ho tach commit toi thieu theo cac moc:

```text
test: reproduce MAIN and challenge lifecycle races
fix: commit challenge completion atomically
fix: bind MAIN commands to the active learning owner
fix: normalize MAIN resume and replay contracts
```

Chi nhan commit khi:

- Co regression test cho tung loi.
- Challenge result va progress commit idempotent.
- MAIN command gan voi dung owner generation va context moi nhat.
- Resume va replay duoc tach ro cho Core, Challenge, Review va Song.
- MAIN lan hai, Back va route pop huy callback audio/mic den muon.
- Khong thay native neu chua co bang chung loi nam o native.

## 7. Dua code cua nguoi thue ve nhanh tu sua

Khong merge ca nhanh mot cach mu quang. Lay danh sach commit, xem tung diff va
cherry-pick theo thu tu da duoc nghiem thu:

```powershell
git switch self-fix-audio-vocabulary
git status --short
git fetch origin
git show --stat <commit-sha>
git show <commit-sha>
git cherry-pick <commit-test>
git cherry-pick <commit-challenge>
git cherry-pick <commit-owner>
git cherry-pick <commit-resume-replay>
```

Sau moi cherry-pick, chay test cua commit do. Neu xung dot:

```powershell
git status --short
```

Giai quyet xung dot bang cach giu ca hai nhom thay doi hop le, sau do chay lai
test lien quan va:

```powershell
git add -- <cac-file-da-giai-quyet>
git cherry-pick --continue
```

Neu commit khong dat nghiem thu hoac xung dot lam thay doi contract da thong nhat:

```powershell
git cherry-pick --abort
```

Khong dung `git reset --hard` va khong revert thay doi local khong lien quan.

## 8. Dieu kien merge ve nhanh san pham

Chi merge sau khi:

- Tat ca test muc tieu va `flutter analyze` qua.
- Da test H20 tren Android voi record, disconnect/reconnect va MAIN.
- Da smoke test iOS, dac biet playback ban ghi Challenge.
- Muc 8 va 9 da duoc nghiem thu rieng neu duoc dua vao cung dot phat hanh.
- Working tree chi con cac thay doi local da biet va khong thuoc task.

Truoc khi merge, luu lai SHA hien tai va danh sach commit:

```powershell
git rev-parse HEAD
git log --oneline origin/audio-24th9..HEAD
git status --short
```

Khong publish, khong build release va khong thay doi secret trong quy trinh nay.

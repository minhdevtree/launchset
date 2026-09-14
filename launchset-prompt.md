# Prompt: xây app LaunchSet (mở/đóng nhóm app theo lịch trên macOS)

> **Cách dùng:** mở Claude Code trong `~/Projects/launchset` rồi gõ: `Đọc launchset-prompt.md và làm theo, bắt đầu từ M0.`
> Sửa bảng "Quyết định mặc định" ở mục 2 trước nếu muốn đổi tên app, ngôn ngữ hay phiên bản macOS.
>
> **Gửi agent:** thư mục hiện tại chính là gốc project (`launchset/` ở mục 7.1). Tạo file ngay tại đây, không tạo thư mục con `launchset/`. Giữ nguyên file prompt này.

---

## 1. Vai trò và mục tiêu

Bạn là lập trình viên macOS có kinh nghiệm với Swift, SwiftUI và AppKit. Hãy xây một app **native macOS** tên **LaunchSet**, dùng cá nhân (không lên App Store), làm được 3 việc:

1. Cho người dùng tạo **nhóm app** (ví dụ "Làm việc": Slack, Chrome, VS Code, Notion).
2. **Mở hoặc đóng cả nhóm bằng tay** chỉ với 1 cú click, từ menu bar hoặc cửa sổ chính.
3. **Tự mở hoặc đóng nhóm theo lịch** đã cấu hình (giờ + các ngày trong tuần), có cảnh báo trước khi đóng để không mất dữ liệu chưa lưu.

App có giao diện đầy đủ (menu bar + cửa sổ quản lý + Settings), chạy nền nhẹ, không cần quyền đặc biệt.

---

## 2. Quyết định mặc định (sửa trước khi chạy nếu cần)

| Hạng mục | Giá trị |
|---|---|
| Tên app | LaunchSet |
| Bundle ID | `local.minhdevtree.launchset` |
| macOS tối thiểu | 14.0 (Sonoma) |
| Ngôn ngữ UI | Tiếng Việt, viết thẳng trong code (chưa cần String Catalog) |
| Swift | Swift 6 language mode, strict concurrency |
| UI | SwiftUI; chỉ dùng AppKit ở chỗ SwiftUI không làm được (NSWorkspace, NSOpenPanel, NSRunningApplication) |
| Hình thức | App menu bar (`LSUIElement = true`), có thêm cửa sổ quản lý |
| Phân phối | Build local, ký ad-hoc (`codesign --sign -`), cài vào `~/Applications` |
| App Sandbox | **TẮT** (xem mục 3, lý do bắt buộc) |
| Dependency bên thứ ba | **Không dùng** |
| Lưu dữ liệu | File JSON trong `~/Library/Application Support/LaunchSet/` |

---

## 3. Môi trường build (đã kiểm tra thực tế trên máy, đừng đổi hướng)

Máy hiện tại: macOS 26.6, **chỉ có Command Line Tools (Swift 6.4), CHƯA cài Xcode**. Đã thử và xác nhận:

- ✅ `swift build` với SwiftPM build được app SwiftUI dùng `MenuBarExtra`, `Window`, `Settings`, `ServiceManagement`, `UserNotifications`.
- ✅ Đóng gói thủ công thành `.app` (binary + `Info.plist`) rồi `codesign --force --sign -` thì `open` chạy được bình thường.
- ❌ `swift test` **không chạy được**: Swift Testing báo thiếu plugin `TestingMacros`, còn XCTest không có trong Command Line Tools.
  → Logic được kiểm tra bằng một executable target riêng tên `SelfCheck`, chạy bằng `swift run SelfCheck`, fail thì exit code khác 0.
- ❌ **App Sandbox chặn `NSRunningApplication.terminate()` và `forceTerminate()`**: cả hai luôn trả về `false` khi quit app khác. Vì vậy app phải chạy **không sandbox**. Không dùng AppleScript/Apple Events, không cần quyền Accessibility.
- ⚠️ `UNUserNotificationCenter` và `SMAppService.mainApp` cần một `.app` bundle thật có bundle ID. **Không chạy app bằng `swift run LaunchSet`**; luôn build qua `scripts/build-app.sh` rồi mở `.app`.

Nếu sau này cài Xcode thì vẫn mở được `Package.swift` bằng Xcode, không cần đổi cấu trúc.

---

## 4. Tính năng (phạm vi v1)

### 4.1 Nhóm app
- Tạo, đổi tên, xoá nhóm. Mỗi nhóm có tên và 1 icon SF Symbol (chọn từ khoảng 12 icon có sẵn: `briefcase`, `gamecontroller`, `book`, `hammer`, `paintbrush`, `music.note`, `film`, `message`, `chart.bar`, `house`, `moon`, `square.stack`).
- Thêm app vào nhóm theo 3 cách:
  1. Nút "Thêm app…" mở `NSOpenPanel` tại `/Applications`, chỉ cho chọn `.app`, chọn được nhiều app.
  2. Menu "Thêm từ app đang chạy" liệt kê `NSWorkspace.shared.runningApplications` có `activationPolicy == .regular`.
  3. Kéo thả file `.app` từ Finder vào danh sách.
- App được nhận diện bằng **bundle ID** (đọc qua `Bundle(url:)?.bundleIdentifier`), lưu kèm tên và đường dẫn gần nhất.
- Sắp xếp lại thứ tự app bằng kéo thả (thứ tự này là thứ tự mở).
- Một app có thể nằm trong nhiều nhóm. Trùng app trong cùng một nhóm thì bỏ qua.
- **Chặn không cho thêm** các app sau (hiện thông báo lý do): chính LaunchSet, `com.apple.finder`, `com.apple.dock`, `com.apple.systemuiserver`, `com.apple.loginwindow`, `com.apple.controlcenter`, `com.apple.notificationcenterui`.
- Tuỳ chọn mỗi nhóm:
  - "Chờ giữa mỗi lần mở app": 0–30 giây (mặc định 0).
  - "Ẩn app sau khi mở": bật/tắt (mặc định tắt).
  - "Nếu app không chịu đóng": `Để yên và báo cho tôi` (mặc định) hoặc `Buộc đóng (có thể mất dữ liệu chưa lưu)`.

### 4.2 Mở/đóng thủ công
- Từ menu bar: mỗi nhóm có nút **Mở** và **Đóng**.
- Từ cửa sổ chính: nút **Mở tất cả** và **Đóng tất cả** trong trang chi tiết nhóm.
- Menu chuột phải trên nhóm có thêm "Buộc đóng tất cả…", bấm vào phải hiện hộp thoại xác nhận.
- Kết quả thao tác thủ công hiện ngay tại chỗ (ví dụ dòng nhỏ "Đã mở 3/4 app" trong 3 giây) và ghi vào lịch sử. Không bắn thông báo hệ thống cho thao tác thủ công.

### 4.3 Lịch
- Mỗi lịch gồm: nhóm, hành động (Mở/Đóng), giờ:phút, các ngày trong tuần, bật/tắt.
- Một nhóm có thể có nhiều lịch (ví dụ Mở 08:30 T2–T6, Đóng 18:00 T2–T6).
- Nút nhanh chọn ngày: "Mọi ngày", "T2–T6", "T7–CN".
- Hiển thị "Lần chạy tới" cho từng lịch.
- Cảnh báo xung đột khi 2 lịch cùng nhóm, cùng giờ:phút, trùng ít nhất 1 ngày nhưng khác hành động. Chỉ cảnh báo, không chặn lưu.
- Công tắc toàn cục "Tạm dừng mọi lịch" trên menu bar. Khi bỏ tạm dừng, **không chạy bù** các lịch đã qua trong lúc tạm dừng.

### 4.4 Cảnh báo trước khi đóng
- Với lịch **Đóng**, gửi thông báo trước N phút (Settings: Tắt / 1 / 2 / 5 / 10 phút, mặc định 2).
- Thông báo có 2 action: **"Hoãn 10 phút"** (số phút lấy từ Settings) và **"Bỏ qua lần này"**.
- Trong khoảng thời gian cảnh báo, menu bar hiện một dòng "Sắp đóng "Làm việc" lúc 18:00" kèm 2 nút Hoãn/Bỏ qua. Nhờ vậy vẫn thao tác được khi người dùng tắt thông báo.
- Hoãn nhiều lần được. Trạng thái hoãn/bỏ qua chỉ giữ trong bộ nhớ.
  `// ponytail: mất khi app khởi động lại; lưu xuống đĩa nếu thấy cần`

### 4.5 Lịch sử chạy
- Mỗi lần chạy (thủ công hoặc theo lịch) ghi 1 bản ghi: thời điểm, nhóm, hành động, nguồn (Thủ công/Theo lịch), kết quả từng app.
- Kết quả từng app thuộc một trong các loại: `Đã mở`, `Đã chạy sẵn`, `Không tìm thấy`, `Mở lỗi: <lỗi>`, `Đã đóng`, `Không chạy`, `Chưa đóng (có thể đang chờ lưu file)`, `Đã buộc đóng`.
- Lịch bị bỏ lỡ cũng ghi lại: "Bỏ lỡ lịch 08:00 (máy đang ngủ hoặc LaunchSet chưa chạy)".
- Giữ tối đa 200 bản ghi mới nhất. Có nút "Xoá lịch sử".

### 4.6 Settings (⌘,)
- **Mở cùng macOS**: dùng `SMAppService.mainApp.register()/unregister()`. Trạng thái đọc trực tiếp từ `SMAppService.mainApp.status`, không lưu vào config.
- **Thông báo**: hiện trạng thái quyền, có nút mở System Settings nếu bị từ chối. Tuỳ chọn "Báo cả khi chạy theo lịch thành công" (mặc định tắt; khi có lỗi thì luôn báo).
- **Cảnh báo trước khi đóng**: Tắt / 1 / 2 / 5 / 10 phút.
- **Thời gian hoãn**: 5 / 10 / 15 phút.
- **Chờ app đóng tối đa**: 5 / 15 / 30 / 60 giây (mặc định 15).
- **Chạy bù lịch bị lỡ** nếu trễ không quá: 5 / 15 / 30 / 60 phút (mặc định 15).
- **Xuất cấu hình…** / **Nhập cấu hình…** (file JSON). Nhập sẽ thay toàn bộ cấu hình hiện tại, phải hỏi xác nhận trước.

---

## 5. Hành vi chi tiết và edge case

### 5.1 Mở nhóm
Với từng app theo thứ tự trong nhóm:
1. Nếu app đang chạy (`NSRunningApplication.runningApplications(withBundleIdentifier:)` không rỗng) thì ghi `Đã chạy sẵn` và bỏ qua, không kéo app lên trước.
2. Tìm URL bằng `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`. Không có thì thử `lastKnownPath` nếu file còn tồn tại. Vẫn không có thì ghi `Không tìm thấy` và **tiếp tục các app còn lại**.
3. Mở bằng `NSWorkspace.shared.openApplication(at:configuration:)` (bản async), `configuration.activates = false`, `configuration.hides = group.hideAfterOpen`.
4. Nếu đã cấu hình thì chờ `launchDelaySeconds` trước khi mở app kế tiếp.

### 5.2 Đóng nhóm
1. Lấy mọi instance đang chạy của từng bundle ID. Không có instance nào thì ghi `Không chạy`.
2. Gọi `terminate()` cho tất cả instance cùng lúc (giống ⌘Q; app có thể hiện hộp thoại lưu file).
3. Chờ tối đa `quitTimeoutSeconds`: nghe `NSWorkspace.didTerminateApplicationNotification` và kiểm tra `isTerminated`, không dùng vòng lặp sleep.
4. Hết thời gian mà app vẫn chạy:
   - Nhóm đang để `Để yên và báo cho tôi` thì ghi `Chưa đóng (có thể đang chờ lưu file)`. Nếu là lịch thì gửi thông báo.
   - Nhóm đang để `Buộc đóng` thì gọi `forceTerminate()` và ghi `Đã buộc đóng`.
5. Không bao giờ đóng các app trong danh sách chặn ở 4.1, kể cả khi file config bị sửa tay.

### 5.3 Thực thi tuần tự
- Mọi lệnh mở/đóng (thủ công và theo lịch) chạy **tuần tự qua một hàng đợi duy nhất** trên `@MainActor`. Lệnh mới đến trong lúc lệnh cũ chưa xong thì đợi.
- Trong lúc nhóm đang chạy lệnh, nút của nhóm đó hiện spinner và bị disable.

### 5.4 Bộ lập lịch
Dùng cách **quét định kỳ** thay vì tính trước từng timer, vì cách này tự xử lý được máy ngủ, đổi giờ hệ thống và đổi múi giờ:

- `Timer` mỗi 15 giây (tolerance 5 giây), cộng thêm việc gọi `check()` ngay khi nhận `NSWorkspace.didWakeNotification`, `.NSSystemClockDidChange`, `.NSSystemTimeZoneDidChange`.
- Lưu `lastCheckedAt` vào `UserDefaults`.
- Khi app khởi động: `from = max(lastCheckedAt đã lưu, now - missedGraceMinutes)`. Nhờ vậy nếu máy bật lúc 08:05 mà có lịch 08:00 thì vẫn chạy bù.
- `check()`:
  1. `now = Date()`.
  2. Đang tạm dừng: gán `lastCheckedAt = now` rồi dừng.
  3. `now < lastCheckedAt` (đồng hồ bị lùi): gán `lastCheckedAt = now` rồi dừng, không chạy gì.
  4. Gọi hàm thuần `Schedule.evaluate(...)` (mục 7.3) cho khoảng `(lastCheckedAt, now]` để lấy danh sách sự kiện cần chạy và sự kiện bị lỡ.
  5. Sự kiện trễ quá `missedGraceMinutes` thì ghi lịch sử "Bỏ lỡ", không chạy.
  6. Một lịch bị lỡ nhiều lần (ví dụ máy ngủ 3 ngày) chỉ tính **lần gần nhất**.
  7. Gán `lastCheckedAt = now`.
- Sự kiện cảnh báo (`warn`) của lịch Đóng tính tại `occurrence - warnBeforeCloseMinutes`. Cảnh báo bị lỡ quá hạn thì bỏ qua, không ghi lịch sử.
- Hoãn: lưu `snoozedUntil[occurrenceKey] = now + snoozeMinutes`. Mỗi lần `check()` sẽ chạy những lệnh Đóng đã hết hạn hoãn. `occurrenceKey = ruleID + thời điểm gốc`.
- Bỏ qua: thêm `occurrenceKey` vào `skipped`. Tới giờ thì ghi lịch sử "Đã bỏ qua theo yêu cầu".
- Múi giờ: dùng `Calendar.current`. Giờ không tồn tại khi chuyển DST thì dùng `matchingPolicy: .nextTime`; giờ lặp lại thì chỉ chạy lần đầu (`repeatedTimePolicy: .first`).
- **Weekday:** `Calendar` dùng 1 = Chủ nhật, 2 = Thứ 2 … 7 = Thứ 7. UI hiển thị Thứ 2 trước: `[2,3,4,5,6,7,1]`. Viết 1 helper duy nhất cho phép map này và test nó.
- Dòng "Tiếp theo" trên menu bar lấy lần chạy sớm nhất trong các lịch đang bật.

### 5.5 Trạng thái app đang chạy
- Đếm "3/4 đang chạy" bằng cách nghe `NSWorkspace.didLaunchApplicationNotification` và `didTerminateApplicationNotification`. Không polling.

### 5.6 Lưu trữ
- `~/Library/Application Support/LaunchSet/config.json`: nhóm, lịch, settings. Có trường `version: 1`.
- `~/Library/Application Support/LaunchSet/history.json`: lịch sử.
- Ghi file bằng `Data.write(to:options: .atomic)`, debounce 0,5 giây sau mỗi thay đổi.
- Đọc `config.json` bị lỗi thì **không được ghi đè**: đổi tên thành `config.corrupt-<yyyyMMdd-HHmmss>.json`, khởi động với cấu hình trống và hiện alert báo tên file đã đổi.
- `JSONEncoder` dùng `.prettyPrinted, .sortedKeys` để người dùng sửa tay được.

### 5.7 Cửa sổ và Dock
- Mặc định app không có icon Dock (`LSUIElement`).
- Khi mở cửa sổ quản lý thì gọi `NSApp.setActivationPolicy(.regular)` và `NSApp.activate()` để cửa sổ lên trước và xuất hiện trong ⌘Tab. Đóng cửa sổ cuối cùng thì trả về `.accessory`.

---

## 6. Giao diện

### 6.1 Menu bar (`MenuBarExtra`, `.menuBarExtraStyle(.window)`)
Icon menu bar: SF Symbol `square.stack.3d.up`. Popover rộng khoảng 320pt:

```
┌────────────────────────────────────────────┐
│ LaunchSet                   [⏸ Tạm dừng lịch] │
│ Tiếp theo: Đóng "Làm việc" lúc 18:00 hôm nay │
├────────────────────────────────────────────┤
│ [icon] Làm việc   3/4 đang chạy  [Mở] [Đóng] │
│ [icon] Giải trí   0/2 đang chạy  [Mở] [Đóng] │
├────────────────────────────────────────────┤
│ ⚠ Sắp đóng "Làm việc" lúc 18:00             │  ← chỉ hiện trong khoảng cảnh báo
│             [Hoãn 10 phút] [Bỏ qua lần này] │
├────────────────────────────────────────────┤
│ Mở cửa sổ quản lý…                          │
│ Cài đặt…                                    │
│ Thoát LaunchSet                             │
└────────────────────────────────────────────┘
```

Chưa có nhóm nào: "Chưa có nhóm nào." + nút "Tạo nhóm đầu tiên" (mở cửa sổ quản lý).

### 6.2 Cửa sổ quản lý (`Window`, `NavigationSplitView`)
Sidebar gồm 3 mục: **Nhóm app** (danh sách nhóm, nút +), **Lịch**, **Lịch sử**.

Nếu có lịch đang bật mà app chưa bật "Mở cùng macOS", hiện banner trên cùng:
"Lịch chỉ chạy khi LaunchSet đang mở. Bật mở cùng macOS để không bị lỡ lịch." [Bật ngay]

**Chi tiết nhóm:**
```
[icon▾] [Tên nhóm__________]              [Mở tất cả] [Đóng tất cả]

Ứng dụng                                   [Thêm app…] [Thêm từ app đang chạy ▾]
  ≡ [icon] Slack          com.tinyspeck.slackmacgap        ● Đang chạy
  ≡ [icon] Google Chrome  com.google.Chrome                ○ Không chạy
  ≡ [icon] OldApp         com.example.old                  ⚠ Không tìm thấy
  (kéo thả file .app vào đây)

Tuỳ chọn
  Chờ giữa mỗi lần mở app      [ 0 ] giây
  Ẩn app sau khi mở            [ ]
  Nếu app không chịu đóng      [Để yên và báo cho tôi ▾]

Lịch của nhóm này                                            [Thêm lịch]
  ☑ Mở   08:30   T2 T3 T4 T5 T6    Lần tới: Thứ 2, 08:30
  ☑ Đóng 18:00   T2 T3 T4 T5 T6    Lần tới: Hôm nay, 18:00
```
Icon app lấy bằng `NSWorkspace.shared.icon(forFile:)`. Xoá app bằng phím Delete hoặc menu chuột phải.

**Lịch** (`Table`): cột Bật | Nhóm | Hành động | Giờ | Ngày | Lần chạy tới. Double-click hoặc nút Sửa để mở sheet:
- Picker nhóm, segmented Mở/Đóng, `DatePicker` kiểu `.hourAndMinute`.
- 7 nút toggle ngày T2…CN, cùng các nút nhanh "Mọi ngày", "T2–T6", "T7–CN".
- Bắt buộc chọn ít nhất 1 ngày (nút Lưu disable và có dòng "Chọn ít nhất 1 ngày").
- Có xung đột thì hiện dòng vàng: "Trùng giờ với lịch Mở 18:00 của nhóm này."

**Lịch sử**: danh sách mới nhất ở trên, mỗi dòng dạng "18:00 · Đóng "Làm việc" · Theo lịch · Đã đóng 3, chưa đóng 1". Mở rộng ra để xem kết quả từng app.

### 6.3 Copy mẫu (dùng đúng các câu này)
- Empty nhóm: "Chưa có nhóm nào. Tạo nhóm để mở hoặc đóng nhiều app cùng lúc."
- Empty lịch: "Chưa có lịch. Thêm lịch để nhóm tự mở hoặc đóng theo giờ."
- Không tìm thấy app: "Không tìm thấy app. Có thể app đã bị xoá hoặc chuyển chỗ."
- Chặn app hệ thống: "Không thể thêm Finder vì macOS cần app này luôn chạy."
- Thông báo cảnh báo: tiêu đề `Sắp đóng nhóm "Làm việc"`, nội dung `4 app sẽ đóng lúc 18:00.`
- Thông báo lỗi đóng: tiêu đề `Một số app chưa đóng`, nội dung `TextEdit chưa đóng sau 15 giây, có thể đang chờ bạn lưu file.`
- Xác nhận buộc đóng: tiêu đề `Buộc đóng 4 app trong "Làm việc"?`, nội dung `Dữ liệu chưa lưu trong các app này sẽ bị mất.`, nút `Buộc đóng` (destructive) / `Huỷ`.
- Xác nhận nhập cấu hình: `Nhập cấu hình sẽ thay toàn bộ nhóm và lịch hiện tại.` nút `Nhập và thay thế` / `Huỷ`.

---

## 7. Kiến trúc

### 7.1 Cấu trúc thư mục (giữ đúng, không thêm lớp trừu tượng)
```
launchset/
├── Package.swift
├── Info.plist
├── scripts/
│   └── build-app.sh
└── Sources/
    ├── LaunchSetCore/          # chỉ import Foundation, không AppKit/SwiftUI
    │   ├── Models.swift        # AppRef, AppGroup, ScheduleRule, AppSettings, Config, RunRecord
    │   └── Schedule.swift      # nextOccurrence, evaluate, conflicts, weekday map
    ├── LaunchSet/
    │   ├── LaunchSetApp.swift  # @main: MenuBarExtra, Window, Settings
    │   ├── AppStore.swift      # @Observable @MainActor: state, load/save JSON, history
    │   ├── AppRunner.swift     # mở/đóng app (NSWorkspace, NSRunningApplication), hàng đợi tuần tự
    │   ├── Scheduler.swift     # timer 15s + observer wake/clock, gọi Schedule.evaluate + AppRunner
    │   ├── Notifier.swift      # UNUserNotificationCenter, category có action Hoãn/Bỏ qua
    │   └── Views/
    │       ├── MenuBarView.swift
    │       ├── MainWindow.swift
    │       ├── GroupDetailView.swift
    │       ├── ScheduleViews.swift   # Table + sheet sửa lịch
    │       ├── HistoryView.swift
    │       └── SettingsView.swift
    └── SelfCheck/
        └── main.swift          # assert logic trong LaunchSetCore
```

### 7.2 `Package.swift`
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LaunchSet",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LaunchSetCore"),
        .executableTarget(name: "LaunchSet", dependencies: ["LaunchSetCore"]),
        .executableTarget(name: "SelfCheck", dependencies: ["LaunchSetCore"]),
    ]
)
```

### 7.3 Model và API thuần (trong `LaunchSetCore`)
```swift
public struct AppRef: Codable, Hashable, Identifiable {
    public var bundleID: String
    public var name: String
    public var lastKnownPath: String
    public var id: String { bundleID }
}

public enum QuitPolicy: String, Codable { case leaveAndNotify, forceQuit }

public struct AppGroup: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String            // SF Symbol
    public var apps: [AppRef]
    public var launchDelaySeconds: Int   // 0...30
    public var hideAfterOpen: Bool
    public var quitPolicy: QuitPolicy
}

public enum GroupAction: String, Codable { case open, close }

public struct ScheduleRule: Codable, Identifiable {
    public var id: UUID
    public var groupID: UUID
    public var action: GroupAction
    public var hour: Int                 // 0...23
    public var minute: Int               // 0...59
    public var weekdays: Set<Int>        // theo Calendar: 1 = CN, 2 = T2 ... 7 = T7
    public var isEnabled: Bool
}

public struct AppSettings: Codable {
    public var warnBeforeCloseMinutes: Int   // 0 = tắt
    public var snoozeMinutes: Int
    public var quitTimeoutSeconds: Int
    public var missedGraceMinutes: Int
    public var notifyOnSuccess: Bool
    public var schedulesPaused: Bool
}

public struct Config: Codable {
    public var version: Int
    public var groups: [AppGroup]
    public var rules: [ScheduleRule]
    public var settings: AppSettings
}

public struct DueEvent: Hashable {
    public enum Kind: Hashable { case run, warn }
    public let ruleID: UUID
    public let kind: Kind
    public let occurrence: Date   // thời điểm gốc của lịch (warn cũng giữ thời điểm gốc)
    public let fireAt: Date       // run: = occurrence; warn: = occurrence - warnBeforeCloseMinutes
}

public enum Schedule {
    /// Lần chạy kế tiếp, lớn hơn hẳn `after`.
    public static func nextOccurrence(of rule: ScheduleRule, after: Date, calendar: Calendar) -> Date?

    /// Sự kiện có fireAt nằm trong (from, now]. Mỗi (rule, kind) chỉ lấy lần gần `now` nhất.
    /// `due`: trễ <= graceMinutes. `missed`: chỉ gồm kind == .run và trễ hơn grace.
    /// Bỏ qua rule tắt. Sắp theo fireAt, cùng fireAt thì giữ thứ tự trong `rules`.
    public static func evaluate(rules: [ScheduleRule], settings: AppSettings,
                                from: Date, now: Date, calendar: Calendar)
        -> (due: [DueEvent], missed: [DueEvent])

    /// Cặp rule cùng group, cùng giờ:phút, trùng >= 1 weekday, khác action.
    public static func conflicts(in rules: [ScheduleRule]) -> [(UUID, UUID)]

    /// Thứ tự hiển thị T2 trước: [2, 3, 4, 5, 6, 7, 1]
    public static let displayWeekdays: [Int]
}
```
Mọi field đều bắt buộc trong JSON v1. Khi thêm field ở phiên bản sau thì viết `init(from:)` dùng `decodeIfPresent` để file cũ vẫn đọc được.

### 7.4 `Info.plist`
Các key cần có: `CFBundleExecutable = LaunchSet`, `CFBundleIdentifier`, `CFBundleName`, `CFBundlePackageType = APPL`, `CFBundleShortVersionString = 1.0`, `CFBundleVersion = 1`, `LSUIElement = true`, `LSMinimumSystemVersion = 14.0`. Không cần `NSAppleEventsUsageDescription`.

### 7.5 `scripts/build-app.sh` (khung đã chạy thử được trên máy)
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LaunchSet"
APP=build/LaunchSet.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x LaunchSet || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/LaunchSet.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/LaunchSet.app
fi
```

---

## 8. Thứ tự làm (mỗi milestone phải qua gate rồi mới làm tiếp)

**Gate chung cho mọi milestone:**
1. `swift build` không có error, không có warning concurrency.
2. `swift run SelfCheck` in `All checks passed` và exit 0.
3. `scripts/build-app.sh` build ra `.app` thành công.
4. Báo lại **output thật** của 3 lệnh trên. Gate đỏ thì sửa, không được nhảy sang milestone sau.

### M0: Kiểm chứng rủi ro (làm trước khi viết UI)
Viết tạm một màn hình có 4 nút để kiểm tra trên `.app` đã ký ad-hoc:
- Mở **TextEdit** (`com.apple.TextEdit`) bằng `NSWorkspace.openApplication`.
- Đóng TextEdit bằng `terminate()`, xác nhận hàm trả `true` và app thật sự tắt.
- Gửi 1 thông báo có action, bấm action thì app nhận được callback.
- `SMAppService.mainApp.register()` khi app nằm trong `~/Applications`, đọc lại `status`.

Ghi kết quả từng mục. Mục nào fail thì **dừng lại và báo**, không tự đổi kiến trúc. Xong thì xoá màn hình tạm.

### M1: Core + SelfCheck
`Models.swift`, `Schedule.swift`, `SelfCheck/main.swift`. Dùng `Calendar(identifier: .gregorian)` với `timeZone = Asia/Ho_Chi_Minh` và ngày cố định. Tối thiểu phải có các case sau:
1. Lịch 18:00 T2–T6, `after` = Thứ 6 đúng 18:00:00 thì kết quả là Thứ 2 tuần sau lúc 18:00 (lớn hơn hẳn).
2. `after` = Thứ 6 17:59 thì kết quả là Thứ 6 18:00.
3. Lịch chỉ T7–CN, `after` = Thứ 4 thì kết quả là Thứ 7.
4. `evaluate` với khoảng (17:59:50, 18:00:05] có sự kiện `run` trong `due`.
5. Máy ngủ: from 17:00, now 18:10, grace 15 thì nằm trong `due`; now 18:20 thì nằm trong `missed`.
6. Ngủ 3 ngày qua lịch "Mọi ngày" thì chỉ ra đúng 1 sự kiện cho rule đó.
7. Lịch Đóng 18:00, cảnh báo 2 phút thì có `warn` với fireAt 17:58. Lịch Mở không có `warn`.
8. `from > now` thì cả `due` lẫn `missed` đều rỗng.
9. Rule đang tắt không bao giờ xuất hiện.
10. `conflicts` bắt được cặp Mở/Đóng cùng giờ và trùng ngày; không bắt cặp khác ngày.
11. `displayWeekdays == [2,3,4,5,6,7,1]`.
12. `Config` encode rồi decode lại cho kết quả giống hệt.
13. DST: `timeZone = America/New_York`, lịch 02:30 vào ngày 14/03/2027 thì trả về đúng 1 thời điểm trong ngày đó, không crash, không nhảy sang ngày khác.

Thiếu framework test thì dùng helper `check(_ cond: Bool, _ name: String)` tự đếm lỗi; cuối file `exit(failures == 0 ? 0 : 1)`.

### M2: Nhóm app + thao tác thủ công
`AppStore` (load/save/xử lý file hỏng), `AppRunner` (mục 5.1–5.3), `MenuBarView`, `MainWindow`, `GroupDetailView`, thêm app bằng 3 cách, danh sách chặn, đếm app đang chạy.

### M3: Lịch + cảnh báo + lịch sử + settings
`Scheduler`, `Notifier`, `ScheduleViews`, `HistoryView`, `SettingsView`, mở cùng macOS, banner nhắc bật, xuất/nhập cấu hình, tạm dừng lịch.

### M4: Nghiệm thu thủ công
Chạy checklist mục 9, ghi rõ mục nào pass, mục nào chưa kiểm được (ví dụ log out/in) để người dùng tự kiểm.

---

## 9. Checklist nghiệm thu (chỉ dùng TextEdit và Calculator để test)

- [ ] Tạo nhóm "Test" gồm TextEdit + Calculator, bấm **Mở** thì cả hai mở và menu bar hiện `2/2 đang chạy`.
- [ ] Bấm **Đóng** thì cả hai đóng, hiện `0/2`.
- [ ] Mở TextEdit, gõ chữ (chưa lưu), bấm **Đóng**: hộp thoại lưu hiện ra; sau 15 giây lịch sử ghi `Chưa đóng`; dữ liệu không mất.
- [ ] Đổi nhóm sang `Buộc đóng` rồi lặp lại: TextEdit bị buộc đóng, lịch sử ghi `Đã buộc đóng`.
- [ ] Thêm lịch Mở vào (giờ hiện tại + 2 phút): app mở trong vòng 15 giây sau giờ đó, lịch sử ghi `Theo lịch`.
- [ ] Lịch Đóng với cảnh báo 1 phút: thông báo đến trước 1 phút. Bấm **Hoãn** thì app đóng sau thời gian hoãn. Bấm **Bỏ qua** thì app không đóng.
- [ ] Tắt quyền thông báo: dòng "Sắp đóng" vẫn hiện trên menu bar và 2 nút vẫn dùng được.
- [ ] Tạm dừng lịch qua giờ chạy rồi bỏ tạm dừng: lịch đó không chạy bù.
- [ ] Cho máy ngủ qua giờ lịch, mở máy trong 15 phút thì lịch chạy bù; quá 15 phút thì lịch sử ghi `Bỏ lỡ`.
- [ ] Sửa `config.json` thêm bundle ID giả: nhóm hiện `Không tìm thấy`, bấm Mở vẫn mở các app còn lại.
- [ ] Thoát LaunchSet rồi mở lại: nhóm, lịch, lịch sử còn nguyên.
- [ ] Làm hỏng `config.json` (xoá một dấu `}`): app vẫn mở, file cũ được đổi tên, có alert.
- [ ] Kéo Finder vào nhóm: bị từ chối, hiện lý do.
- [ ] Xuất cấu hình, xoá hết nhóm, nhập lại: mọi thứ khôi phục.
- [ ] Bật "Mở cùng macOS", log out rồi log in lại: LaunchSet tự chạy.
- [ ] Mở cửa sổ quản lý: app hiện trong ⌘Tab. Đóng cửa sổ: app biến khỏi Dock.

---

## 10. Ngoài phạm vi v1 (KHÔNG làm, trừ khi được yêu cầu)

- Phím tắt toàn cục cho từng nhóm.
- Tích hợp Shortcuts/App Intents, Siri, URL scheme.
- Chế độ "đóng mọi app trừ nhóm này".
- Mở kèm file, thư mục, URL hay tab trình duyệt.
- Sắp xếp vị trí cửa sổ sau khi mở.
- Lịch theo sự kiện (đổi Wi-Fi, cắm màn hình, pin yếu).
- Đồng bộ iCloud, nhiều ngôn ngữ, app icon riêng, notarize, auto-update.

---

## 11. Quy tắc làm việc

1. Không thêm dependency bên thứ ba. Không bật App Sandbox. Không dùng AppleScript/Apple Events. Không xin quyền Accessibility.
2. Không tạo protocol, factory hay lớp trừu tượng chỉ có 1 cách cài đặt. Giữ đúng cấu trúc file ở 7.1; view nào vượt khoảng 300 dòng thì mới tách.
3. Logic lịch phải nằm trong `LaunchSetCore` dưới dạng hàm thuần, nhận `Date`/`Calendar` từ tham số, không gọi `Date()` bên trong, để `SelfCheck` kiểm được.
4. State UI đặt trên `@MainActor`. Không dùng `DispatchQueue.main.async` rải rác khi `async/await` làm được.
5. Khi test chỉ được mở/đóng **TextEdit** và **Calculator**. Tuyệt đối không quit app nào khác đang chạy trên máy nếu chưa hỏi.
6. Làm lần lượt M0 → M4. Hết mỗi milestone, báo: đã làm gì, output thật của gate, việc còn lại.
7. Spec mâu thuẫn hoặc không làm được đúng như mô tả: dừng lại và hỏi. Chi tiết nhỏ spec không nói tới: chọn cách đơn giản nhất và ghi chú 1 dòng trong báo cáo.
8. Chỗ nào cố ý làm đơn giản và có giới hạn đã biết thì ghi comment `// ponytail: <giới hạn>, <khi nào cần nâng cấp>`.

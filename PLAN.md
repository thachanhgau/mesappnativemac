# Messenger for macOS – Kế hoạch

Ngày lập: 25/11/2026 · Môi trường: macOS 15.8.3, Xcode, Swift 6.2.4 (arm64)

## 1. Bối cảnh

- Meta đã khai tử app Messenger desktop (Mac/Windows) từ 15/12/2025; người dùng bị chuyển về facebook.com (có tài khoản FB) hoặc messenger.com (không có tài khoản FB).
- Meta **không có API công khai** cho chat cá nhân. Graph/Messenger Platform API chỉ dành cho Page/bot.

## 2. Quyết định kiến trúc

| Phương án | Đủ chức năng | Nhẹ | Rủi ro | Kết luận |
|---|---|---|---|---|
| **Swift + WKWebView** bọc web Messenger | Có (chính là web của Meta) | Rất nhẹ: dùng WebKit sẵn của macOS, app chỉ vài trăm KB | Meta đổi giao diện web → chỉ ảnh hưởng phần JS tiêm vào (giữ tối thiểu) | **Chọn** |
| Electron | Có | Nặng: kèm cả Chromium (~150–250 MB dung lượng, RAM cao) | Thấp | Loại (trái mục tiêu “nhẹ”) |
| Client native tự viết, giao thức reverse-engineer (MQTT nội bộ của Meta) | Một phần, luôn đuổi theo Meta | Nhẹ | **Vi phạm ĐK sử dụng, nguy cơ khóa tài khoản**, E2EE rất phức tạp, bảo trì nặng | Loại |

=> App native macOS (AppKit) làm vỏ: cửa sổ, Dock, thông báo, phím tắt, gửi file. Nội dung chat do web Messenger chính chủ xử lý → đầy đủ chức năng, cập nhật tự động theo Meta.

## 3. Tính năng & cách hiện thực

| Tính năng | Cách làm |
|---|---|
| Đăng nhập, giữ phiên | `WKWebsiteDataStore.default()` – cookie lưu bền, mở lại không phải đăng nhập |
| Chat, sticker, reaction, nhóm, E2EE | Web Messenger lo toàn bộ |
| Gửi ảnh/file | `WKUIDelegate.runOpenPanelWith` → `NSOpenPanel`; kéo-thả có sẵn |
| Tải file/ảnh về | Link file ngoài domain FB → mở trình duyệt mặc định tải |
| Thông báo tin nhắn mới | Shim JS thay `window.Notification` → `WKScriptMessageHandler` → `UNUserNotificationCenter`; bấm thông báo → đưa cửa sổ lên |
| Badge số tin chưa đọc trên Dock | KVO `webView.title` (dạng “(3) Messenger”) → `NSApp.dockTile.badgeLabel` |
| Link ngoài | Mở bằng trình duyệt mặc định (`NSWorkspace.open`), chỉ giữ domain facebook/messenger trong app |
| Đóng cửa sổ ≠ thoát | Ẩn cửa sổ, bấm icon Dock mở lại (vẫn nhận thông báo) |
| Menu chuẩn macOS | Cmd+Q/W/C/V/Z, Cmd+R reload, Cmd +/- zoom |
| User-Agent | Đặt UA Safari để Meta không báo “trình duyệt không hỗ trợ” |

## 4. Cấu trúc dự án (tối giản, không cần .xcodeproj)

```
Messenger/
├── PLAN.md
├── main.swift      # toàn bộ app (~190 dòng)
├── Info.plist      # bundle id, LSMinimumSystemVersion
└── build.sh        # swiftc -O → đóng gói Messenger.app, ký ad-hoc (codesign -s -)
```

Build: `./build.sh` → `Messenger.app` → kéo vào /Applications.

## 5. Lộ trình

| Giai đoạn | Nội dung | Tiêu chí hoàn thành |
|---|---|---|
| P1 – MVP | Cửa sổ + WKWebView, giữ phiên, UA, link ngoài, menu, build.sh | Đăng nhập, nhắn tin, mở lại app không phải login |
| P2 – Native | Thông báo, badge Dock, gửi file, đóng = ẩn | Nhận thông báo khi app ở nền |
| P3 – Hoàn thiện | Icon, nhớ kích thước/vị trí cửa sổ, đo RAM/CPU so với tab Safari | Số đo thực tế ghi vào README |

Ước lượng: P1 ~0,5 ngày, P2 ~1 ngày, P3 ~0,5 ngày (ước tính, chưa kiểm chứng).

## 6. Rủi ro cần kiểm tra sớm (ngay ở P1)

1. **Thông báo**: shim `window.Notification` cần thử thực tế sau khi đăng nhập.
2. **URL đích**: thử cả `facebook.com/messages` và `messenger.com`, chọn cái ổn định hơn (là 1 hằng số trong code).
3. **Chat mã hóa đầu cuối (E2EE)**: lần đầu trên “thiết bị mới” cần nhập PIN/khôi phục lịch sử – hành vi của Meta, không phải lỗi app.
4. **Meta đổi web**: chỉ shim Notification phụ thuộc JS; badge lấy từ title nên ít vỡ.

## 7. Ngoài phạm vi (thêm khi thực sự cần)

**Phạm vi chốt 25/11/2026: chỉ chat (bỏ gọi thoại/video).** Nhiều tài khoản, gọi thoại/video, menu bar mini-window, tự cập nhật (Sparkle), phát hành App Store/notarize.

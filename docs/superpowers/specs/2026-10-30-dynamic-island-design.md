# MeloDock → Dynamic Island แบบ iPhone บนรอยบาก MacBook

## Context

ตอนนี้ MeloDock เป็นแผง "Now Playing" ขนาดคงที่ 612×176 ที่เปิด/ปิดด้วย hotkey (`IslandPanelController` + `IslandView`)
ผู้ใช้อยากให้รอยบากทำงาน "เหมือน iPhone ทุกอย่าง" เท่าที่ macOS อนุญาต ผลลัพธ์ที่ต้องการคือ:
- เกาะเกาะติดรอยบากตลอดเวลา
- ยืด/หดแบบเด้งตามสิ่งที่เกิดขึ้น
- แสดงได้หลายเรื่อง ได้แก่ เพลง แบต อุปกรณ์บลูทูธ เสียง ไมค์/กล้อง ตัวจับเวลา และปฏิทิน

## สิ่งที่ผู้ใช้ตัดสินใจแล้ว
- **เอาทุกอย่างในกลุ่ม "ทำได้"**:
  - พฤติกรรมเกาะ: ย่อ/ขยายแบบ spring, โหมด compact/expanded, สองกิจกรรมพร้อมกัน, แจ้งเตือนชั่วคราว
  - เพลง
  - ชาร์จ/แบตต่ำ
  - AirPods/บลูทูธ
  - เสียงและลำโพง
  - ตัวจับเวลา
  - ปฏิทิน
  - ไมค์/กล้องกำลังใช้
- **เกาะติดรอยบากตลอด**:
  - ไม่มีอะไรแสดง → ดำกลืนกับรอยบาก
  - มีกิจกรรม → ยืดเป็น "หู" ซ้าย/ขวา
  - ขยายเป็นแผงเต็มเมื่อต้องการ
- **ขยายด้วยการชี้เมาส์ค้าง (~0.3 วิ)**:
  - เอาเมาส์ออกแล้วย่อกลับ
  - คลิกเกาะหรือกด hotkey ก็ขยาย/ย่อได้

- **มีเกาะเดียว อยู่ที่รอยบากของ MacBook เสมอ** แม้ทำงานบนจอนอก:
  - ถ้าปิดฝา (ไม่มีจอในตัว) ย้ายไปเป็นเม็ดยาใต้เมนูบาร์ของจอหลัก
  - ใช้ panel เดียวเหมือนเดิม

## Non-goals (macOS ไม่เปิดให้ทำ)
- Live Activities ของแอปอื่น
- แจ้งเตือนของแอปอื่น
- สายโทรเข้า
- Face ID / Apple Pay
- แบต AirPods (ไม่มี public API)
- ซ่อน HUD เสียงของระบบ (ทำไม่ได้ใน sandbox) เกาะจะแสดงคู่กับ HUD ระบบ

## Anti-goals
- บังการคลิกเมนูบาร์ในส่วนที่โปร่งใสของ panel
- เกาะกระพริบหรือกระตุกตอนเปลี่ยนสถานะ
- กิน CPU เมื่อเกาะว่าง (ห้าม poll ถี่ ให้ใช้ listener/notification)
- ต้องเลิก sandbox

## การตัดสินใจของผม (ตรวจได้)
- **คง sandbox** ทุกฟีเจอร์ทำได้ใน sandbox:
  - AirPods ตรวจผ่าน CoreAudio device list (transport type Bluetooth) จึงไม่ต้องใช้ entitlement บลูทูธ
  - เพิ่มแค่ entitlement ปฏิทิน
- **รูปทรงเกาะ**: ขอบบนแบนติดขอบจอ มุมล่างโค้ง (ต่อเนื่องกับรอยบาก) ขนาดตอนว่างเท่ารอยบากพอดี:
  - กว้าง = ช่องระหว่าง `auxiliaryTopLeftArea` กับ `auxiliaryTopRightArea`
  - สูง = `safeAreaInsets.top`
- **จอไม่มีรอยบาก/จอนอก**:
  - ตอนว่าง ซ่อนเกาะ
  - เมื่อมีกิจกรรม แสดงเม็ดยาลอยใต้เมนูบาร์ (ต่อยอด fallback เดิม)
- **ลำดับความสำคัญ** กิจกรรมต่อเนื่อง จากมากไปน้อย:
  1. ตัวจับเวลา (รวมตอนหมดเวลา)
  2. นัดปฏิทินใกล้ถึง
  3. เพลงกำลังเล่น
  4. ไมค์/กล้อง
  5. เพลงหยุดชั่วคราว
- **การแสดงสองเรื่อง**:
  - อันดับ 1 อยู่ใน "หู"
  - อันดับ 2 เป็นวงกลมเล็กแยกทางขวา (แบบ iPhone)
- **แจ้งเตือนชั่วคราว**:
  - ได้แก่ เสียบสายชาร์จ, แบตต่ำ 20%/10%, บลูทูธต่อ/หลุด, ปรับเสียง/เปลี่ยนลำโพง, ตัวจับเวลาหมด
  - ทับหูชั่วคราว 2.5 วิ (ปรับเสียงจะอยู่ตราบที่ยังปรับ)
  - เข้าคิวทีละอัน
- **โหมดขยาย**:
  - แสดงหน้าของกิจกรรมอันดับ 1
  - ด้านล่างมีแถบเล็กไว้สลับไปกิจกรรมอื่นที่ active และปุ่มเปิดตัวจับเวลา
  - หน้าเพลงคือ player เดิม (ปรับขนาดให้เข้าเกาะ)
- **ตัวจับเวลา**:
  - ปุ่ม preset 1/5/10/25 นาที, เวลากำหนดเอง และนาฬิกาจับเวลา
  - หมดเวลามีเสียง `NSSound`
  - เก็บในหน่วยความจำเท่านั้น (ปิดแอปแล้วหาย)
- **ปฏิทิน**:
  - ขึ้นหู 10 นาทีก่อนนัดเริ่ม จนถึง 5 นาทีหลังเริ่ม
  - หน้าขยายแสดงชื่อ เวลา สถานที่ และปุ่ม Join ถ้ามีลิงก์ประชุม
  - ปิดไว้จนกว่าผู้ใช้กดอนุญาต
- **ขยายตอนเกาะว่าง**:
  - hover บนรอยบากที่ว่างจะไม่ขยาย (กันขยายเองตอนเอาเมาส์ไปเมนูบาร์)
  - คลิกรอยบากหรือกด hotkey จึงขยาย
  - หน้าที่ขึ้นคือ "หน้าหลัก": player เพลงของ provider ล่าสุด และปุ่มตัวจับเวลา
- **เพลงหยุดชั่วคราว** ค้างในหู 5 นาที แล้วกลับเป็นว่าง
- **ตัวจับเวลาหมด**:
  - หูกระพริบ และเสียงดังซ้ำทุก ~3 วิ นานสูงสุด 30 วิ หรือจนกว่าผู้ใช้คลิกปิด
  - transient "หมดเวลา" คือจังหวะแรกของสถานะนี้ ไม่ได้แยกเป็นอีกอัน
  - มีนับถอยหลังได้ 1 อัน และนาฬิกาจับเวลาได้ 1 อัน พร้อมกัน
- **Settings**:
  - สวิตช์เปิด/ปิดแต่ละกิจกรรม
  - `showOnStartup` เปลี่ยนเป็น "แสดงเกาะ" (ใช้ key เดิม ค่าเริ่มต้นเปิด)
  - ถ้าปิด "แสดงเกาะ" จะไม่มีหูหรือแจ้งเตือนเลย แต่ hotkey ยังเปิดหน้าขยายชั่วคราวได้
  - `overlayVisible` เปลี่ยนความหมายเป็น "กำลังขยาย" (ใช้ throttle polling เพลงเหมือนเดิม) ทุกครั้งที่เปิดแอปเริ่มในสถานะย่อเสมอ

## สถาปัตยกรรม

**Domain** (ใหม่ `Domain/Models/IslandActivity.swift`, `Domain/Protocols/ActivitySource.swift`):
- `IslandActivity`: id, kind, priority, ongoing/transient, ข้อมูลสำหรับ compact leading/trailing และ expanded
- `ActivitySource` (`@MainActor`): publisher ของ `[IslandActivity]` และ transient events

**ตัวรวม** `Features/Island/IslandCoordinator.swift` (`@MainActor ObservableObject`):
- รวมทุก source แล้วเลือก primary/secondary ตามลำดับความสำคัญ
- จัดคิว transient
- state machine: `idle → compact → expanded` และ `transient` ทับ compact
- logic เลือก/คิวเป็นฟังก์ชันล้วน เพื่อให้เทสได้

**Panel** (rewrite `IslandPanelController.swift`):
- panel โปร่งใสขนาดคงที่เท่าโหมดขยายสูงสุด ยึดกึ่งกลางรอยบากที่ขอบบนจอ
- SwiftUI วาดรูปทรงที่ animate ด้วย spring ระหว่างขนาดรอยบาก → compact → expanded
- ส่วนโปร่งใสต้องคลิกทะลุได้ โดยสลับ `ignoresMouseEvents` ตามว่าเมาส์อยู่ในกรอบรูปทรงปัจจุบันหรือไม่ (mouse-moved monitor ไม่ต้องขอ Accessibility)
- hover ค้าง 0.3 วิ → ขยาย, ออก → ย่อ
- ยกการคำนวณตำแหน่งรอยบากเดิม (`notchCenterX`, `normalizedAuxiliaryArea`, `validatedNotchCenterX`) ไปเป็นฟังก์ชันล้วน `NotchGeometry` เพื่อเทส
- คง `.fullScreenAuxiliary` ไว้

**View** (แยก `IslandView.swift`):
- `IslandShellView`: รูปทรงและ animation
- `CompactViews`: หูของแต่ละ kind
- `ExpandedMusicView`: ย้าย layout เดิมมา
- `TimerView`
- `CalendarEventView`
- `SystemAlertView`

**Sources**:

| Source | ไฟล์ | กลไก |
|---|---|---|
| เพลง | `IslandViewModel` เดิม + adapter เป็น `NowPlayingActivitySource` | ตามเดิม (compact: artwork ซ้าย, `MusicSpectrumView` ขวา) |
| แบต/ชาร์จ | `Integrations/PowerSourceService.swift` | IOKit `IOPSNotificationCreateRunLoopSource` + `IOPSCopyPowerSourcesInfo` |
| บลูทูธเสียง + เสียง/ลำโพง | ขยาย `CoreAudioService` | `AudioObjectAddPropertyListenerBlock`:<br>• `kAudioHardwarePropertyDevices`<br>• `kAudioHardwarePropertyDefaultOutputDevice`<br>• volume scalar<br>• transport type `kAudioDeviceTransportTypeBluetooth`<br>แทนการ poll ทุก 8 วิ |
| ไมค์ | `Integrations/CaptureActivityService.swift` | `kAudioDevicePropertyDeviceIsRunningSomewhere` บน input devices |
| กล้อง | ไฟล์เดียวกัน | CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` |
| ตัวจับเวลา | `Features/Timer/TimerModel.swift` | ใช้นาฬิกาที่ inject ได้ |
| ปฏิทิน | `Integrations/CalendarService.swift` | EventKit `requestFullAccessToEvents`, ฟัง `EKEventStoreChanged` + ตั้ง timer ถึงนัดถัดไป |

**Wiring**:
- `DIContainer`: สร้าง services ใหม่และ coordinator
- `AppDelegate`:
  - hotkey/เมนู "Toggle Overlay" → ขยาย/ย่อ
  - เพิ่มเมนู "Show Island"
- `SettingsStore`: เพิ่ม key `settings.island.*` สำหรับสวิตช์แต่ละกิจกรรม

**Config**:
- entitlement `com.apple.security.personal-information.calendars` ใน `MeloDock.entitlements`
- `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription` ใน `project.pbxproj` ทั้ง Debug และ Release (ข้อยกเว้นจาก "ไม่ต้องแก้ pbxproj")
- ช่วง spike ต้องตรวจว่าอ่านสถานะกล้องใน sandbox ได้โดยไม่ต้องขอ entitlement กล้อง ถ้าไม่ได้ ให้ตัดกล้องออก เหลือไมค์ แล้วแจ้งผู้ใช้

## ลำดับการทำ (แต่ละเฟส build ผ่านและใช้งานได้จริง)
1. **โครงเกาะ**:
   - `NotchGeometry`, panel ใหม่ (คลิกทะลุ), shell + spring
   - state machine + coordinator
   - hover/คลิก/hotkey
   - เพลงเป็นทั้ง compact และ expanded
2. **เหตุการณ์ระบบ**:
   - แบต/ชาร์จ
   - บลูทูธ + เสียง/ลำโพง (เปลี่ยน CoreAudio เป็น listener)
   - ไมค์/กล้อง
   - คิว transient + วงกลมเรื่องที่สอง
3. **ตัวจับเวลา + ปฏิทิน**:
   - หน้า expanded มีแถบสลับ
   - Settings toggles
   - entitlement/usage string

หลังผู้ใช้อนุมัติ:
- เขียนไฟล์นี้เป็น spec ที่ `docs/superpowers/specs/2026-10-30-dynamic-island-design.md` แล้ว commit บน `dev`
- ใช้ `superpowers:writing-plans` แตกเป็นแผนงานทีละเฟส

## Verification
- **เทส XCTest** ใน `MeloDock/Tests/` (มาร์ก `@MainActor`, ใช้ `UserDefaults` suite ชั่วคราว):
  - `NotchGeometry`: notch center/width, พิกัด backing/local
  - การเลือก primary/secondary และคิว transient
  - state machine transitions
  - TimerModel ด้วยนาฬิกาปลอม
  - ช่วงเวลาแสดงนัดปฏิทิน
  - SettingsStore keys ใหม่
- **รันทั้งชุด**:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MeloDock/MeloDock.xcodeproj -scheme MeloDock -destination 'platform=macOS' test`
- **ทดสอบมือบน MacBook ที่มีรอยบาก**:
  - ตอนว่างเกาะกลืนกับรอยบาก
  - คลิกเมนูบาร์ข้าง ๆ ได้
  - เล่นเพลง → หูขึ้น
  - hover → ขยาย/ย่อ
  - เสียบ/ถอดสายชาร์จ
  - ต่อ AirPods
  - ปรับเสียง
  - เปิด Photo Booth (กล้อง) / Voice Memos (ไมค์)
  - ตั้งเวลา 1 นาที
  - สร้างนัดใน Calendar อีก 5 นาที
  - เข้าแอปเต็มจอ
  - ต่อจอนอก

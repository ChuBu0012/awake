# Awake Verification Guide

คู่มือและขั้นตอนการตรวจสอบคุณภาพ การแสดงผล UI (Light/Dark Mode, Accessibility) และการทดสอบบนเครื่องจำลอง macOS VM ก่อนการ Release

---

## 1. การตรวจสอบ UI Appearance (Light & Dark Mode)

Awake ถูกออกแบบให้รองรับทั้ง Dark Mode และ Light Mode บน macOS อย่างกลมกลืนตามแนวทาง macOS Human Interface Guidelines (HIG)

### คำสั่งช่วยสลับโหมดอัตโนมัติ
สามารถรันสคริปต์สลับ Theme จาก Terminal ได้ทันที:
```bash
# สลับ Theme ไป-มา
./scripts/toggle-appearance.sh toggle

# กำหนดเป็น Dark Mode
./scripts/toggle-appearance.sh dark

# กำหนดเป็น Light Mode
./scripts/toggle-appearance.sh light
```

### รายการตรวจสอบ UI Checklist
- [ ] **Menu Bar Status Item**:
  - ไอคอน `moon.zzz` (Inactive) และ `eye.fill` (Active) ปรับสีเป็นสีดำใน Light Mode และสีขาวใน Dark Mode อัตโนมัติ (ผ่าน `.isTemplate = true`)
  - ขนาดของปุ่มเมนูบาร์ต้องคงที่ `(36.0, 24.0)` ไม่มีการขยับหรือกระตุกเมื่อกดเปิด/ปิด
- [ ] **Popover Window Contrast**:
  - ข้อความ Status Header และรายละเอียดสถานะอ่านง่าย ชัดเจน ไม่จมกลืนกับพื้นหลัง
  - ปุ่มหลัก **Turn On Awake** (สีฟ้า Accent) และ **Turn Off Awake** (ปุ่มโทนอ่อน) มี Contrast Ratio ผ่านเกณฑ์ WCAG AA
  - Duration Selector pills มีตัวหนังสือสีขาวบนพื้นหลังสีฟ้าเมื่อถูกเลือก และมีตัวหนังสือสีหลักบนพื้นหลังจางเมื่อไม่ได้เลือก
  - รายการ Automations cards แสดงสถานะ (Active/Paused) และปุ่มกดลบ/แก้ไขอย่างชัดเจน
- [ ] **Settings Window**:
  - แถบ Tab Picker ด้านบนแสดงไอคอนและตัวหนังสือคมชัด
  - Badge สีเขียว `"✓ Verified (LaunchAgent)"` และ `"✓ Verified (Passwordless pmset)"` อ่านง่าย ชัดเจน

---

## 2. การตรวจสอบการเข้าถึง (Accessibility & Reduce Motion)

Awake ให้ความสำคัญกับผู้ใช้ที่เปิดการตั้งค่าลดการเคลื่อนไหว (Reduce Motion) เพื่อป้องกันอาการเวียนศีรษะหรือภาพกระตุก

### ขั้นตอนการทดสอบ Reduce Motion
1. เปิด **System Settings** บน macOS (หรือ System Preferences ใน macOS 12)
2. ไปที่ **Accessibility** > **Display**
3. เปิดสวิตช์ **Reduce motion** (ลดการเคลื่อนไหว)
4. ทดสอบเปิด-ปิด Popover จากเมนูบาร์:
   - Popover ต้องปรากฏขึ้นทันทีโดยไม่มีแอนิเมชันวูบวาบหรือเลื่อนตำแหน่ง
   - การกดปุ่ม Toggle ใน Popover ต้องเปลี่ยนสถานะอย่างนิ่งสนิท 100%

---

## 3. ขั้นตอนการทดสอบบน Clean macOS Virtual Machine (Desktop VM)

การทดสอบบน macOS VM (เช่น Tart หรือ UTM) จำลองสภาพแวดล้อมเสมือนเครื่องจริงของผู้ใช้ใหม่ที่ยังไม่เคยติดตั้ง Go, Xcode หรือสิทธิ์ sudoers ใดๆ

### ขั้นตอนการทดสอบ
1. **เตรียมไฟล์ติดตั้ง**:
   - รันคำสั่งสร้าง Release Preview บนเครื่องหลัก:
     ```bash
     make preview
     ```
   - จะได้ไฟล์ `build/Awake.dmg` และ `build/Awake.zip`
2. **ส่งไฟล์ไปยัง VM**:
   - คัดลอก `Awake.dmg` เข้าสู่ VM (ผ่าน Shared Folder หรือเครือข่าย)
3. **ตรวจสอบ Gatekeeper First-Launch**:
   - ดับเบิลคลิกเปิด `Awake.dmg` และลาก `Awake.app` ลงใน `/Applications`
   - เมื่อเปิดแอปครั้งแรก: หาก macOS แจ้งเตือน *"Awake cannot be opened because the developer cannot be verified"* ให้คลิกขวาที่แอปเลือก **Open** (หรือไปที่ **System Settings > Privacy & Security** แล้วกด **Open Anyway**)
   - ยืนยันว่าแอปเปิดขึ้นที่เมนูบาร์ได้สำเร็จ
4. **ตรวจสอบ Status Bar & Popover**:
   - ไอคอนปรากฏที่เมนูบาร์สะอาด ไม่มีแอปอื่นเบียดบัง
   - คลิกไอคอน ยืนยันว่า Popover ลูกศรชี้ตรงกึ่งกลางไอคอนเป๊ะ
   - กด **Turn On Awake** ยืนยันว่าเวลาเริ่มนับถอยหลัง 1 ชั่วโมงตามค่าเริ่มต้น
5. **ตรวจสอบสิทธิ์ Sudoers ครั้งแรก**:
   - ในหน้า Popover เปิดสวิตช์ **Lid-closed Support**
   - สังเกตหน้าต่างขอรหัสผ่าน macOS Touch ID / Password จากระบบ
   - เมื่อกรอกรหัสผ่านผ่าน สวิตช์จะเปิดเป็นสีเขียว และแสดง Badge `"✓ Verified (Active)"`
6. **ตรวจสอบ Start at Login**:
   - เปิด Settings > เปิดสวิตช์ **Start Awake at Login**
   - ตรวจสอบว่ามี Badge `"✓ Verified (LaunchAgent)"` ปรากฏ
   - สั่ง Restart VM แล้วสังเกตว่า Awake เริ่มทำงานขึ้นบนเมนูบาร์อัตโนมัติ

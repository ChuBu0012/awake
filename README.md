# ⚡ Awake (Stickman Edition)

เครื่องมือป้องกัน Mac หลับขณะ AI Agents ทำงาน — มาพร้อมมาสคอต **Stickman** ตาโตขอบตาคล้ำสไตล์คนทำงานหนัก รองรับการพับจอ (Clamshell / Lid-closed mode) พร้อมเมนูบาร์ Native และคำสั่ง CLI

A clean, minimalist Native macOS Menu Bar utility and CLI companion to keep your Mac awake while AI Agents run (even with the lid closed).

Awake is developed in the open under the [MIT License](LICENSE). Contributions and bug reports are welcome. See [Contributing](CONTRIBUTING.md), [Support](SUPPORT.md), and [Security](SECURITY.md).

<p align="center">
  <img src="config/AppIcon_1024.png" width="140" alt="Awake Stickman Icon" style="border-radius: 28px; box-shadow: 0 10px 30px rgba(0,0,0,0.15);" />
</p>

---

## ✨ Features (จุดเด่น)

1. **มาสคอต Stickman น่ารัก ตลก และมีเอกลักษณ์**:
   - หน้าคนทำงานหนัก ตาโตเบิกกว้าง ขอบตาคล้ำแบบคนอดนอนรัน Agent ข้ามคืน
   - AppIcon ขาว-ดำ ลายเส้นหมึกคมชัดบนพื้นหลัง Squircle ขาวนวล
   - ไอคอนบนแถบ Menu Bar เปลี่ยนตามสถานะ: หน้าตาค้าง `( O_O )` เมื่อ Active และหลับตาพริ้ม `( -_- ) z` เมื่อ Inactive
2. **Clamshell / Lid-Closed Support**: ป้องกันเครื่องหลับเมื่อพับจอด้วย `sudo pmset -a disablesleep 1` + ป้องกัน kernel idle ด้วย `caffeinate`
3. **Menu Bar App กระชับ รวดเร็ว (`Awake.app`)**:
   - พัฒนาด้วย Swift (AppKit) แท้ๆ เบาเพียง 115 KB
   - เมนูคลีน เรียบง่าย ไม่มีเมนูรกตา:
     - ดูสถานะและเวลานับถอยหลัง
     - ปุ่ม Toggle Awake เปิด/ปิดทันที
     - ตัวเลือกตั้งเวลาล่วงหน้า (Duration Presets: Indefinite, 30m, 1h, 2h, 4h, 8h)
     - สลับเปิด/ปิด Battery Guard
4. **Battery & Thermal Guard**:
   - ตัดการทำงานอัตโนมัติหากแบตเตอรี่เหลือน้อยกว่า 20% ขณะใช้งานบนแบตเตอรี่ (ป้องกันเครื่องร้อนหรือแบตหมดในกระเป๋าเป้)
5. **One-Time Passwordless Sudo**:
   - ตั้งค่าสิทธิ์ผ่าน `sudoers` เพียงครั้งเดียว ปลอดภัยเฉพาะคำสั่ง `pmset -a disablesleep` ทำให้คลิกใน Menu Bar หรือพิมพ์ใน CLI ได้ทันทีโดยไม่ต้องเด้งถามรหัสผ่าน

---

## 🚀 Quick Start (เริ่มต้นใช้งาน)

**Requirements:** macOS 12 or later, Xcode Command Line Tools (for building), and administrator access for the one-time `pmset` setup. The app changes a system-wide sleep setting; use it only while needed and turn it off afterward to restore the prior setting.

### 1. Build และ Install
```bash
make install
```

### 2. ตั้งค่าสิทธิ์ครั้งแรก (One-time Setup)
เพื่อให้คลิกเปิด/ปิดใน Menu Bar และ Terminal ได้โดยไม่ต้องกรอกรหัสผ่านทุกครั้ง:
```bash
make setup
```

### 3. เปิดใช้งาน Menu Bar App
```bash
open ~/Applications/Awake.app
```
(หรือเปิดจาก Spotlight พิมพ์ `Awake`)

---

## 💻 CLI Commands (การใช้งานผ่าน Terminal)

| คำสั่ง | คำอธิบาย |
|---|---|
| `awake on [duration]` | เปิดโหมดห้ามหลับ (เช่น `awake on 30m`, `awake on 2h`, `awake on indefinite`) |
| `awake off` | ปิดโหมด คืนค่า sleep ปกติ |
| `awake status` | ดูสถานะปัจจุบัน เวลาที่เหลือ แหล่งพลังงาน และแบตเตอรี่ |
| `awake run <command...>` | รันคำสั่งพร้อมเปิด awake อัตโนมัติ และปิดทันทีเมื่องานเสร็จ |
| `awake setup` | ตั้งค่า sudoers rule ปลอดภัย |
| `awake help` | แสดงคู่มือการใช้งานคำสั่ง |

---

## 🛡️ การถอนการติดตั้ง (Uninstall)
```bash
make uninstall
```

## 🌱 Open Source

- [Contributing guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security policy](SECURITY.md)
- [Support](SUPPORT.md)
- [Changelog](CHANGELOG.md)
- [Git workflow](docs/GIT_WORKFLOW.md)
- [GitHub repository setup checklist](docs/GITHUB_SETUP.md)

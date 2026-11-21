# ⚡ Awake (Stickman Edition)

เครื่องมือป้องกัน Mac หลับขณะ AI Agents ทำงาน — มาพร้อมมาสคอต **Stickman** ตาโตขอบตาคล้ำสไตล์คนทำงานหนัก รองรับการพับจอ (Clamshell / Lid-closed mode) พร้อมเมนูบาร์ Native และคำสั่ง CLI

A clean, minimalist Native macOS Menu Bar utility and CLI companion to keep your Mac awake while AI Agents run (even with the lid closed).

Awake is developed in the open under the [MIT License](LICENSE). Contributions and bug reports are welcome. See [Contributing](CONTRIBUTING.md), [Support](SUPPORT.md), and [Security](SECURITY.md).

<p align="center">
  <img src="config/AppIcon_1024.png" width="140" alt="Awake Stickman Icon" style="border-radius: 28px; box-shadow: 0 10px 30px rgba(0,0,0,0.15);" />
</p>

---

## ✨ Features (จุดเด่น)

1. **Local automation**: enable rules for selected apps, exact work process names, and weekly schedules. Rules run on this Mac while the menu bar app is open.
2. **One arbitration engine**: CLI and menu bar app share a private, locked state file; Manual On, Activity, Schedule, Snooze, Battery Guard, and `awake run` follow the same rules.
3. **Scoped sleep prevention**: idle prevention uses per-request `caffeinate`; optional lid-closed support uses the narrowly scoped `pmset` sudoers rules and restores the value Awake captured.
4. **Menu bar controls**: choose a duration, add/pause/remove automation rules, see active requests, and toggle Battery Guard.

---

## 🚀 Quick Start (เริ่มต้นใช้งาน)

**Requirements:** macOS 12 or later. Building from source requires Go 1.26 and Xcode Command Line Tools. Administrator access is only needed for optional lid-closed support. Idle-sleep prevention uses a per-request `caffeinate` assertion; the optional lid layer changes the system-wide `pmset` setting and restores the captured prior value.

### 1. Build และ Install
```bash
make install
```

### 2. เปิดใช้ Lid-Closed Support (ตัวเลือก)
การป้องกันการหลับตามปกติไม่ต้องใช้ `sudo` การตั้งค่านี้เพิ่มกฎ sudoers แบบจำกัดเพื่อรองรับการพับจอ:
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
| `awake on [duration]` | เปิดคำขอ Manual On (เช่น `awake on 30m`, `awake on 2h`, `awake on indefinite`) |
| `awake off` | ปิด Manual On และพัก Activity/Schedule 30 นาที; คำขอ `awake run` ยังทำงานต่อ |
| `awake status [--json]` | ดูสถานะ แหล่งคำขอ Battery Guard และ recovery state |
| `awake run <command...>` | รันคำสั่งเป็น argument array พร้อม assertion ของตัวเอง และล้างเฉพาะ lease นี้เมื่อจบ |
| `awake rule ...` | เพิ่ม/เปิด/ปิดกฎ Activity และ Schedule |
| `awake set battery-guard\|lid-support on\|off` | ตั้งค่า guard หรือเลือกเปิด lid-closed layer |
| `awake setup` | ตั้งค่า sudoers เฉพาะ `pmset -a disablesleep 0|1` |
| `awake recover` | กู้คืน stale leases และค่าระบบที่ Awake บันทึกไว้ |
| `awake help` | แสดงคู่มือการใช้งานคำสั่ง |

Schedules use local time and selected start weekdays. For example, `fri 22:00 02:00` runs from Friday night through Saturday at 02:00. Automation evaluation stops when the menu bar app quits; explicit `awake run` requests continue independently.

---

## 🛡️ การถอนการติดตั้ง (Uninstall)
```bash
make uninstall
```
คำสั่งนี้คืนค่า setting ที่ Awake เป็นเจ้าของก่อนลบไฟล์ หากยังมี `awake run` ทำงานอยู่จะหยุดไว้ก่อน ให้คำสั่งนั้นจบแล้วค่อยลองใหม่ หากต้องการถอน sudoers rule ด้วยตนเอง ให้ตรวจไฟล์ก่อนแล้วรัน:
```bash
sudo visudo -c
sudo rm -f /etc/sudoers.d/awake /etc/sudoers.d/mac-awake
sudo visudo -c
```

## 🌱 Open Source

- [Contributing guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security policy](SECURITY.md)
- [Support](SUPPORT.md)
- [Changelog](CHANGELOG.md)
- [Git workflow](docs/GIT_WORKFLOW.md)
- [GitHub repository setup checklist](docs/GITHUB_SETUP.md)

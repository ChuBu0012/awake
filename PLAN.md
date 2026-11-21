# PLAN.md — แผนปรับปรุง Awake (macOS, Open Source, ไม่มีค่าใช้จ่าย)

อัปเดตล่าสุด: 2026-11-22
ขอบเขต: macOS เท่านั้น (ยังไม่รวม Linux/Windows)

## เป้าหมาย

ทำให้ Awake เป็นโปรเจค open source ที่คนอื่น **ติดตั้งได้ ไว้ใจได้ และ contribute ได้** โดยไม่ต้องจ่ายเงิน
(ไม่ใช้ Apple Developer Program, ใช้ GitHub Actions แบบฟรีสำหรับ public repo)

## หลักการ

- ความปลอดภัยของเครื่องผู้ใช้มาก่อนฟีเจอร์: ต้องคืนค่า `SleepDisabled` เสมอ
- ไม่เพิ่ม network, telemetry หรือคำสั่งที่ต้องใช้สิทธิ์เพิ่ม (ตาม AGENTS.md)
- หนึ่ง branch ต่อหนึ่งเรื่อง, commit เล็กและมีจุดประสงค์เดียว (ตาม `docs/GIT_WORKFLOW.md`)
- ไม่อ้างว่า "ตรวจแล้ว" ถ้ายังไม่ได้รันคำสั่งตรวจจริง

## ข้อจำกัดเรื่อง "ไม่เสียเงิน" ที่ต้องยอมรับ

| เรื่อง | ผลกระทบ | แนวทาง |
|---|---|---|
| ไม่มี Developer ID → sign/notarize ไม่ได้ | `.dmg` ที่ดาวน์โหลดจะถูก Gatekeeper บล็อก | แจก **วิธี build จากโค้ด** เป็นทางหลัก, ให้ `.dmg` เป็นทางเลือกพร้อมคำอธิบายชัดเจน, ใช้ ad-hoc signing (`codesign -s -`) ให้ bundle สอดคล้องกัน |
| ไม่เข้า Homebrew core cask ได้ง่าย | Homebrew เข้มงวดกับ cask ที่ไม่ notarize (ต้องตรวจนโยบายปัจจุบันก่อนทำ) | ทำ **tap ของตัวเอง** ที่ build จาก source (formula) เพราะไฟล์ที่ build บนเครื่องผู้ใช้ไม่ติด quarantine |
| ไม่มีเครื่อง Intel / macOS หลายเวอร์ชันฟรี | ทดสอบหลายสภาพแวดล้อมยาก | ใช้ GitHub-hosted macOS runner (ฟรีสำหรับ public repo) + เปิดให้ผู้ใช้รายงานผลบน Intel |

---

## Phase 0 — เก็บงานค้างให้เป็นระเบียบ (ทำก่อนอย่างอื่น)

ปัญหา: มีการแก้ 13 ไฟล์ (~+1,100/−335 บรรทัด) ค้างอยู่บน `main` ซึ่งขัดกับ git workflow

- [ ] สร้าง branch ใหม่จากสถานะปัจจุบัน แล้วแยก commit ตามเรื่อง:
  1. Go engine/domain/store/cli (+ tests)
  2. Swift popover model/view
  3. Swift Settings
  4. `Makefile` + `scripts/clean-run.sh`
  5. เอกสาร
- [ ] ไม่ commit `AGENTS.md` และ `.agents/` (ตรวจ `.gitignore` ว่าครอบคลุม `.agents/`)
- [ ] ก่อน commit แต่ละก้อนให้รัน `make test` และบันทึกผลจริง

**เสร็จเมื่อ:** `git status` สะอาด, `main` ไม่มีงานค้าง, `make test` ผ่าน

## Phase 1 — ทำให้เอกสารตรงกับโค้ด

| ที่ | ปัญหา | แก้ |
|---|---|---|
| `README.md` | ยังพูดถึง "Get Started Wizard" ที่ถูกลบแล้ว (commit d064546) | ลบหัวข้อ wizard, อธิบายการตั้งค่าครั้งแรกตามที่เป็นจริง |
| `project.md` | Stage 4 ยังบอกว่ามี wizard; ระบุ grace period 2 นาทีแต่โค้ดตัดออก | อัปเดตสถานะและ decisions |
| `internal/domain/evaluate.go` | คอมเมนต์ว่า grace period ถูกเอาออก "ชั่วคราวเพื่อทดสอบ" | **ตัดสินใจ**: คืน grace period หรือเปลี่ยน spec ให้เป็น "ปล่อยทันที" แล้วแก้ทั้งโค้ดและเอกสารให้ตรงกัน |
| `AGENTS.md` (local) | เรียกว่า Bash CLI ทั้งที่ตอนนี้เป็น Go | แก้เฉพาะในเครื่อง ห้าม commit |
| `README.md` | ภาษาปนไทย/อังกฤษไม่สม่ำเสมอ | แยก `README.md` (อังกฤษ, สำหรับ contributor ทั่วโลก) และ `README.th.md` |

**เสร็จเมื่อ:** อ่าน README แล้วทำตามได้จริงบนเครื่องสะอาด

## Phase 2 — ความน่าเชื่อถือของการ "พับจอแล้วไม่หลับ" (สำคัญที่สุด)

ความเสี่ยง: ถ้าแอปโดน kill/crash/ไฟดับ ค่า `SleepDisabled=1` จะค้างจนกว่าจะเปิดแอปหรือ CLI อีกครั้ง
เครื่องที่อยู่ในกระเป๋าอาจร้อนและแบตหมด โดยไม่ต้องเพิ่ม daemon ที่มีสิทธิ์สูง:

- [ ] ให้แอปเรียก `Recover` อัตโนมัติทุกครั้งที่เปิด (เงียบ ไม่ถามผู้ใช้ ถ้าไม่มี lease ที่ active)
- [ ] แสดง warning ใน popover เมื่อพบ `SleepDisabled=1` ที่ Awake เป็นผู้ตั้ง แต่ไม่มี lease active พร้อมปุ่ม "Restore"
- [ ] ให้ `awake status` แสดงสถานะนี้ชัดเจน (และ `--json` มี field สำหรับสคริปต์)
- [ ] เพิ่มเทสใน `internal/engine` สำหรับ: crash กลางคัน, ค่าถูกเปลี่ยนจากภายนอก, baseline หาย
- [ ] เขียน `docs/RECOVERY.md`: คำสั่งกู้คืนด้วยมือ (`awake recover`, และ `sudo pmset -a disablesleep 0` เป็นทางสุดท้าย)
- [ ] ทดสอบด้วยมือบนเครื่องจริง: พับจอ ทั้งเสียบสายและใช้แบต, kill แอปด้วย `kill -9`, แล้วดูว่า recover ได้

**เสร็จเมื่อ:** kill -9 ระหว่างโหมดพับจอ แล้วเปิดแอป/CLI ใหม่ ค่า `SleepDisabled` กลับเป็นค่าเดิมโดยอัตโนมัติ และมีเทสครอบคลุม

## Phase 3 — CI ฟรีบน GitHub Actions

- [ ] `.github/workflows/ci.yml` บน `macos-latest` (และ macOS เวอร์ชันเก่ากว่าถ้ามี runner ให้ใช้)
  - `bash -n` สคริปต์ทั้งหมด
  - `go test ./...` และ `go vet ./...`
  - `./scripts/test-swift-status.sh`
  - `make build` และ `scripts/verify-macos-target.sh` (ยืนยัน minimum macOS 12)
- [ ] pin เวอร์ชัน Go ให้ตรงกับ Makefile (`go1.26.4`)
- [ ] เพิ่ม `govulncheck` (ฟรี) เป็น job แยก
- [ ] ใส่ badge ใน README
- [ ] เปิด branch protection ให้ `main` ต้องผ่าน CI

**เสร็จเมื่อ:** PR ที่ทำให้เทสพังถูกบล็อกอัตโนมัติ

## Phase 4 — ลดภาระการดูแลโค้ด

- [ ] แบ่ง `src/AwakeSettingsView.swift` (1,473 บรรทัด) ตามแท็บ (General / Automations / About) เป็นไฟล์ย่อย
  - ทำเป็น commit แยกที่ **ไม่เปลี่ยนพฤติกรรม** เพื่อ review ง่าย
- [ ] เพิ่มเทสให้ `AwakePopoverModel` (ตอนนี้ Swift tests ครอบคลุมแค่ `AwakeStatus`)
  - ทำให้ตัวเรียก CLI เป็น protocol เพื่อ mock ได้
- [ ] ทำ `scripts/clean-run.sh` ให้ปลอดภัยขึ้น: ถามยืนยันก่อนลบ หรือต้องมี `--yes`, และจำกัด path ที่ลบให้แคบลง (ตอนนี้ลบ `/tmp/awake*` แบบ glob กว้าง)
- [ ] ตรวจว่า `bin/awake` (wrapper) ยังจำเป็นหรือไม่เมื่อมี binary ที่ build แล้ว ถ้าไม่จำเป็นให้ลบเพื่อลดความสับสน

## Phase 5 — การแจกจ่ายโดยไม่ต้องจ่ายเงิน

ลำดับความสำคัญ:

1. **Build จาก source (ทางหลัก)** — `make install` ใช้ได้อยู่แล้ว
   - เขียนส่วน "Requirements / Install / Uninstall" ใน README ให้ชัดว่าต้องมี Go + Xcode Command Line Tools
2. **Homebrew tap ของตัวเอง (ทางที่สอง)** — repo `homebrew-awake` ที่มี formula build จาก source
   - ตรวจนโยบาย Homebrew ปัจจุบันก่อนลงมือ ไม่แน่ใจว่าแบบไหนยังรองรับ
3. **`.dmg` / `.zip` ใน GitHub Releases (ทางเลือก)** — สร้างด้วย Actions
   - ใช้ ad-hoc signing
   - ใส่ **SHA-256 checksum** ทุก release และตั้ง `permissions` ของ workflow ให้น้อยที่สุด
   - เขียนวิธีเปิดแอปที่ไม่ได้ notarize ให้ตรงตามจริงของ macOS แต่ละเวอร์ชัน (คลิกขวา → Open หรือ System Settings → Privacy & Security → Open Anyway) **หลังทดสอบจริงแล้วเท่านั้น**
   - ระบุใน README ตรงๆ ว่า build นี้ไม่ได้ notarize และเหตุผล
4. **Universal build (arm64 + x86_64)** — ตรวจว่า `swiftc` + `go build` สร้างทั้งสอง arch ได้ แล้ว `lipo` รวม; ถ้าทดสอบ Intel ไม่ได้ ให้ระบุว่า "ยังไม่ทดสอบบน Intel"

**ไม่ทำ:** จ่ายค่า Apple Developer Program (ไม่ตรงข้อจำกัด) — ถ้ามีผู้สนับสนุนในอนาคตค่อยเพิ่ม notarization

## Phase 6 — ความโปร่งใส & ความปลอดภัยในกระเป๋า (User Visibility & Backpack Safety)

เป้าหมาย: ทำให้ผู้ใช้รู้เสมอว่าทำไมเครื่องไม่หลับ และพับจอใส่กระเป๋าได้อย่างมั่นใจ 100% ว่าเครื่องจะไม่ร้อนจนพัง

- [ ] **Reason Header ใน Popover**:
  - บรรทัดบนสุดของ Popover แสดงเหตุผลเด่นชัดเสมอ:
    - *ขณะตื่น*: `"🟢 ตื่นอยู่เพราะ: [ชื่อ Task / Agent] (รันมาแล้ว X นาที)"` หรือ `"🟢 ตื่นอยู่เพราะ: Manual On (เหลือ Y นาที)"`
    - *ขณะหลับปกติ*: `"⚪ สภาพปกติ: เครื่องจะหลับตามที่ macOS กำหนด (ไม่มีงานที่รันค้าง)"`
- [ ] **Notification เมื่องานเสร็จสิ้น (Completion Alert)**:
  - ส่ง Native macOS Notification อัตโนมัติเมื่องานจบ:
    > 🔔 **Awake: งานเสร็จสิ้นแล้ว**
    > *[ชื่อ Task] ทำงานเสร็จและเข้าสู่โหมด Idle แล้ว — Awake คืนค่าการนอนหลับตามปกติ*
  - แจ้งเตือนเสมอ ไม่ต้องมี toggle ให้ผู้ใช้ต้องคิดมาก
- [ ] **Thermal Guard (ป้องกันเครื่องร้อนจัดในกระเป๋า)**:
  - สังเกต `ProcessInfo.processInfo.thermalState`
  - หากอุณหภูมิเครื่องเข้าสู่ระดับ `.serious` หรือ `.critical` ให้ตัด sleep prevention ทันที และคืนค่า `pmset -a disablesleep 0` เพื่อให้เครื่องหลับและระบายความร้อน
  - แสดงสถานะใน Popover: `"🟠 Paused by Thermal Guard (Mac temperature is high)"`
- [ ] **Max Clamshell Timeout on Battery (เพดาน 2 ชั่วโมงเมื่อพับจอบนแบต)**:
  - ขณะเสียบสายชาร์จ (AC Power): ทำงานได้ไม่จำกัดเวลาตามที่งานต้องการ
  - ขณะใช้แบตเตอรี่ (Battery Power) และพับจอ: จำกัดเวลาสูงสุดไม่เกิน 2 ชั่วโมง (120 นาที) ป้องกันกรณีลืมหยิบออกจากกระเป๋าเป้
- [ ] **Silent Auto-Recovery (กู้คืนอัตโนมัติเมื่อเปิดแอป)**:
  - ตรวจสอบ `SleepDisabled` ตอนเปิดแอป/CLI เสมอ หากพบค่า `1` ค้างอยู่โดยไม่มี lease ที่ active ให้รีเซ็ตกลับเป็น `0` อัตโนมัติเงียบๆ

## Phase 7 — Smart Activity & ตรวจจับการทำงานจริง (Zero-Config Workload)

เป้าหมาย: เลิกให้ผู้ใช้กรอก PID หรือชื่อ process เอง และไม่เปิด Awake ค้างเพียงเพราะ "แอปเปิดอยู่"

- [ ] **Smart Activity Watcher (CPU-Aware Threshold)**:
  - ตรวจสอบ CPU Usage ของ Process แอปที่เป็น Agent หรือ Dev Tools
  - *เกณฑ์ตื่น*: CPU > 5% → Awake เข้าสู่สถานะ Active ทันที
  - *เกณฑ์ปล่อยหลับ (Hysteresis / Debounce)*: CPU < 5% **ต่อเนื่องกันอย่างน้อย 60 วินาที** (Sustained Idle) จึงปล่อยให้ Mac หลับ ป้องกันการตัดตอนรอเน็ตเวิร์ก/API
- [ ] **Zero-Input / Tap-to-Enable App Catalog**:
  - สแกนแอปที่ติดตั้งในเครื่องอัตโนมัติ (Cursor, VS Code, Docker, Xcode, Terminal ฯลฯ)
  - ผู้ใช้กดคลิกเดียวเพื่อเปิด/ปิดการเฝ้าดู ไม่ต้องพิมพ์ชื่อ process ไม่ต้องพิมพ์ PID
  - ปรับกฎ "App is open (regardless of activity)" ให้เป็นตัวเลือกรอง โดยมี Smart Activity เป็นค่าเริ่มต้น
- [ ] **One-Click Agent Hook Integration**:
  - เพิ่มคำสั่ง `awake hold <id> [--ttl 30m]` และ `awake release <id>` ใน CLI
  - รองรับการต่อเข้ากับ Claude Code hooks (`SessionStart`, `SessionEnd`) เพื่อให้ Agent รัน Awake เองอัตโนมัติหลังบ้านโดยผู้ใช้ไม่ต้องสั่งคำสั่งนำหน้า

---

## ลำดับแนะนำและขนาดงาน

| ลำดับ | Phase | ขนาด | เหตุผล |
|---|---|---|---|
| 1 | 0 เก็บงานค้าง | เล็ก | ฐานต้องสะอาดก่อน |
| 2 | 1 เอกสาร | เล็ก | แก้ความสับสนทันที |
| 3 | 3 CI | เล็ก–กลาง | ต้นทุนต่ำ ป้องกัน regression |
| 4 | 2 recovery | กลาง | ความเสี่ยงต่อผู้ใช้สูงสุด |
| 5 | 4 refactor/เทส | กลาง | ทำหลังมี CI รองรับ |
| 6 | 5 การแจก | กลาง | ทำเมื่อ 1–4 นิ่ง |
| 7 | 6, 7 | ต่อเนื่อง | |

## เกณฑ์ก่อนประกาศเป็น public release (v0.1)

- [ ] `main` สะอาด และ CI ผ่านบน PR/`main`
- [ ] Recovery หลัง `kill -9` ผ่านทั้งเทสอัตโนมัติและทดสอบด้วยมือ
- [ ] README ตรงกับพฤติกรรมจริง ทุกคำสั่งในนั้นรันแล้ว
- [ ] วิธีติดตั้ง/ถอนการติดตั้งผ่านบนเครื่องสะอาด
- [ ] SECURITY.md, PRIVACY.md, RECOVERY.md พร้อม
- [ ] Release notes ระบุชัดว่าไม่ได้ notarize และระบุ macOS/arch ที่ทดสอบจริง

## คำถามที่ต้องตัดสินใจ

1. คืน grace period 2 นาทีหรือเปลี่ยน spec เป็น "ปล่อยทันที"?
2. ใช้ license MIT ต่อไปหรือไม่ (ปัจจุบันเป็น MIT)?
3. จะรองรับ Intel อย่างเป็นทางการหรือไม่ ถ้าไม่มีเครื่องทดสอบ?

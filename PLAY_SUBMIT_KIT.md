# 로그챌린지 — Google Play 등록 복붙 키트

> EXANSYS 조직 계정 · com.keywordream.keepup · v1.1.0 (versionCode 7)
> 최종 발행·약관동의·데이터보안/콘텐츠등급 선언은 반드시 본인이 클릭.

---

## 0) 업로드할 파일
| 용도 | 경로 |
|---|---|
| **앱 번들(AAB)** | `E:\app\LogChallenge-1.1.0-release.aab` |
| 앱 아이콘 512 | `E:\app\keepup\store_assets\icon_512.png` |
| 피처 그래픽 1024×500 | `E:\app\keepup\store_assets\screenshots\00_feature_graphic.png` |
| 스크린샷 5장 | `E:\app\keepup\store_assets\screenshots\01_home.png ~ 05_alarm.png` |
| 개인정보처리방침 URL | `https://log.keywordream.com/privacy` |

---

## 1) 앱 이름 / 제목  (30자 이내)
```
로그챌린지 - 습관 인증 챌린지
```
- "습관"+"챌린지" 포함 → **습관챌린지 검색 노출**

## 2) 짧은 설명  (80자 이내)
```
매일 습관을 사진·타이머로 인증하고 도장으로 남기는 습관 챌린지. 마감 전 알림이 놓치지 않게 붙잡아줘요.
```

## 3) 전체 설명  (복붙)
```
미루면 사라지는 습관, 도장으로 붙잡으세요.

로그챌린지(Log Challenge)는 매일의 습관을 사진·타이머·녹음·영상으로 인증하고,
인증할 때마다 도장을 찍어 기록으로 남기는 습관 인증 챌린지 앱입니다.
계정도, 서버도 없습니다. 모든 기록은 오직 내 폰 안에만 저장돼요.

■ 이런 분께
· 작심삼일을 끝내고 진짜 습관을 만들고 싶은 분
· 운동·독서·공부·명상·기상 등 루틴을 꾸준히 인증하고 싶은 분
· 습관 챌린지 모임에서 매일 인증(도장)을 남기는 분

■ 핵심 기능
· 사진 인증 + 날짜·시각 자동 워터마크 — 조작 걱정 없는 인증
· 다양한 인증 방식 — 사진 / 타이머(달리기·명상) / 녹음 / 영상 / 링크
· 마감 3시간·1시간·30분 전 알림 — 인증하면 그날 알림 자동 취소
· 도장 달력 — 달성률·최장 연속 기록을 한눈에
· 적립형(매일 쌓기) · 결과형(목표 선언 후 주기별 인증) 루틴
· 66일(9주) 시즌 — 습관이 몸에 붙는 기간을 기록으로

■ 습관 · 루틴 · 기록을 한 앱에서
habit tracker, 루틴 관리, 습관 형성, 매일 인증, 도장 챌린지, 63일/66일 습관.

내 습관을 자랑스럽게 인증하고 기록하세요. 로그챌린지.
```

---

## 4) 데이터 보안(Data safety) 설문 — 답
- **데이터를 수집/공유합니까?** → **아니요 (수집 안 함)**
  - 근거: 사진·영상·녹음·메모·루틴은 **기기 내에만 저장**, 서버로 전송 안 함 = Google 정의상 "수집" 아님.
- 위치/개인정보/금융정보 등 → 전부 **아니요**
- (웹 성과 게시판은 별개 서비스라 앱 데이터 보안과 무관)

## 5) 콘텐츠 등급 설문(IARC) — 답
- 폭력·성적 콘텐츠·욕설·도박·약물 → **전부 없음** → 결과 **전체이용가(만 3세)**
- 사용자 간 소통/공유 있음? → 앱 자체는 없음(공유는 OS 공유 시트) → 해당 없음/아니요

## 6) 기타 설정
- **카테고리**: 건강/피트니스 (또는 생산성)
- **타겟 연령층**: 만 13세 이상 (아동 대상 아님)
- **광고 포함**: 아니요
- **국가/지역**: 대한민국 (필요시 전체)

---

## ⚠️ 7) 함정 — 미리 대비
1. **정확한 알람(SCHEDULE_EXACT_ALARM) 권한 선언**
   - 이 앱은 "마감 전 정확한 알림"이 핵심이라 정확한 알람 권한을 씁니다.
   - Play Console이 **"정확한 알람 사용 이유"** 선언을 요구할 수 있음 → **"작업/이벤트 정시 알림(사용자가 설정한 습관 마감 리마인더)"** 사유로 정당하게 통과.
2. **카메라·마이크·사진/미디어 권한** — 사용 이유: "습관 인증 사진·영상·음성 촬영(기기 내 저장)". 데이터 보안에선 "수집"으로 표시하지 않음(전송 안 하므로).
3. **앱 서명**: 업로드하면 Google Play 앱 서명이 적용됨. 우리가 만든 keystore는 **업로드 키**로 계속 사용 → keystore/백업 절대 분실 금지 (`E:\app\keepup_keystore_backup`).
4. **프로덕션 직행**: 조직 계정이라 비공개 테스트 의무는 없음. 단 첫 제출은 **검토(수일)** 후 공개.

---

## 9) 영어권(글로벌) 등록정보 — 미리 준비
> 글로벌 출시 시 Play Console에서 **영어(미국)** 언어를 추가하고 아래 붙여넣기.
> 개인정보처리방침·약관은 이미 `log.keywordream.com/privacy` (우측 상단 **EN 토글**)로 영어 제공됨.

**App name / Title** (≤30 chars)
```
Log Challenge - Habit Tracker
```

**Short description** (≤80 chars)
```
Verify daily habits with a photo or timer, stamp your streak, never miss a deadline.
```

**Full description**
```
Beat procrastination — stamp your habits into a record you can be proud of.

Log Challenge is a habit-verification challenge app. Prove each habit with a photo,
timer, voice recording, or video, and earn a stamp every time you check in.
No account, no server — everything stays only on your device.

■ Made for
· Anyone who wants to break "3-day resolutions" and build habits that stick
· Exercise, reading, study, meditation, early rising and other daily routines
· Habit-challenge groups that log a daily check-in (stamp)

■ Key features
· Photo verification with an automatic date/time watermark — tamper-proof proof
· Multiple ways to verify — photo / timer (running, meditation) / voice / video / link
· Reminders 3 hours, 1 hour, and 30 minutes before the deadline — auto-cancel once you check in
· Stamp calendar — see your completion rate and longest streak at a glance
· Two routine types — Daily (build up every day) and Goal (declare a target, verify per cycle)
· 66-day (9-week) seasons — the time a habit takes to stick, kept as a record

A habit tracker, routine builder, and daily log in one app.
Verify your habits proudly and keep the record. Log Challenge.
```

---

## 8) 진행 순서 (요약)
1. 앱 만들기 → 이름 `로그챌린지` → 무료/앱 선택
2. 대시보드의 설정 작업들: 개인정보처리방침 URL, 광고 없음, 콘텐츠 등급, 타겟층, 데이터 보안 → 위 답 입력
3. 프로덕션 → 새 버전 만들기 → **AAB 업로드**
4. 스토어 등록정보: 제목/짧은설명/전체설명(위 복붙) + 아이콘·피처그래픽·스크린샷 첨부
5. 검토 후 **출시** 클릭 (본인)
```
```

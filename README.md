# 습관 챌린지 (혼자 쓰는 인증 앱) — MVP

적립형/결과형 습관을 선언하고, 사진+메모로 인증하며, **마감 3시간 전부터 로컬 알림**으로
스스로를 강제하는 개인용 Flutter 앱. 서버·계정 없이 폰 안에서만 돌아갑니다.

## 기능
- 루틴 선언: **적립형**(매일/주6일) · **결과형**(매주 일요일 목표 인증)
- 사진 인증 → **날짜·시각 자동 워터마크**
- **마감 3시간 / 1시간 / 30분 전 알림** (인증하면 그날 알림 자동 취소)
- **공유 버튼** — 인증을 OS 공유 시트로 카카오톡 오픈채팅방 등에 직접 공유 (합법·안전)
- 인증 사진 앨범(기록·추억)
- 로컬 저장(SharedPreferences + 앱 문서 폴더)

---

## 실행 방법

> 이 폴더에는 `lib/`, `pubspec.yaml`만 들어있습니다.
> 플랫폼 폴더(android/ios)는 아래 명령으로 생성한 뒤, 설정을 추가하세요.

```bash
# 1) 이 폴더에서 플랫폼 폴더 생성 (기존 lib/pubspec은 유지됨)
flutter create .

# 2) 패키지 설치
flutter pub get

# 3) 폰 연결 후 실행
flutter run
```

Flutter SDK **3.22 이상**이 필요합니다. 없으면 https://docs.flutter.dev/get-started/install 참고.
(`flutter --version`으로 확인, 낮으면 `flutter upgrade`)

---

## ⚠️ 필수 플랫폼 설정 (안 하면 알림/카메라 동작 안 함)

### Android — `android/app/src/main/AndroidManifest.xml`

`<manifest>` 안, `<application>` **위**에 권한 추가:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
```

`<application>` **안**에 리시버 추가(기기 재부팅 후에도 알림 유지):

```xml
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
    </intent-filter>
</receiver>
```

### Android — `android/app/build.gradle`

`flutter_local_notifications`는 **코어 라이브러리 디슈가링**이 필요합니다.
`android { }` 안에 추가:

```gradle
compileOptions {
    coreLibraryDesugaringEnabled true
    sourceCompatibility JavaVersion.VERSION_1_8
    targetCompatibility JavaVersion.VERSION_1_8
}
```

파일 맨 아래 `dependencies { }`에 추가:

```gradle
dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.2'
}
```

`minSdkVersion`은 21 이상으로 설정하세요.

### iOS — `ios/Runner/Info.plist`

`<dict>` 안에 카메라·사진 권한 설명 추가:

```xml
<key>NSCameraUsageDescription</key>
<string>습관 인증 사진 촬영에 사용됩니다.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>습관 인증 사진 선택에 사용됩니다.</string>
```

---

## 카카오톡 공유 방식 (중요)

앱이 카톡방에 **자동 전송하는 것은 카카오 정책상 불가**합니다. 대신 이 앱은
**공유 버튼**을 제공합니다. 인증 후(또는 기록 앨범에서) 공유를 누르면 OS 공유 시트가 열리고,
카카오톡 → 원하는 오픈채팅방을 직접 골라 전송하면 됩니다. 워터마크 찍힌 사진과
인증 글이 함께 채워집니다. 이 방식은 공식 공유 기능이라 **약관 위반·정지 위험이 없습니다.**

- 흐름: 알림 → 인증(사진+메모) → 공유 버튼 → 카톡 방 선택 → 전송
- 마지막 전송은 본인이 직접 누릅니다(완전 자동 아님).
- 카톡은 사진+글 동시 공유 시, 방에 따라 글이 캡션으로 붙거나 별도로 갈 수 있습니다.

---

## 알림 동작 방식 & 한계

- 앱은 서버 없이 **미래의 의무일 알림을 미리 예약**합니다. 인증하거나 앱을 열면
  현재 상태에 맞춰 전체 재예약(reconcile)합니다.
- iOS는 앱당 **대기 알림 64개 제한**이 있어, 예약을 60개로 캡했습니다.
  루틴이 많아지면 먼 미래 알림 일부가 빠질 수 있습니다(가까운 날짜 우선).
- Android는 배터리 최적화가 정확 알람을 지연시킬 수 있습니다.
  실제 사용 시 설정에서 이 앱을 **배터리 최적화 예외**로 두면 정확합니다.
- 정시 알람(exact alarm)은 Android 12+에서 사용자 허용이 필요할 수 있습니다.
  앱 첫 실행 시 권한 요청이 뜹니다.

---

## 다음에 붙이면 좋은 것 (2단계)
- 시즌 기간(예: 7/13~9/13) 설정 + 종료 시 회고 카드
- 미인증 통계/달성률 화면, 자율 벌금 계산
- 루틴 변경 찬스 UI (로직은 `AppState.changeRoutine`에 이미 있음)
- 알림 시각/간격 사용자 커스터마이즈

## 구조
```
lib/
  main.dart                  앱 진입, 타임존/알림/저장소 초기화, 루트 네비게이션
  app_state.dart             전역 상태(루틴·인증) + 저장/알림 동기화
  theme.dart                 Material 3 테마
  models/routine.dart        Routine/Certification 모델 + 의무일 판정
  services/
    storage_service.dart     로컬 저장(JSON)
    notification_service.dart 마감 전 알림 예약/재동기화
    watermark_service.dart   사진 날짜 워터마크
    share_service.dart       OS 공유 시트로 인증 공유(카톡 등)
  screens/
    home_screen.dart         오늘의 습관 + 상태/카운트다운
    add_routine_screen.dart  루틴 선언
    certify_screen.dart      사진 인증
    history_screen.dart      기록·추억 앨범
```

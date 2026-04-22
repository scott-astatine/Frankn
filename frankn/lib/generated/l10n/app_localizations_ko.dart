// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => '도히';

  @override
  String get neuralDeck => '신경 데크';

  @override
  String get systemOperations => '시스템 작업';

  @override
  String get fileBrowser => '파일 브라우저';

  @override
  String get terminal => '터미널';

  @override
  String get processes => '프로세스';

  @override
  String get sysLog => '시스템 로그';

  @override
  String get liveLog => '라이브 로그';

  @override
  String get activeMonitors => '활성 모니터';

  @override
  String get fetching => '가져오는 중...';

  @override
  String get syncing => '동기화 중...';

  @override
  String get linked => '연결됨';

  @override
  String get error => '오류';

  @override
  String get offline => '오프라인';

  @override
  String get cpu => 'CPU';

  @override
  String get ram => 'RAM';

  @override
  String get ping => '핑';

  @override
  String get neuralLinks => '신경 링크';

  @override
  String get publicDiscovery => '공개 검색';

  @override
  String get noPersistentLinks => '고정 링크 없음';

  @override
  String get noAdditionalTargets => '추가 대상 없음';

  @override
  String get addManualTarget => '수동 대상 추가';

  @override
  String get uplinkSecurity => '업링크 보안';

  @override
  String get enterPasscode => '비밀번호 입력';

  @override
  String get cancel => '취소';

  @override
  String get establish => '연결';

  @override
  String get disconnect => '연결 해제';

  @override
  String get disconnectLink => '링크 해제';

  @override
  String get adminOverride => '관리자 오버라이드';

  @override
  String get serviceManagement => '서비스 관리';

  @override
  String get restartSvc => '서비스 재시작';

  @override
  String get sysUpdate => '시스템 업데이트';

  @override
  String get powerState => '전원 상태';

  @override
  String get lockHost => '호스트 잠금';

  @override
  String get unlockHost => '호스트 잠금 해제';

  @override
  String get reboot => '재부팅';

  @override
  String get shutdown => '종료';

  @override
  String get criticalIntent => '중요한 작업';

  @override
  String executeRemoteCommand(String command) {
    return '원격 $command 명령을 실행하시겠습니까? 현재 신경 링크가 종료됩니다.';
  }

  @override
  String get abort => '중단';

  @override
  String get confirm => '확인';

  @override
  String get status => '상태';

  @override
  String get memory => '메모리';

  @override
  String get affinity => '선호도';

  @override
  String get cmdPath => '명령 경로';

  @override
  String get killProcess => '프로세스 종료';

  @override
  String get terminateIntent => '작업 종료';

  @override
  String killProcessConfirm(String pid) {
    return '프로세스 $pid를 종료하시겠습니까? 시스템이 불안정해질 수 있습니다.';
  }

  @override
  String get noDataFound => '데이터를 찾을 수 없음';

  @override
  String get directory => '디렉토리';

  @override
  String get download => '다운로드';

  @override
  String get edit => '편집';

  @override
  String get delete => '삭제';

  @override
  String get intentHandler => '작업 핸들러';

  @override
  String get audioMatrix => '오디오 매트릭스';

  @override
  String get vol => '볼륨';

  @override
  String get close => '닫기';

  @override
  String get settings => '설정';

  @override
  String get neuralLinkConfiguration => '신경 링크 설정';

  @override
  String get signalingServer => '시그널링 서버';

  @override
  String get lastConnectedHost => '마지막 연결된 호스트';

  @override
  String get uiPreferences => 'UI 기본 설정';

  @override
  String get language => '언어';

  @override
  String get terminalFontSize => '터미널 글꼴 크기';

  @override
  String get colorScheme => '색상 구성표';

  @override
  String get appReset => '앱 초기화';

  @override
  String get clearAllData => '모든 데이터 지우기';

  @override
  String get newNeuralLink => '새 신경 링크';

  @override
  String get visualHash => '시각적 해시 (QR)';

  @override
  String get tapToScan => '탭하여 스캔';

  @override
  String get orManual => '또는 수동 입력';

  @override
  String get hostId => '호스트 ID';

  @override
  String get aliasOptional => '별칭 (선택 사항)';

  @override
  String get initialize => '초기화';

  @override
  String get root => '루트';

  @override
  String get sortByName => '이름순 정렬';

  @override
  String get sortBySize => '크기순 정렬';

  @override
  String get sortByDate => '날짜순 정렬';

  @override
  String get selected => '선택됨';

  @override
  String get filterProcesses => '프로세스 필터링...';
}

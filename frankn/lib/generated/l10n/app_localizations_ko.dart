// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => '도회';

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
  String get generalConfig => '일반 설정';

  @override
  String get storageSync => '스토리지 동기화';

  @override
  String get manageDir => '디렉터리 관리';

  @override
  String get hostAlias => '호스트 별칭';

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
  String get search => '검색';

  @override
  String get trackpadSensitivity => '트랙패드 민감도';

  @override
  String get trackpad => '트랙패드';

  @override
  String get filterProcesses => '프로세스 필터...';

  @override
  String get terminate => '종료';

  @override
  String get folderSynchronization => '폴더 동기화';

  @override
  String get folderSyncComplete => '폴더 동기화 완료';

  @override
  String get folderSyncCompleteNoChanges => '폴더 동기화 완료: 변경 사항 없음';

  @override
  String get fullStorageAccessRequired => '전체 저장소 액세스 권한 필요';

  @override
  String get establishNewLink => '새 링크 설정';

  @override
  String get modifyLink => '링크 수정';

  @override
  String get localDir => '로컬 디렉터리';

  @override
  String get notSelected => '선택되지 않음';

  @override
  String get remoteDir => '원격 디렉터리';

  @override
  String get syncStrategy => '동기화 전략';

  @override
  String get bidirectionalMirror => '양방향 미러링';

  @override
  String get singleSourceBackup => '단일 소스 백업';

  @override
  String get clientIsSourceLabel => '클라이언트가 소스임';

  @override
  String get syncInterval => '동기화 간격';

  @override
  String everyNMinutes(int minutes) {
    return '$minutes분마다';
  }

  @override
  String get everyHour => '매 시간';

  @override
  String get every6Hours => '6시간마다';

  @override
  String get onceADay => '하루에 한 번';

  @override
  String get update => '업데이트';

  @override
  String get localEndpoint => '로컬 엔드포인트';

  @override
  String get remoteEndpoint => '원격 엔드포인트';

  @override
  String get mirror => '미러';

  @override
  String get backup => '백업';

  @override
  String lastSyncedLabel(String time) {
    return '마지막 동기화: $time';
  }

  @override
  String get triggerSyncNow => '지금 동기화 실행';

  @override
  String get noSyncPairsEstablished => '설정된 동기화 쌍이 없음';

  @override
  String get inSync => '동기화됨';

  @override
  String changesPending(int count) {
    return '$count개의 변경 사항 대기 중';
  }

  @override
  String get verifying => '확인 중...';

  @override
  String get english => '영어';

  @override
  String get korean => '한국어';

  @override
  String pixels(int size) {
    return '$size PX';
  }

  @override
  String multiplier(double value) {
    return '${value}X 배율';
  }

  @override
  String multiplierValue(double value) {
    return '${value}X';
  }

  @override
  String get renameHost => '호스트 이름 변경';

  @override
  String get reinitializingNeuralLink => '새 서버로 신경 링크 재설정 중...';

  @override
  String get invalidUrlFormat => '잘못된 URL 형식입니다. ws:// 또는 wss://로 시작해야 합니다.';

  @override
  String get defaultLlm => '기본 LLM';

  @override
  String get unknown => '알 수 없음';

  @override
  String get notSet => '설정되지 않음';

  @override
  String get uiDefaults => 'UI 기본 설정';

  @override
  String get criticalReset => '위험한 초기화';

  @override
  String get terminateConfigsConfirm => '모든 고정 링크와 시스템 설정을 종료하시겠습니까?';

  @override
  String get execute => '실행';

  @override
  String get forgetIntents => '작업 무시';

  @override
  String get noMediaPlaying => '재생 중인 미디어 없음';

  @override
  String get idle => '대기 중';

  @override
  String get idleInstance => '유휴 인스턴스';

  @override
  String get doheeChat => '도희 채팅';

  @override
  String get unknownArtist => '알 수 없는 아티스트';

  @override
  String get bluetoothDevices => '블루투스 장치';

  @override
  String get noDevicesFound => '장치를 찾을 수 없음';

  @override
  String get wifiNetworks => '와이파이 네트워크';

  @override
  String get noNetworksFound => '네트워크를 찾을 수 없음';

  @override
  String connectToSsid(String ssid) {
    return '$ssid에 연결';
  }

  @override
  String get password => '비밀번호';

  @override
  String get neuralModelVault => '신경 모델 보관소';

  @override
  String get scanningVault => '보관소 스캔 중...';

  @override
  String get noModelsFound => '호스트 보관소 디렉터리에서 .gguf 모델을 찾을 수 없습니다.';

  @override
  String get connectivityAudio => '연결 및 오디오';

  @override
  String criticalAction(String action) {
    return '위험 // $action';
  }

  @override
  String get remoteCommandConfirm => '이 원격 명령을 실행하시겠습니까?';

  @override
  String get scanning => '스캔 중...';

  @override
  String get connected => '연결됨';

  @override
  String get importFromImage => '이미지에서 가져오기';

  @override
  String get hostIdHint => '예: 550e8400-e29b...';

  @override
  String get aliasHint => '예: 작업-컴퓨터';

  @override
  String get defaultDownloadDir => '기본 다운로드 디렉터리';

  @override
  String get chooseOnDownload => '다운로드 시 선택';

  @override
  String get downloadFolder => '다운로드 폴더';

  @override
  String get noDefaultFolderConfigured =>
      '아직 기본 다운로드 폴더가 설정되지 않았습니다. 첫 다운로드 시 자동으로 설정되거나 아래에서 선택할 수 있습니다.';

  @override
  String currentFolder(String folderPath) {
    return '현재 폴더: $folderPath\n\n이 폴더를 지우거나 새로운 폴더를 선택하시겠습니까?';
  }

  @override
  String get clearDefault => '기본값 지우기';

  @override
  String get chooseFolder => '폴더 선택';

  @override
  String get saveAs => '다른 이름으로 저장';
}

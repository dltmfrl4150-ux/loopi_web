/// Complete Terms of Service and Privacy Policy copy (KO primary, EN secondary).
///
/// The text published before the 2026-10-13 revision is kept at
/// docs/legal/legal_texts_snapshot_20261013.dart. Counsel must review before
/// production publication. Unknown operator details are left unspecified.
class LegalTexts {
  LegalTexts._();

  static bool _isEn(String? languageCode) => languageCode == 'en';

  static String termsTitle(String? languageCode) =>
      _isEn(languageCode) ? 'Terms of Service' : '이용약관';

  static String privacyTitle(String? languageCode) =>
      _isEn(languageCode) ? 'Privacy Policy' : '개인정보처리방침';

  static String termsOfServiceBody(String? languageCode) =>
      _isEn(languageCode) ? _termsEn : _termsKo;

  static String privacyPolicyBody(String? languageCode) =>
      _isEn(languageCode) ? _privacyEn : _privacyKo;

  // ---------------------------------------------------------------------------
  // 이용약관 (한국어 · 전문)
  // ---------------------------------------------------------------------------
  static const String _termsKo = '''
Loopi 이용약관

본 약관은 Loopi 서비스(이하 "서비스")의 이용과 관련하여 운영자와 이용자 간의 권리·의무 및 책임사항을 규정합니다. 현재 운영자는 사업자등록 전의 개인이며, 법인명·대표자·주소는 이 약관에 적지 않습니다. 아래 "회사"는 그 개인 운영자를 가리킵니다. 서비스는 현재 무료로 제공됩니다. 서비스를 이용함으로써 이용자는 본 약관에 동의한 것으로 간주됩니다.

제1조 (목적)
본 약관은 회사가 제공하는 서비스의 이용조건 및 절차, 회사와 이용자의 권리·의무·책임사항, 기타 필요한 사항을 규정함을 목적으로 합니다.

제2조 (정의)
① "서비스"란 회사가 제공하는 YouTube 등 외부 콘텐츠 기반 구간 반복 연습, 루틴 저장, 연습 녹화·비교, 커뮤니티·클래스·쇼케이스 등 일체의 기능을 의미합니다.
② "이용자"란 본 약관에 동의하고 서비스를 이용하는 회원 및 비회원(게스트)을 말합니다.
③ "유료 콘텐츠"란 인앱 결제, 구독, 클래스 수강 등 유상으로 제공되는 디지털 콘텐츠·기능을 말합니다.
④ "이용자 콘텐츠"란 이용자가 서비스에 업로드·게시·공유하는 영상, 텍스트, 루틴, 쇼케이스, 프로필 정보 등을 말합니다.
⑤ "로컬 데이터"란 이용자 기기 또는 브라우저의 저장소·캐시에 저장되는 연습 영상·임시 파일·설정 등을 말합니다.
⑥ 이용자는 자신의 기기 및 소셜 로그인 계정(Google, Kakao, Apple 등)의 보안을 유지할 책임이 있습니다. 이용자의 기기 분실, 계정 관리 소홀, 타인에게 양도·대여하여 발생한 불이익 및 부정 결제에 대해 회사는 고의 또는 중과실이 없는 한 책임을 지지 않습니다.

제3조 (약관의 효력 및 변경)
① 본 약관은 서비스 화면 게시를 통해 효력이 발생합니다.
② 회사는 관련 법령을 위반하지 않는 범위에서 약관을 개정할 수 있으며, 변경 시 적용일자 및 개정 사유를 명시하여 서비스 내 공지합니다.
③ 이용자에게 불리한 중요 변경은 시행일 전에 서비스 내 공지로 알립니다. 이용자는 그 변경에 동의하지 않으면 시행일 전에 이용을 중단할 수 있습니다. 서비스를 계속 이용한다는 사실만으로, 이용자의 법정 권리를 줄이는 변경에 동의한 것으로 보지 않습니다. 앱은 탈퇴 요청과 복구 요청을 기록할 수 있습니다. 30일이 지난 뒤 서버에서 계정을 지우는 작업은 배포되어 실행 중이지 않습니다.
④ 본 약관에서 정하지 않은 사항은 관련 법령 및 일반적인 상관례에 따릅니다.

제4조 (무료 서비스의 AS-IS 제공 및 보증의 부인)
① 회사는 무료로 제공되는 서비스의 완전무결성, 특정 목적에의 적합성, 오류·중단 없는 운영, 보안의 절대성을 보증하지 않습니다.
② 관련 법령이 허용하는 한도 내에서 서비스는 "있는 그대로(AS-IS)" 및 "이용 가능한 상태로(AS AVAILABLE)" 제공됩니다.
③ 이용자 기기의 운영체제(OS) 오류, 브라우저 캐시·데이터 삭제, 저장 공간 부족, 기기 분실·교체, 네트워크 불안정, 이용자 부주의로 인하여 로컬 기기에 보관된 영상·루틴·설정 데이터가 유실·손상·재생 불가한 경우, 회사는 고의 또는 중과실이 없는 한 책임을 지지 않습니다.
④ 회사는 서비스 개선, 점검, 장애 대응을 위해 사전 또는 사후 공지 후 서비스의 전부 또는 일부를 일시 중단·변경할 수 있습니다.

제5조 (유료 기능)
① 이 약관이 반영된 앱에는 결제 시스템, 앱 마켓 결제, 자동 갱신 구독, 영수증 검증이 연결되어 있지 않습니다. 이용 등급 화면의 요금제 버튼은 결제수단으로 대금을 청구하지 않으며, 화면에 표시되는 결제 수단 문구는 실제 결제 내역이 아닙니다.
② 사업자등록과 유료 결제 도입은 2027년 4월 이후로 계획되어 있습니다. 그 계획은 현재 판매 중인 유료 계약이 아니며, 가격·결제 주기·청약철회는 실제로 결제를 열기 전에 별도로 고지합니다.
③ 유료 결제가 도입된 뒤 미성년자가 법정대리인의 동의 없이 결제한 경우, 미성년자 또는 법정대리인은 관련 법령에 따라 취소를 청구할 수 있습니다. 미성년자가 속임수로 성년자이거나 법정대리인의 동의가 있는 것으로 믿게 한 경우에는 취소가 제한될 수 있습니다.

제6조 (YouTube 및 제3자 API·콘텐츠에 관한 면책)
① 서비스는 YouTube 등 제3자가 제공하는 API, SDK, 임베드 플레이어, 링크를 통해 외부 콘텐츠에 접근할 수 있습니다. 해당 콘텐츠의 소유권·저작권·이용 가능 여부는 제3자 또는 원권리자에게 있습니다.
② 회사는 YouTube 등 제3자 플랫폼의 약관·정책 변경, API 중단·제한, 재생 불가, 지역 차단, 계정 제재, 네트워크 장애로 인한 기능 저하 또는 서비스 중단에 대해, 고의 또는 중과실이 없는 한 책임을 지지 않습니다.
③ 이용자는 YouTube 이용약관(https://www.youtube.com/t/terms) 및 Google 정책 등 제3자 약관을 준수할 책임이 있으며, 위반으로 인한 분쟁·손해는 이용자가 부담합니다.
④ 회사는 제3자 콘텐츠의 정확성, 적법성, 지속 가용성, 음원·안무·영상의 권리 관계를 보증하지 않습니다.

제7조 (이용자 콘텐츠, 저작권 및 면책·보상)
① 이용자 콘텐츠에 대한 권리와 책임은 원칙적으로 해당 이용자에게 있습니다. 이용자는 타인의 저작권·초상권·상표권·개인정보 등 권리를 침해하는 콘텐츠를 업로드·게시해서는 안 됩니다.
② 이용자가 쇼케이스·커뮤니티 등 공개 기능에 콘텐츠를 게시하면, 회사는 그 콘텐츠를 서비스 안에서 저장·전송·재생·전시하고 재생에 필요한 형식(화질, 길이, 썸네일)으로 바꾸는 비독점적·무상의 이용 허락을 받습니다. 서비스 밖 광고나 홍보물에 쓰는 허락은 게시만으로 생기지 않으며, 별도의 동의가 있는 경우에 한합니다.
③ 이용자는 자신이 게시한 콘텐츠로 인하여 회사 또는 제3자에게 손해가 발생한 경우, 관련 법령이 허용하는 범위에서 이를 배상하고 회사를 면책하여야 합니다.
④ 회사는 법령 위반, 권리 침해 또는 서비스 운영 방해가 확인되거나 합리적으로 의심되는 콘텐츠의 공개를 제한하거나 삭제할 수 있습니다. 현재 앱에는 이용자 신고를 접수하는 화면이 연결되어 있지 않습니다. 신고를 받을 방법, 처리 결과의 통지, 이의 절차는 운영자가 그 채널을 정한 뒤 서비스에 안내합니다.
⑤ 연습 기능 이용 과정에서 기기에 생성되는 로컬 녹화물은 이용자가 명시적으로 업로드·공유를 요청하지 않는 한 회사 중앙 서버로 자동 전송되지 않으며, 그 보관·삭제에 대한 1차 책임은 이용자에게 있습니다.
⑥ 이용자가 매크로, 크롤링, 비정상적인 방법으로 트래픽을 유발하여 회사에 운영상 손해를 끼친 경우, 회사는 계정 이용을 제한하고 관련 법령에 따라 책임을 물을 수 있습니다. 결제 우회에 대한 조치는 결제 기능이 도입된 뒤에만 적용됩니다.

제7조의2 (계정 종료, 공개 게시물, 연령)
① 앱은 탈퇴 요청을 비공개 계정 문서에 기록하고, 같은 로그인 방식의 계정이면 서버 삭제가 시작되기 전에 복구할 수 있습니다. 익명 게스트는 로그아웃하면 같은 계정으로 돌아올 수 없습니다. 30일이 지난 뒤 개인 계정, 개인 보관함, 쇼케이스 문서와 파일을 지우고 공개 루틴의 작성자를 "탈퇴한 회원"으로 바꾸는 예약 작업은 저장소의 서버 코드로만 존재합니다. 그 작업은 Firebase에 배포되어 있지 않으며 시행 중인 삭제 절차가 아닙니다. 배포 전에는 요청과 복구만 기록되고 서버의 보관함과 쇼케이스는 자동으로 지워지지 않습니다.
② 이용자는 자신이 공개한 커뮤니티 루틴 문서를 서비스 안에서 삭제할 수 있습니다. 본인 쇼케이스를 삭제할 때는 그 문서가 가리키는 본인 Storage 경로의 파일도 지우도록 되어 있습니다. 공개 루틴 본문은 계정 문서와 별도로 저장됩니다. 작성자 익명화는 위 예약 작업이 배포되어 실행될 때 적용되며, 지금은 실행되지 않습니다.
③ 앱은 생년월일과 보호자 정보를 수집하지 않습니다. Google, Apple, Kakao 로그인은 나이 또는 법정대리인 동의 여부를 앱에 넘기지 않습니다. 만 14세 미만은 보호자 확인 절차가 없어 가입을 진행하지 않습니다. 만 14세 이상 선택은 본인 선언이며 신원 확인이 아닙니다. 법정대리인 동의 절차는 구현되어 있지 않으며 시행 중인 동의 절차가 아닙니다. 공개 게시물을 신고하거나 운영자가 계정을 정지하는 화면도 없습니다.

제8조 (책임의 제한 및 손해배상 한도)
① 회사는 천재지변, 전쟁, 기간통신사업자의 서비스 중지, 해킹·DDoS 등 회사의 합리적 통제 범위를 넘는 사유로 인한 서비스 장애에 대해 책임을 지지 않습니다.
② 회사는 이용자 간 또는 이용자와 제3자 간에 서비스를 매개로 발생한 분쟁에 개입할 의무가 없으며, 이로 인한 손해에 대해 고의 또는 중과실이 없는 한 책임을 지지 않습니다.
③ 회사의 고의 또는 중대한 과실로 발생한 손해, 이용자의 생명·신체에 관한 손해, 개인정보 보호 관련 법령상 책임에는 계약으로 정한 배상 한도를 적용하지 않습니다. 그 밖의 손해는 관련 법령이 허용하는 범위에서 통상손해를 기준으로 배상합니다. 무료로만 이용한 경우에도 회사의 고의·과실로 인한 배상 책임이 면제되지 않습니다.
④ 회사는 간접손해, 특별손해, 결과적 손해, 일실이익, 데이터 복구 비용에 대해, 그 발생 가능성을 사전에 고지받았더라도 고의 또는 중과실이 없는 한 책임을 지지 않습니다.
⑤ 본 조의 책임 제한은 관련 강행법규가 금지하는 범위에서는 적용되지 않습니다.

제9조 (준거법 및 관할)
① 본 약관은 대한민국 법을 준거법으로 합니다. 이용자에게 적용되는 강행법규는 이 조항으로 배제되지 않습니다.
② 회사와 이용자 사이의 소송 관할은 민사소송법 등 관련 법령이 정한 바에 따릅니다. 소비자인 이용자에게 불리한 전속 관할 합의는 적용하지 않습니다.

부칙
본 약관은 게시일로부터 시행합니다.
''';

  // ---------------------------------------------------------------------------
  // 개인정보처리방침 (한국어 · 전문)
  // ---------------------------------------------------------------------------
  static const String _privacyKo = '''
Loopi 개인정보처리방침

Loopi("회사")는 「개인정보 보호법」 등 관련 법령을 준수하며, 이용자의 개인정보를 보호하고 이와 관련한 고충을 신속·원활하게 처리하기 위하여 다음과 같이 개인정보처리방침을 수립·공개합니다. 현재 운영자는 사업자등록 전의 개인이고 서비스는 무료입니다. 개인정보 보호책임자의 성명과 연락처, 관리용 이메일 주소는 아직 이 방침에 적지 않습니다.

1. 수집하는 개인정보 항목
회사는 서비스 제공을 위해 다음 정보를 수집할 수 있습니다.
① 계정·인증 정보: Firebase Authentication의 고유 식별자(UID), 로그인 제공자(Google, Apple, Kakao, 익명 게스트), 제공되는 경우의 이메일, 닉네임, 프로필 이미지 URL
② 서비스 이용 정보: 이용자가 저장한 루틴·폴더·즐겨찾기, 공개한 커뮤니티 루틴과 쇼케이스
③ 기기·접속 정보: 서비스 실행에 따라 브라우저 또는 기기가 처리하는 정보가 있을 수 있습니다. 현재 앱 의존성에는 별도의 분석 또는 오류 수집 SDK가 포함되어 있지 않으며, 회사가 진단 로그를 서버에 수집하는 기능은 코드에서 확인되지 않았습니다.
④ 결제 정보: 현재 버전은 카드번호, 거래 식별자, 스토어 영수증을 수집·저장하지 않습니다. 이용 등급 화면의 결제 수단 문구는 결제 기록이 아닙니다.
⑤ 이용자가 직접 입력·업로드한 정보: 닉네임, 프로필 이미지, 공개 루틴, 공개 쇼케이스 영상·음성. 클래스 목록은 앱에 포함된 자료로 표시될 수 있으며, 수강 결제 기록은 코드에서 확인되지 않았습니다.
⑥ 회사는 이용자의 안면 인식 데이터, 홍채, 지문 등 법령상 특별한 보호가 필요한 생체인식 정보를 수집·식별·분석하지 않습니다. 이용자가 저장한 댄스 영상은 미디어 파일로 다루며, 특정 개인을 식별하는 생체 정보로 사용하지 않습니다.
⑦ 연령: 생년월일, 보호자 이름, 보호자 연락처는 수집하지 않습니다. 로그인 제공자는 앱에 나이를 제공하지 않습니다. 만 14세 이상이라는 본인 선언과 그 시각만 비공개 계정 문서에 기록할 수 있습니다. 이것은 법정대리인 동의 확인이 아닙니다.

2. 개인정보의 수집·이용 목적
회사는 수집한 개인정보를 다음 목적으로 이용합니다.
① 회원 식별, 로그인·인증, 계정 관리 및 부정 이용 방지
② 루틴 연습, 구간 반복, 커뮤니티·클래스·쇼케이스 등 서비스 제공 및 맞춤 기능 제공
③ 서비스 제공에 필요한 안내. 앱 안에 고객 문의 화면은 연결되어 있지 않습니다.
④ 유료 결제가 도입되기 전까지 결제·영수증 검증 목적으로 개인정보를 수집하지 않습니다.
⑤ 코드에서 확인된 범위의 서비스 제공. 별도의 통계·오류 수집 SDK는 확인되지 않았습니다.
⑥ 관련 법령상 의무 이행

3. 로컬 미디어 저장·처리 원칙
① 회사는 연습 기능 제공 시 이용자의 로컬 저장 공간(브라우저 캐시 및 기기 스토리지)을 활용하여 영상을 일시 재생 및 보관할 수 있습니다.
② 이용자가 직접 업로드(쇼케이스 등록, 클라우드 저장, 공유 등)를 요청하지 않은 연습 녹화·임시 미디어 데이터는 회사의 중앙 서버로 자동 전송되지 않습니다.
③ 로컬에 저장된 미디어는 이용자 기기·브라우저의 저장 공간 정책, OS/브라우저의 캐시 삭제, 앱 삭제, 기기 분실 등에 따라 삭제되거나 복구가 불가능할 수 있으며, 회사는 고의 또는 중과실이 없는 한 이에 대한 복원 의무를 부담하지 않습니다.
④ 이용자가 공개·업로드를 선택한 콘텐츠에 한해 서비스 제공에 필요한 범위에서 서버에 저장·전송될 수 있습니다.

4. 개인정보의 보유 및 이용 기간
① 회사는 개인정보 수집·이용 목적이 달성된 후에는 지체 없이 해당 정보를 파기합니다. 다만, 관련 법령에 따라 보존할 필요가 있는 경우 아래 기간 동안 보관합니다.
  - 계약 또는 청약철회 등에 관한 기록: 5년 (전자상거래 등에서의 소비자보호에 관한 법률)
  - 대금결제 및 재화 등의 공급에 관한 기록: 5년 (전자상거래 등에서의 소비자보호에 관한 법률)
  - 소비자의 불만 또는 분쟁처리에 관한 기록: 3년 (전자상거래 등에서의 소비자보호에 관한 법률)
  - 접속에 관한 기록: 3개월 이상 (통신비밀보호법 등 관련 법령이 정한 기간)
② 앱은 탈퇴 요청과 복구 요청을 기록할 수 있습니다. 30일 뒤 계정·개인 보관함·쇼케이스를 지우고 공개 루틴 작성자를 익명으로 바꾸는 예약 작업은 배포되어 실행되지 않습니다. 그 작업이 배포되어 실행되기 전에는 30일 복구 후 자동 삭제를 시행 중인 정책으로 보지 않습니다. 삭제 요청을 받을 연락 방법은 아직 정하지 않았습니다.
③ 로컬 기기에만 존재하는 데이터는 이용자가 직접 삭제하거나 앱/브라우저 데이터를 제거하여 관리합니다.

5. 제3자 제공 및 처리위탁(클라우드 등)
① 회사는 이용자의 동의 없이 개인정보를 제3자에게 제공하지 않습니다. 다만, 법령에 근거한 요청이 있거나 이용자가 명시적으로 동의한 경우는 예외로 합니다.
② 서비스 제공을 위해 다음 사업자의 기능을 사용합니다. 계약상 수탁자인지, 제3자 제공인지, 이용자가 그 사업자에게 직접 전송하는 것인지는 코드만으로 확정할 수 없는 항목이 있습니다.
  - Firebase Authentication, Cloud Firestore, Cloud Storage(Google): 로그인 식별, 계정 문서, 루틴 저장, 쇼케이스 파일, 프로필 이미지. 수탁 계약과 저장 리전은 확인이 필요합니다.
  - Google, Apple, Kakao: 이용자가 해당 로그인 화면에서 인증합니다. 게스트는 Firebase 익명 로그인을 사용합니다. 로그인 제공자가 자기 서비스에서 처리하는 정보는 회사의 위탁과 구분됩니다.
  - YouTube 임베드 플레이어: 이용자가 재생을 요청한 영상에 대해 브라우저가 YouTube에 접속합니다. 이것을 회사의 개인정보 제3자 제공으로 단정하지 않습니다.
  - 앱 마켓 결제 사업자: 현재 앱에 연결되어 있지 않습니다.
③ 위탁이 확인되면 회사는 관련 법령에 따라 안전성 확보에 필요한 조치를 요구하고, 수탁자·업무 내용이 바뀌면 본 방침에 반영합니다.
④ Firebase를 사용한다는 이유만으로 보관 국가를 특정 국가로 단정하지 않습니다. 이전 국가, 이전받는 자의 이름과 연락처, 이전 항목, 목적, 시기와 방법, 보유 기간, 거부 시 영향은 프로젝트 리전과 계약을 확인한 뒤에 본 방침에 적습니다. 확인 전에는 그 항목을 비워 둡니다.

6. 이용자의 권리
이용자는 관련 법령에 따라 다음과 같은 권리를 행사할 수 있습니다.
① 개인정보 열람, 정정·삭제, 처리 정지 요구
② 동의 철회 및 회원 탈퇴
③ 문의·고충 처리 요청
개인정보 보호책임자의 성명, 연락처, 주소는 아직 정해져 있지 않습니다. 현재 앱에는 그 문의로 연결되는 연락처가 없습니다. 운영자가 연락처를 정하면 본 방침과 서비스 화면에 게시합니다. 다른 이용자에게 공개되는 항목은 닉네임, 프로필 이미지, 이용자가 공개한 루틴·쇼케이스입니다.

7. 안전성 확보 조치 및 방침 변경
① 저장소의 보안 규칙은 계정 문서와 이메일을 로그인한 본인만 읽도록 두고, 닉네임과 프로필 이미지는 공개 프로필 문서에 둡니다. 공개 게시물과 쇼케이스 파일, 프로필 이미지는 규칙상 읽기가 열려 있습니다. 이 규칙이 실제 Firebase 프로젝트에 배포되었는지는 코드만으로 확인할 수 없습니다. 인터넷 환경에서 절대적 안전을 보장하지는 않습니다.
② 본 방침이 변경되는 경우 회사는 변경 내용과 시행 시점을 서비스 내에 고지합니다.
③ 본 방침과 개별 동의 내용이 충돌하는 경우, 관련 법령 및 개별 동의가 우선할 수 있습니다.

부칙
본 개인정보처리방침은 게시일로부터 시행합니다.
''';

  // ---------------------------------------------------------------------------
  // English (secondary · aligned coverage)
  // ---------------------------------------------------------------------------
  static const String _termsEn = '''
Loopi Terms of Service

These Terms govern use of the Loopi service ("Service"). The current operator is an individual before business registration. A corporate name, representative, and address are not stated here. "Company" means that individual operator. The Service is currently free. By using the Service, you agree to these Terms.

Article 1 (Purpose)
These Terms set out the conditions of use, procedures, and the rights, obligations, and responsibilities between the Company and users.

Article 2 (Definitions)
(1) "Service" means all features provided by the Company, including loop practice based on external content (e.g., YouTube), routine storage, practice recording/comparison, community, classes, and showcase.
(2) "User" means any member or guest who uses the Service under these Terms.
(3) "Paid Content" means paid digital features such as in-app purchases, subscriptions, or paid classes.
(4) "User Content" means videos, text, routines, showcases, profile data, and other materials uploaded or shared by users.
(5) "Local Data" means practice videos, temporary files, and settings stored on the user's device or browser storage/cache.
(6) Users are responsible for securing their devices and social login accounts (Google, Kakao, Apple, etc.). Except for willful misconduct or gross negligence, the Company is not liable for disadvantages or fraudulent payments arising from device loss, negligent account management, or transfer/lending of accounts to others.

Article 3 (Effect and Modification)
(1) These Terms take effect when posted in the Service.
(2) The Company may amend these Terms within the scope permitted by law, with notice of the effective date and reasons.
(3) Continued use after the effective date is not treated as consent to a change that reduces statutory rights. A change that materially disadvantages users will be announced in the Service before it takes effect, and users may stop using the Service before that date. The app can record a deletion request and a restore request. The server job that deletes an account after 30 days is not deployed and is not running.
(4) Matters not specified here follow applicable law and customary practice.

Article 4 (Free Service AS-IS Disclaimer)
(1) The Company does not warrant completeness, fitness for a particular purpose, uninterrupted operation, or absolute security of free Service features.
(2) To the extent permitted by law, the Service is provided "AS IS" and "AS AVAILABLE".
(3) The Company is not liable for loss or damage to Local Data caused by OS errors, browser cache/data deletion, insufficient storage, device loss/replacement, network instability, or user negligence, except in cases of willful misconduct or gross negligence.
(4) The Company may suspend or change all or part of the Service for improvement, maintenance, or incident response, with prior or subsequent notice.

Article 5 (Paid Features)
(1) This app has no payment system, app-store billing, auto-renewal, or receipt validation. Choosing a plan on the upgrade screen does not charge a payment method, and any payment-method text on that screen is not a payment record.
(2) Business registration and paid billing are planned for after April 2027. That plan is not a paid contract currently on sale. Price, billing period, and withdrawal terms will be disclosed before any payment is enabled.
(3) After paid billing is introduced, a minor or their legal representative may seek cancellation under applicable law if the minor paid without the legal representative's consent. Cancellation may be limited if the minor used deceit to appear to be an adult or to have that consent.

Article 6 (YouTube and Third-Party API Disclaimer)
(1) The Service may access external content via third-party APIs, SDKs, embedded players, or links. Ownership and rights remain with the third party or original rights holders.
(2) Except for willful misconduct or gross negligence, the Company is not liable for outages, API limits, playback failures, geo-blocks, account sanctions, or network issues caused by YouTube or other third parties.
(3) Users must comply with YouTube Terms of Service (https://www.youtube.com/t/terms) and other third-party policies; disputes arising from violations are the user's responsibility.
(4) The Company does not warrant the legality, accuracy, availability, or rights clearance of third-party content.

Article 7 (User Content, Copyright, and Indemnification)
(1) Rights and responsibility for User Content remain with the user. Users must not upload content that infringes others' copyrights, publicity rights, trademarks, or privacy.
(2) Posting to public features such as showcase or community grants the Company a non-exclusive, royalty-free license to store, transmit, play, and display that content inside the Service and to change format (quality, duration, thumbnail) as needed for playback. A license to use the content in advertising or promotion outside the Service is not granted by posting alone and requires separate consent.
(3) Users shall indemnify and hold the Company harmless from damages arising from their User Content to the extent permitted by law.
(4) The Company may restrict or remove content that violates law, infringes rights, or interferes with Service operation, when that is confirmed or reasonably suspected. This app has no screen that receives user reports. The reporting method, notice of the result, and an objection process will be announced after the operator designates that channel.
(5) Local practice recordings are not automatically uploaded to Company servers unless the user expressly requests upload/share; primary custody of Local Data rests with the user.
Article 7-2 (Account End, Public Posts, and Age)
(1) The app can record a deletion request on the private account document. The same sign-in method can restore the account until a server deletion job starts. An anonymous guest cannot return to the same account after sign-out. Code for a scheduled job that, 30 days later, deletes the personal account, private library, and showcase posts and files, and changes a public routine's author to "탈퇴한 회원", exists in the repository only. That job is not deployed to Firebase and is not an active deletion process. Until it is deployed, only the request and restore are recorded, and the server library and showcase are not deleted automatically.
(2) A user can delete their own public community routine documents in the Service. Deleting one's own showcase also deletes a Storage file when the document points at that user's own Storage path. The public routine body is stored separately from the account document. Author anonymization applies when the scheduled job above is deployed and runs. It does not run now.
(3) The app does not collect a date of birth or guardian details. Google, Apple, and Kakao sign-in do not provide age or guardian-consent status. Signup does not continue for users under 14 because guardian verification does not exist. Choosing 14 or older is a self-declaration, not an identity check. A legal-guardian consent process is not implemented and is not an active consent process. There is no screen that receives content reports or suspends an account.

Article 8 (Limitation of Liability and Damage Cap)
(1) The Company is not liable for failures beyond reasonable control (force majeure, carrier outages, hacking/DDoS, etc.).
(2) The Company has no duty to intervene in disputes between users or between a user and a third party, and is not liable therefor except for willful misconduct or gross negligence.
(3) A contractual damages cap does not apply to harm caused by the Company's intent or gross negligence, harm to life or body, or liability under privacy statutes. Other damages are compensated as ordinary damages to the extent the law allows. Using only free features does not waive liability for the Company's intent or negligence.
(4) Except for willful misconduct or gross negligence, the Company is not liable for indirect, special, consequential, lost profits, or data-recovery costs.
(5) These limitations do not apply where mandatory law prohibits them.

Article 9 (Governing Law and Venue)
(1) These Terms are governed by the laws of the Republic of Korea. Mandatory rules that protect the user are not displaced by this Article.
(2) Venue for a lawsuit between the Company and a user follows the jurisdiction statutes, including the Civil Procedure Act. An exclusive-venue clause that disadvantages a consumer user does not apply.

Supplementary Provision
These Terms take effect on the date of posting.
''';

  static const String _privacyEn = '''
Loopi Privacy Policy

Loopi ("Company") complies with applicable privacy laws and discloses this Privacy Policy to protect users' personal information. The current operator is an individual before business registration, and the Service is free. The privacy officer's name and contact, and any admin email address, are not stated in this Policy.

1. Personal Information Collected
The Company processes:
(1) Account data: Firebase Authentication UID, login provider (Google, Apple, Kakao, or anonymous guest), email if the provider supplies it, nickname, and profile image URL
(2) Service data: routines, folders, and favorites the user saves, plus community routines and showcase items the user publishes
(3) Device or browser data may be handled as the app runs. The app dependencies do not include a separate analytics or crash-reporting SDK, and no feature that uploads diagnostic logs to the Company's servers was found in the code
(4) Payments: this version does not collect or store card numbers, transaction IDs, or store receipts. Payment-method text on the plan screen is not a payment record
(5) Content the user submits: nickname, profile image, public routines, and public showcase video or audio. Class lists may be shown from data bundled with the app. Class payment records were not found in the code
(6) The Company does not collect, identify, or analyze sensitive biometric information specially protected by law (e.g., facial recognition data, iris, fingerprints). Dance videos stored by users are treated as ordinary media files and are not used as biometric data to identify a specific individual.
(7) Age: a date of birth, a guardian's name, and a guardian's contact are not collected. Login providers do not supply age. The private account document can store only a self-declaration of being 14 or older and the time of that declaration. That is not a check of legal-guardian consent.

2. Purpose of Collection and Use
(1) Identification, authentication, account management, and abuse prevention
(2) Providing practice, community, showcase, and related features that exist in the app
(3) Notices required to provide the Service. No in-app customer-inquiry screen is connected
(4) Until paid billing is introduced, personal information is not collected for payment or receipt validation
(5) Providing the Service within what the code implements. A separate statistics or error-collection SDK was not found
(6) Compliance with legal obligations

3. Local Media Storage Principle
(1) When providing practice features, the Company may use local storage (browser cache and device storage) to temporarily play and retain media.
(2) Practice recordings and temporary media that the user has not expressly chosen to upload (showcase, cloud save, share, etc.) are not automatically transmitted to the Company's central servers.
(3) Local media may be deleted or become unrecoverable due to OS/browser cache clearing, storage limits, app deletion, or device loss; except for willful misconduct or gross negligence, the Company has no duty to restore such data.
(4) Only content the user chooses to publish/upload may be stored/transmitted on servers as needed to provide the Service.

4. Retention Periods
(1) Personal information is destroyed without delay when the purpose is achieved, except where law requires retention, including:
  - Contracts/withdrawal records: 5 years (Korean e-commerce consumer protection law)
  - Payment/supply records: 5 years
  - Consumer complaint/dispute records: 3 years
  - Access logs: at least the period required by applicable communications secrecy / logging laws
(2) The app can record a deletion request and a restore request. The scheduled job that would delete the account, private library, and showcase after 30 days and anonymize public-routine authors is not deployed and does not run. Until that job is deployed and running, automatic deletion after a 30-day recovery window is not an active policy. The contact method for a deletion request is not fixed yet.
(3) Data existing only on the local device is managed by the user (delete files or clear app/browser data).

5. Third Parties and Cloud Consignment
(1) The Company does not provide personal information to third parties without consent, except as required by law or with explicit user consent.
(2) The Service uses the following. The code alone does not decide whether each relationship is consignment, a third-party disclosure, or a transfer the user makes directly to that provider.
  - Firebase Authentication, Cloud Firestore, and Cloud Storage (Google): sign-in identity, account documents, routine storage, showcase files, and profile images. The processing contract and storage region still need to be confirmed
  - Google, Apple, and Kakao: the user authenticates on that provider's sign-in screen. Guests use Firebase anonymous sign-in. Processing by the login provider in its own service is separate from the Company's consignment
  - YouTube embedded player: the browser contacts YouTube for a video the user asks to play. That is not asserted here to be the Company's third-party disclosure
  - App-store payment processors: not connected in this app
(3) If consignment is confirmed, the Company will require safeguards required by law and will update this Policy when the processor or the task changes.
(4) Using Firebase does not by itself establish that data is stored in a named country. The destination country, the recipient's name and contact, the items transferred, the purpose, the timing and method, the retention period, and the effect of refusal will be written here after the project region and the contract are confirmed. Until then those fields are left blank.

6. User Rights
Users may request access, correction, deletion, suspension of processing, withdrawal of consent, and account deletion under applicable law. The privacy officer's name, contact, and address are not yet designated. This app has no contact path that reaches that officer. Those details will be posted in this Policy and in the Service after the operator sets them. Other users can see the nickname, profile image, and routines or showcase items the user publishes.

7. Security Measures and Policy Changes
(1) The security rules in this repository let only the signed-in owner read the account document and email. Nickname and profile image live on a separate public profile. Public posts, showcase files, and profile images are readable under those rules. Whether these rules are deployed to the live Firebase project cannot be confirmed from the code alone. Absolute security on the Internet is not guaranteed.
(2) Material changes to this Policy will be announced in the Service with an effective date.
(3) Where this Policy conflicts with a specific consent, applicable law and the specific consent may prevail.

Supplementary Provision
This Privacy Policy takes effect on the date of posting.
''';
}

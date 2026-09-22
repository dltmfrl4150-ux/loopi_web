/// Complete Terms of Service and Privacy Policy copy (KO primary, EN secondary).
///
/// Intended for in-app dialogs. This is product legal copy for liability
/// protection; have counsel review before production publication.
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

본 약관은 Loopi(이하 "회사")가 제공하는 댄스·어학 연습 및 관련 부가 서비스(이하 "서비스")의 이용과 관련하여 회사와 이용자 간의 권리·의무 및 책임사항을 규정합니다. 서비스를 이용함으로써 이용자는 본 약관에 동의한 것으로 간주됩니다.

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
③ 이용자가 변경 약관 시행일 이후에도 서비스를 계속 이용하는 경우, 변경 약관에 동의한 것으로 봅니다. 동의하지 않는 경우 이용을 중단하고 탈퇴할 수 있습니다.
④ 본 약관에서 정하지 않은 사항은 관련 법령 및 일반적인 상관례에 따릅니다.

제4조 (무료 서비스의 AS-IS 제공 및 보증의 부인)
① 회사는 무료로 제공되는 서비스의 완전무결성, 특정 목적에의 적합성, 오류·중단 없는 운영, 보안의 절대성을 보증하지 않습니다.
② 관련 법령이 허용하는 한도 내에서 서비스는 "있는 그대로(AS-IS)" 및 "이용 가능한 상태로(AS AVAILABLE)" 제공됩니다.
③ 이용자 기기의 운영체제(OS) 오류, 브라우저 캐시·데이터 삭제, 저장 공간 부족, 기기 분실·교체, 네트워크 불안정, 이용자 부주의로 인하여 로컬 기기에 보관된 영상·루틴·설정 데이터가 유실·손상·재생 불가한 경우, 회사는 고의 또는 중과실이 없는 한 책임을 지지 않습니다.
④ 회사는 서비스 개선, 점검, 장애 대응을 위해 사전 또는 사후 공지 후 서비스의 전부 또는 일부를 일시 중단·변경할 수 있습니다.

제5조 (유료 콘텐츠 및 인앱 결제)
① 유료 콘텐츠의 가격, 이용 기간, 환불·청약철회 조건은 결제시점의 상품 안내, 스토어(Apple App Store, Google Play 등) 정책 및 관련 법령에 따릅니다.
② 인앱 결제는 각 앱 마켓 사업자를 통해 처리되며, 결제 오류·승인 지연·환불 절차는 해당 스토어 정책을 우선 적용합니다.
③ 이용자가 부정한 방법으로 결제를 하거나 유료 콘텐츠를 무단 복제·공유·재판매하는 경우, 회사는 이용 제한, 계약 해지 및 법적 조치를 취할 수 있습니다.
④ 무료 체험 종료 후 자동 갱신되는 구독이 있는 경우, 이용자는 스토어 설정에서 해지할 수 있으며, 해지 시점 이후의 요금 청구에 관한 책임은 스토어 정책에 따릅니다.
⑤ 디지털 콘텐츠의 특성상 제공이 개시된 이후에는 관련 법령이 허용하는 범위를 제외하고 청약철회가 제한될 수 있습니다.
⑥ 미성년자가 법정대리인의 동의 없이 유료 콘텐츠를 결제한 경우, 미성년자 본인 또는 법정대리인은 결제를 취소할 수 있습니다. 단, 미성년자가 속임수로써 성년자로 믿게 하거나 법정대리인의 동의가 있는 것으로 믿게 한 경우에는 취소가 제한됩니다. 인앱결제의 경우 결제 명의자(기기 소유자 또는 스토어 계정 명의자)를 기준으로 성년 여부를 판단합니다.

제6조 (YouTube 및 제3자 API·콘텐츠에 관한 면책)
① 서비스는 YouTube 등 제3자가 제공하는 API, SDK, 임베드 플레이어, 링크를 통해 외부 콘텐츠에 접근할 수 있습니다. 해당 콘텐츠의 소유권·저작권·이용 가능 여부는 제3자 또는 원권리자에게 있습니다.
② 회사는 YouTube 등 제3자 플랫폼의 약관·정책 변경, API 중단·제한, 재생 불가, 지역 차단, 계정 제재, 네트워크 장애로 인한 기능 저하 또는 서비스 중단에 대해, 고의 또는 중과실이 없는 한 책임을 지지 않습니다.
③ 이용자는 YouTube 이용약관(https://www.youtube.com/t/terms) 및 Google 정책 등 제3자 약관을 준수할 책임이 있으며, 위반으로 인한 분쟁·손해는 이용자가 부담합니다.
④ 회사는 제3자 콘텐츠의 정확성, 적법성, 지속 가용성, 음원·안무·영상의 권리 관계를 보증하지 않습니다.

제7조 (이용자 콘텐츠, 저작권 및 면책·보상)
① 이용자 콘텐츠에 대한 권리와 책임은 원칙적으로 해당 이용자에게 있습니다. 이용자는 타인의 저작권·초상권·상표권·개인정보 등 권리를 침해하는 콘텐츠를 업로드·게시해서는 안 됩니다.
② 이용자가 쇼케이스·커뮤니티·클래스 등 공개 기능에 콘텐츠를 게시하는 경우, 회사는 서비스 운영·홍보·개선을 위해 해당 콘텐츠를 복제·전송·전시·편집(형식 변경 포함)할 수 있는 비독점적·무상의 이용 허락을 부여받은 것으로 봅니다. 이용 허락의 범위는 서비스 제공에 필요한 한도로 제한됩니다.
③ 이용자는 자신이 게시한 콘텐츠로 인하여 회사 또는 제3자에게 손해가 발생한 경우, 관련 법령이 허용하는 범위에서 이를 배상하고 회사를 면책하여야 합니다.
④ 회사는 권리 침해 신고, 법령 위반, 서비스 운영 방해가 확인되거나 합리적으로 의심되는 콘텐츠를 사전 통지 없이 삭제·비공개·접근 제한할 수 있습니다.
⑤ 연습 기능 이용 과정에서 기기에 생성되는 로컬 녹화물은 이용자가 명시적으로 업로드·공유를 요청하지 않는 한 회사 중앙 서버로 자동 전송되지 않으며, 그 보관·삭제에 대한 1차 책임은 이용자에게 있습니다.
⑥ 이용자가 매크로, 크롤링, 비정상적인 방법(어뷰징)으로 트래픽을 유발하거나, 결제 시스템을 우회·악용하여 회사에 금전적·운영상 손해를 끼친 경우, 회사는 즉각적인 계정 영구 정지 및 민·형사상 손해배상을 청구할 수 있습니다.

제8조 (책임의 제한 및 손해배상 한도)
① 회사는 천재지변, 전쟁, 기간통신사업자의 서비스 중지, 해킹·DDoS 등 회사의 합리적 통제 범위를 넘는 사유로 인한 서비스 장애에 대해 책임을 지지 않습니다.
② 회사는 이용자 간 또는 이용자와 제3자 간에 서비스를 매개로 발생한 분쟁에 개입할 의무가 없으며, 이로 인한 손해에 대해 고의 또는 중과실이 없는 한 책임을 지지 않습니다.
③ 관련 법령이 허용하는 최대 한도 내에서, 회사의 손해배상 책임은 해당 손해가 발생한 직전 3개월 동안 이용자가 회사에 실제로 지급한 유료 이용 대금의 총액을 한도로 합니다. 무료 이용만 한 경우 회사의 금전적 배상 책임은 면제되거나 관련 법령이 정한 최소 한도로 제한됩니다.
④ 회사는 간접손해, 특별손해, 결과적 손해, 일실이익, 데이터 복구 비용에 대해, 그 발생 가능성을 사전에 고지받았더라도 고의 또는 중과실이 없는 한 책임을 지지 않습니다.
⑤ 본 조의 책임 제한은 관련 강행법규가 금지하는 범위에서는 적용되지 않습니다.

제9조 (준거법 및 전속 관할)
① 본 약관 및 서비스 이용에 관한 분쟁에는 대한민국 법을 준거법으로 하며, 국제사법 원칙이나 이용자의 거주 국가 법률에 우선하여 대한민국 법이 적용됩니다.
② 서비스 이용과 관련하여 회사와 이용자 간에 소송이 제기되는 경우, 민사소송법 등 관련 법령에 따른 관할 규정에도 불구하고, 회사 본사 소재지를 관할하는 법원을 제1심 전속 관할로 합니다. 다만, 관련 강행법규가 이용자에게 유리한 관할을 보장하는 경우에는 그 규정에 따릅니다.

부칙
본 약관은 게시일로부터 시행합니다.
''';

  // ---------------------------------------------------------------------------
  // 개인정보처리방침 (한국어 · 전문)
  // ---------------------------------------------------------------------------
  static const String _privacyKo = '''
Loopi 개인정보처리방침

Loopi(이하 "회사")는 「개인정보 보호법」 등 관련 법령을 준수하며, 이용자의 개인정보를 보호하고 이와 관련한 고충을 신속·원활하게 처리하기 위하여 다음과 같이 개인정보처리방침을 수립·공개합니다.

1. 수집하는 개인정보 항목
회사는 서비스 제공을 위해 다음 정보를 수집할 수 있습니다.
① 계정·인증 정보: 소셜 로그인(OAuth)을 통해 제공받는 고유 식별자(UID), 이메일 주소(제공되는 경우), 프로필 이름·닉네임, 프로필 이미지 URL(제공되는 경우), 로그인 제공자 유형
② 서비스 이용 정보: 루틴·폴더·즐겨찾기 등 이용자가 생성·저장한 설정 데이터, 커뮤니티·쇼케이스·클래스 이용 기록
③ 기기·로그 정보: 기기 종류, OS/브라우저 정보, 앱 버전, 접속 일시, 서비스 이용 기록, 오류·성능 로그(진단 목적)
④ 결제·거래 정보: 인앱 결제·구독 시 거래 식별자(Transaction ID), 상품 코드, 결제 상태, 스토어 영수증 검증에 필요한 최소 정보(카드번호 등 민감 결제수단 정보는 회사가 직접 저장하지 않으며 앱 마켓 사업자가 처리합니다)
⑤ 이용자가 자발적으로 입력·업로드한 정보: 문의 내용, 프로필 추가 정보, 공개 게시물
⑥ 회사는 이용자의 안면 인식 데이터, 홍채, 지문 등 법령상 특별한 보호가 필요한 '민감한 생체인식 정보'를 수집·식별·분석하지 않습니다. 이용자가 자발적으로 저장한 댄스 영상은 단순 미디어 파일로 취급되며, 회사는 이를 특정 개인을 식별하기 위한 생체 정보로 활용하거나 제3자에게 제공하지 않습니다.

2. 개인정보의 수집·이용 목적
회사는 수집한 개인정보를 다음 목적으로 이용합니다.
① 회원 식별, 로그인·인증, 계정 관리 및 부정 이용 방지
② 루틴 연습, 구간 반복, 커뮤니티·클래스·쇼케이스 등 서비스 제공 및 맞춤 기능 제공
③ 고객 문의 응대, 공지·약관 변경 안내, 서비스 관련 중요 고지
④ 유료 결제·구독 상태 확인, 영수증 검증, 환불·청약철회 처리 지원
⑤ 서비스 안정성 확보, 오류 분석, 보안 사고 대응, 이용 환경 개선 및 통계 분석(개인을 알아볼 수 없도록 가공한 형태 포함)
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
② 회원 탈퇴 시 회사가 서버에 보관한 계정 연계 정보는 지체 없이 삭제하거나 분리 보관하며, 법령상 보관이 필요한 항목만 해당 기간 동안 보관합니다.
③ 로컬 기기에만 존재하는 데이터는 이용자가 직접 삭제하거나 앱/브라우저 데이터를 제거하여 관리합니다.

5. 제3자 제공 및 처리위탁(클라우드 등)
① 회사는 이용자의 동의 없이 개인정보를 제3자에게 제공하지 않습니다. 다만, 법령에 근거한 요청이 있거나 이용자가 명시적으로 동의한 경우는 예외로 합니다.
② 원활한 서비스 제공을 위해 다음과 같이 처리 업무를 위탁할 수 있습니다.
  - 클라우드·백엔드 인프라(예: Firebase/Google Cloud 등): 인증, 데이터베이스, 파일 저장, 푸시·원격 설정 등
  - 앱 마켓·결제 사업자(Apple, Google 등): 인앱 결제·구독 처리 및 영수증 검증
  - 소셜 로그인 제공자(Kakao, Google, Apple 등): 계정 인증
  - YouTube/Google 등: 외부 영상 재생·API 연동(이용자가 선택한 콘텐츠 접근에 필요한 범위)
③ 위탁 시 회사는 관련 법령에 따라 안전성 확보에 필요한 조치를 요구하며, 위탁 내용이 변경되면 본 방침 또는 서비스 공지를 통해 안내합니다.
④ 회사는 글로벌 클라우드 서비스(예: Google Firebase)를 사용하고 있어, 데이터 백업 및 서비스 안정성을 위해 수집된 정보가 국외(예: 미국, 아시아 리전 등) 물리적 서버에 전송되어 보관될 수 있습니다. 국외 이전되는 정보는 본 방침에 명시된 보유 기간 동안 안전하게 보관되며 목적 달성 시 파기됩니다.

6. 이용자의 권리
이용자는 관련 법령에 따라 다음과 같은 권리를 행사할 수 있습니다.
① 개인정보 열람, 정정·삭제, 처리 정지 요구
② 동의 철회 및 회원 탈퇴
③ 문의·고충 처리 요청
회사는 법령이 정한 바에 따라 지체 없이 조치하며, 다른 법령에서 보관의무가 있는 경우에는 해당 범위에서 삭제가 제한될 수 있습니다. 권리 행사는 서비스 내 문의 기능 또는 회사가 안내하는 연락 채널을 통해 요청할 수 있습니다.

7. 안전성 확보 조치 및 방침 변경
① 회사는 개인정보의 분실·도난·유출·변조·훼손 방지를 위해 접근 통제, 전송 구간 보호, 권한 관리 등 합리적 수준의 기술적·관리적 보호조치를 시행합니다. 다만, 인터넷 환경의 특성상 절대적 안전을 보장하지는 않습니다.
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

These Terms govern your use of the Loopi service ("Service") operated by Loopi ("Company"). By using the Service, you agree to these Terms.

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
(3) Continued use after the effective date constitutes acceptance. If you disagree, stop using the Service and withdraw.
(4) Matters not specified here follow applicable law and customary practice.

Article 4 (Free Service AS-IS Disclaimer)
(1) The Company does not warrant completeness, fitness for a particular purpose, uninterrupted operation, or absolute security of free Service features.
(2) To the extent permitted by law, the Service is provided "AS IS" and "AS AVAILABLE".
(3) The Company is not liable for loss or damage to Local Data caused by OS errors, browser cache/data deletion, insufficient storage, device loss/replacement, network instability, or user negligence, except in cases of willful misconduct or gross negligence.
(4) The Company may suspend or change all or part of the Service for improvement, maintenance, or incident response, with prior or subsequent notice.

Article 5 (Paid Content and In-App Purchases)
(1) Pricing, term, refunds, and withdrawal follow the product notice at purchase, app-store policies (Apple App Store, Google Play, etc.), and applicable law.
(2) In-app payments are processed by the relevant store operator; billing errors, approval delays, and refunds primarily follow store policies.
(3) Fraudulent payment or unauthorized copying/resale of Paid Content may result in restriction, termination, and legal action.
(4) For auto-renewing subscriptions after a free trial, cancel in store settings; post-cancellation billing follows store rules.
(5) Once digital content delivery has begun, withdrawal may be limited except as required by mandatory law.
(6) If a minor purchases Paid Content without the legal representative's consent, the minor or the legal representative may cancel the payment. However, cancellation may be limited if the minor used deceit to appear as an adult or to appear to have the legal representative's consent. For in-app purchases, majority status is determined based on the payment account holder (device owner or store-account holder).

Article 6 (YouTube and Third-Party API Disclaimer)
(1) The Service may access external content via third-party APIs, SDKs, embedded players, or links. Ownership and rights remain with the third party or original rights holders.
(2) Except for willful misconduct or gross negligence, the Company is not liable for outages, API limits, playback failures, geo-blocks, account sanctions, or network issues caused by YouTube or other third parties.
(3) Users must comply with YouTube Terms of Service (https://www.youtube.com/t/terms) and other third-party policies; disputes arising from violations are the user's responsibility.
(4) The Company does not warrant the legality, accuracy, availability, or rights clearance of third-party content.

Article 7 (User Content, Copyright, and Indemnification)
(1) Rights and responsibility for User Content remain with the user. Users must not upload content that infringes others' copyrights, publicity rights, trademarks, or privacy.
(2) By posting to public features (showcase, community, classes, etc.), the user grants the Company a non-exclusive, royalty-free license to reproduce, transmit, display, and reformat such content as needed to operate, promote, and improve the Service.
(3) Users shall indemnify and hold the Company harmless from damages arising from their User Content to the extent permitted by law.
(4) The Company may remove, hide, or restrict content that infringes rights, violates law, or harms Service operations.
(5) Local practice recordings are not automatically uploaded to Company servers unless the user expressly requests upload/share; primary custody of Local Data rests with the user.
(6) If a user causes monetary or operational harm to the Company through macros, crawling, abnormal traffic (abuse), or by bypassing or exploiting the payment system, the Company may immediately permanently suspend the account and seek civil and criminal damages.

Article 8 (Limitation of Liability and Damage Cap)
(1) The Company is not liable for failures beyond reasonable control (force majeure, carrier outages, hacking/DDoS, etc.).
(2) The Company has no duty to intervene in disputes between users or between a user and a third party, and is not liable therefor except for willful misconduct or gross negligence.
(3) To the maximum extent permitted by law, the Company's aggregate liability is capped at the total Paid Content fees actually paid by the user to the Company in the three (3) months preceding the claim. For free-only users, monetary liability is disclaimed or limited to the minimum required by law.
(4) Except for willful misconduct or gross negligence, the Company is not liable for indirect, special, consequential, lost profits, or data-recovery costs.
(5) These limitations do not apply where mandatory law prohibits them.

Article 9 (Governing Law and Exclusive Jurisdiction)
(1) These Terms and disputes arising from use of the Service are governed by the laws of the Republic of Korea, which apply in preference to conflict-of-laws principles or the laws of the user's country of residence.
(2) Lawsuits arising from the Service shall be subject to the exclusive jurisdiction of the court having jurisdiction over the Company's principal place of business as the court of first instance, unless mandatory law provides otherwise for the user's benefit.

Supplementary Provision
These Terms take effect on the date of posting.
''';

  static const String _privacyEn = '''
Loopi Privacy Policy

Loopi ("Company") complies with applicable privacy laws and discloses this Privacy Policy to protect users' personal information.

1. Personal Information Collected
The Company may collect:
(1) Account/auth data: OAuth UID, email (if provided), profile name/nickname, profile image URL (if provided), login provider type
(2) Service usage data: routines, folders, favorites, and community/class/showcase activity
(3) Device/log data: device type, OS/browser, app version, access times, usage logs, error/performance diagnostics
(4) Transaction data: in-app purchase/subscription Transaction IDs, product codes, payment status, and minimum receipt-validation data (card numbers are not stored by the Company; app stores process payments)
(5) Information voluntarily submitted: inquiries, additional profile fields, public posts
(6) The Company does not collect, identify, or analyze sensitive biometric information specially protected by law (e.g., facial recognition data, iris, fingerprints). Dance videos voluntarily stored by users are treated as ordinary media files and are not used as biometric data to identify a specific individual, nor provided to third parties for that purpose.

2. Purpose of Collection and Use
(1) Identification, authentication, account management, and abuse prevention
(2) Providing practice, community, class, showcase, and related features
(3) Customer support and service notices
(4) Payment/subscription verification, receipt validation, and refund support
(5) Stability, security, error analysis, improvement, and aggregated statistics
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
(2) Upon account deletion, server-side account-linked data is deleted or segregated without delay, except items legally required to be retained.
(3) Data existing only on the local device is managed by the user (delete files or clear app/browser data).

5. Third Parties and Cloud Consignment
(1) The Company does not provide personal information to third parties without consent, except as required by law or with explicit user consent.
(2) Processing may be entrusted to:
  - Cloud/backend providers (e.g., Firebase/Google Cloud) for auth, database, storage, and remote config
  - App stores (Apple, Google, etc.) for payments/subscriptions and receipt validation
  - Social login providers (Kakao, Google, Apple, etc.) for authentication
  - YouTube/Google and similar services for playback/API access within the scope needed for user-selected content
(3) The Company requires appropriate safeguards from processors and will notify material changes via this Policy or in-Service notices.
(4) The Company uses global cloud services (e.g., Google Firebase). For backup and service reliability, collected information may be transmitted to and stored on physical servers outside Korea (e.g., United States, Asia regions). Cross-border data is retained securely for the periods stated in this Policy and destroyed when the purpose is achieved.

6. User Rights
Users may request access, correction, deletion, suspension of processing, withdrawal of consent, account deletion, and complaint handling under applicable law. The Company will act without undue delay, except where retention is legally required. Requests may be made via in-app support channels.

7. Security Measures and Policy Changes
(1) The Company implements reasonable technical and administrative safeguards (access control, transport protection, permission management). Absolute security cannot be guaranteed on the Internet.
(2) Material changes to this Policy will be announced in the Service with an effective date.
(3) Where this Policy conflicts with a specific consent, applicable law and the specific consent may prevail.

Supplementary Provision
This Privacy Policy takes effect on the date of posting.
''';
}

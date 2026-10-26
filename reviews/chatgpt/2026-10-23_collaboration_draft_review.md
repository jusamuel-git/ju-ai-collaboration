확인했습니다. 초안의 뼈대는 좋습니다. 다만 지금 확정하기 전에 몇 군데는 수정하는 게 좋습니다. 특히 기존 JuProvider에서 이미 정한 방향과 충돌하거나, AI 협업 시 나중에 발목을 잡을 규칙이 있습니다.
제가 수정하고 싶은 핵심
첫째, 역할 정의에서 ChatGPT를 단순 코드 리뷰 역할로 제한하지 않겠습니다. 지금 협업 방식에서는 제가 전체 설계와 작업계획까지 담당하고 Claude가 로컬 구현을 담당하는 구조가 더 정확합니다.

둘째, desktop/app/ 전체를 Git에서 제외한다는 규칙은 위험합니다. 기존 JuProvider에서 /app/config, /app/service, /app/libs, /app/logs 등의 실행 구조를 사용해 왔기 때문입니다. 실행 산출물은 제외하되, 원본 설정/template이 필요한 경우는 소스 영역에서 관리해야 합니다. 

셋째, baseline을 절대 수정하지 않는다는 규칙도 조금 바꾸겠습니다. 이미 배포된 DB의 변경은 migration이 맞지만, 현재처럼 baseline 자체를 개발하고 정리하는 단계에서는 baseline/seed를 함께 갱신해야 새 DB를 처음 만들었을 때 최신 구조가 됩니다.

넷째, 현재 문서에 적힌 기술 스택이 기존 기록과 달라졌습니다. Spring Boot 3.5 / Java 21, .NET 10, VS2026 등은 Claude가 현재 저장소에서 직접 확인한 최신 상태라면 저장소 실물을 우선하겠습니다. 과거에 제가 알고 있던 Spring Boot 2.7/Java 17/.NET 9보다 현재 Git 소스가 우선입니다. 

다섯째, 작업 기록을 AI_COLLABORATION.md에 계속 누적하는 것은 장기적으로 문서가 너무 커집니다. 규칙 문서와 작업 이력은 분리하는 편이 좋습니다. AI_COLLABORATION.md에는 규칙만, Git commit이 실제 변경 이력이 되고, AI 간 인수인계가 필요한 현재 작업만 별도 AI_WORKLOG.md를 두는 방식을 추천합니다.
협업 구조는 이렇게 확정하는 게 좋겠습니다
사용자(JU)
        │
        │ 최종 결정 / 승인
        ▼
     ChatGPT
 설계 / 분석 / 작업계획
 규칙 관리 / 결과 검토
        │
        │ 작업지시
        ▼
      Claude
 로컬 소스 조사 / 구현
 빌드 / 테스트 / 변경보고
        │
        ▼
       Git
 확정된 소스의 기준점

여기서 아주 중요한 규칙 하나를 추가하겠습니다.
Git 저장소의 현재 소스가 구현 상태에 대한 최종 기준(Source of Truth)이다.

ChatGPT의 기억, Claude의 이전 설명, README, 대화 내용과 실제 코드가 충돌하면 코드를 먼저 조사하고 차이가 발생한 이유를 확인해야 합니다. 오래 개발하다 보면 이 규칙이 상당히 중요해집니다.

또 하나는:
AI는 기존 코드가 이상해 보인다는 이유만으로 임의 리팩터링하지 않는다.

이번 JuProvider 개발에서 한 문제를 고치다가 다른 부분까지 바뀌면서 반복적으로 문제가 발생했던 것을 막기 위한 규칙입니다. 
지금 발견된 항목의 결정
현재 미결 사항은 이렇게 처리하겠습니다.
항목	결정
node_modules	Git 추적 해제
dist	Git 추적 해제
target	Git 추적 해제
DB 1234	환경변수 전환 유지
과거 Git history의 1234	지금 history rewrite 안 함
빈 Class1.cs	다음 구조검사에서 판단
desktop/native	삭제 금지
template.accdb	원본 관리 위치 결정 후 처리
Jenkins frontend	구조 확인 후 결정
Jenkins desktop	후순위
juproject README	나중에 작성
juproject seed password	환경변수/user-secrets 방향
baseline	개발 중에는 최신 상태 유지
migration	기존 설치 DB 업그레이드용


desktop/native는 특히 삭제하면 안 됩니다. JuProvider에서 OpenCV/OpenGL/Eigen/VTK/Qt를 사용하는 C++ native library와 C# P/Invoke 연동을 계획하고 이미 작업해 왔기 때문에, 지금 비어 있더라도 향후 native 영역으로 사용해야 합니다. 
Claude에게 다음과 같이 전달하면 됩니다
현재 AI_COLLABORATION.md 초안을 기본으로 유지하되 다음 내용을 반영한다.
1. 역할 수정
ChatGPT 역할을 다음과 같이 변경한다.
- 전체 구조 및 아키텍처 설계
- 작업 범위와 구현 방향 결정 지원
- Claude 작업지시 작성
- DB/API/UI 구조 검토
- Claude 변경 결과 및 오류 분석
- 협업 규칙 관리
Claude 역할:
- 로컬 저장소 조사
- 실제 소스 수정
- 빌드
- 테스트
- 변경 결과 보고
사용자(JU):
- 최종 결정
- 우선순위 결정
- 중요 변경 승인
- commit/push 승인
2. Source of Truth 규칙 추가
현재 Git 저장소의 소스를 구현 상태의 최종 기준(Source of Truth)으로 한다.

ChatGPT의 기억, Claude의 이전 분석, README, 과거 대화와 현재 코드가 다르면 현재 코드를 먼저 조사한다.

단, 코드가 설계 원칙과 다른 경우 임의로 변경하지 않고 차이를 보고한다.
3. 변경 범위 원칙 추가
요청받은 범위를 넘어선 대규모 리팩터링을 하지 않는다.

문제를 발견해도 현재 작업과 직접 관계가 없으면 임의 수정하지 않고 보고한다.

DB/API/공통 모델처럼 영향 범위가 큰 변경은 사용자의 승인 후 진행한다.
4. desktop/app 규칙 수정
desktop/app/ 전체를 단순히 Git 제외 대상으로 정의하지 않는다.

빌드 결과물과 실행 중 생성되는 파일은 Git에 포함하지 않는다.

하지만 프로그램 실행에 필요한 원본 설정, template, schema 등의 파일은 소스 영역에서 별도로 관리하고 build/copy 과정에서 app으로 배포하는 구조를 사용한다.

template.accdb의 원본 위치는 desktop 구조를 확인한 후 결정한다.
5. database 규칙 수정
이미 배포된 DB 변경은 database/migration SQL로 관리한다.

현재 개발 중인 최신 DB 구조는 baseline에도 반영한다.

따라서:
- baseline = 신규 설치용 최신 전체 구조
- seed = 신규 설치용 기본 데이터
- migration = 기존 설치 DB 업그레이드
로 정의한다.
6. Native 영역
desktop/native는 삭제하지 않는다.

JuProvider의 C++ native library 영역으로 사용한다.

향후 OpenCV/OpenGL/Eigen/VTK/Qt 및 C# P/Invoke 연동 코드를 배치할 수 있다.

현재 비어 있어도 유지한다.
7. 작업 기록
AI_COLLABORATION.md에는 장기간 작업 기록을 계속 누적하지 않는다.

AI_COLLABORATION.md는 협업 규칙을 관리한다.

필요하면 별도 AI_WORKLOG.md를 만들어 현재 작업 인수인계를 기록한다.

확정된 변경 이력은 Git commit을 최종 기록으로 사용한다.
8. 현재 정리 대상
다음 Git 추적 파일은 제거 대상으로 확정한다.
- node_modules
- dist
- target
실제 소스는 삭제하지 않고 Git 추적만 해제한다.

다음은 아직 삭제하지 않는다.
- Class1.cs
- desktop/native
- template.accdb
구조를 확인한 후 별도로 결정한다.
9. 기술 스택
문서에 기록하는 Java/.NET/Spring Boot/Node 등의 버전은 과거 문서가 아니라 현재 repository의 project/build 설정에서 직접 확인한 값을 사용한다.

확인한 근거 파일도 작업 결과에 보고한다.

위 내용을 두 저장소의 AI_COLLABORATION.md에 동일하게 반영한다.

아직 commit/push하지 않는다.

수정 후 다음만 보고한다.
1. 변경된 AI_COLLABORATION.md
2. 현재 juprovider git status
3. 현재 juproject git status
4. 기술 스택 버전을 확인한 파일과 실제 버전
5. 아직 판단이 필요한 항목
추가적인 코드 수정이나 파일 삭제는 하지 않는다.



이 작업까지 끝내고 Claude의 결과를 다시 가져오면 제가 마지막으로 확인하겠습니다. 그 다음 첫 정리 commit을 만들고, 그 commit부터 ChatGPT-Claude 공동개발의 기준점으로 잡는 것이 가장 깔끔합니다.
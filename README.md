# Codyssey_Trouble_Shooting

## B1-2

---

# 초기 설정

```bash
# 1. 필수 환경변수 설정
export AGENT_HOME=$(pwd)
export AGENT_LOG_DIR="/var/log/agent-app"
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys"
export MEMORY_LIMIT=128 # 메모리 누수 실험용
export CPU_MAX_OCCUPY=10 # CPU 사용량 제한 (최솟값 10)

export MULTI_THREAD_ENABLE=1 # Deadlock 재현을 위해 활성화

# 2. 필수 디렉토리 및 키 파일 생성
mkdir -p $AGENT_UPLOAD_DIR
mkdir -p $AGENT_KEY_PATH
echo "agent_api_key_test" > $AGENT_KEY_PATH/secret.key

# 3. 실행
./agent-app-leak
```

---

# [Bug] OOM Crash - 메모리 누수로 인한 에이전트 자가 종료 발생

## 1. Description (현상 설명)

- 현상: 에이전트 실행 후 약 15~20초 시점에서 프로세스가 아무런 에러 메시지 없이 갑자기 종료(Killed)되는 현상이 발생함.
- 조건: `MEMORY_LIMIT` 환경변수가 128MB로 설정된 상태에서 에이전트 구동 시 발생.

---

## 2. Evidence & Logs (증거 자료)

### 2.1 프로그램 실행 로그 (핵심 구간)

```bash
2026-05-15 17:56:45,189 [INFO] [MemoryWorker] Current Heap: 100MB
2026-05-15 17:56:48,211 [INFO] [MemoryWorker] Current Heap: 125MB
2026-05-15 17:56:51,234 [INFO] [MemoryWorker] Current Heap: 150MB

# 설정해둔 MEMORY_LIMIT(128MB) 보다 현재 힙 메모리가 커짐

2026-05-15 17:56:51,234 [CRITICAL] [MemoryGuard] Memory limit exceeded (150MB >= 128MB)
2026-05-15 17:56:51,234 [CRITICAL] [MemoryGuard] Self-terminating process 1448 to prevent system instability.

>>> [SYSTEM] SELF-TERMINATED (Memory Limit Exceeded) <<<

Killed
```

### 2.2 monitor.sh 관제 데이터 (추론값)

- 점유율 상승 패턴:
  - 3초 간격으로 메모리 사용량이 약 25MB씩 선형적으로 증가함.
- 최종 관측:
  - 종료 직전 메모리 점유량 약 150MB 기록.

---

## 3. Root Cause Analysis (원인 분석)

### 기술적 원인

- `MemoryWorker` 스레드 내에서 메모리 할당 후 해제되지 않는 메모리 누수(Memory Leak) 현상이 발생함.
- 힙(Heap) 영역이 지속적으로 팽창하여 설정된 임계치에 도달함.

### OS 및 애플리케이션 동작 원리

- 시스템 전체의 메모리 고갈로 인한 OOM Killer 작동 및 OS 패닉을 방지하기 위해 앱 내부에 Fail-Safe 기구인 `MemoryGuard`가 구현되어 있음.
- 애플리케이션 레벨에서 자가 진단을 통해 설정된 임계치를 초과하는 순간 프로세스를 안전하게 종료하여 시스템 안정성을 확보함.

---

## 4. Workaround & Verification (조치 및 검증)

### 4.1 조치 내용

- 환경변수 `MEMORY_LIMIT`을 기존 128MB에서 300MB로 상향 조정하여 에이전트 가용 메모리 범위를 확장함.

```bash
export MEMORY_LIMIT=300
./agent-app-leak
```

### 4.2 Before & After 비교 결과

| 항목 | 조치 전 (Before) | 조치 후 (After) |
|---|---|---|
| 환경변수 설정 | MEMORY_LIMIT=128 | MEMORY_LIMIT=300 |
| 최대 가용 메모리 | 128 MB | 300 MB |
| 생존 시간 | 약 15초 (150MB에서 종료) | 지속 실행 (안정화 확인) |

---

# [Bug] CPU Latency - CPU 과점유로 인한 Watchdog 강제 종료

## 1. Description (현상 설명)

- 현상: 고부하 연산 작업(Intensive Computation) 시 CPU 점유율이 급증하며, 특정 임계치 도달 시 Watchdog에 의해 프로세스가 종료됨.
- 조건: `CPU_MAX_OCCUPY` 환경변수가 10%로 설정된 상태에서 연산 수행 시 발생.

---

## 2. Evidence & Logs (증거 자료)

### 2.1 프로그램 실행 로그 (핵심 구간)

```bash
2026-05-15 19:40:04,534 [INFO] [CpuWorker] Current Load: 9.29%
2026-05-15 19:40:07,635 [INFO] [CpuWorker] Peak reached (10.00%). Starting cooldown...
2026-05-15 19:40:07,635 [INFO] [CpuWorker] Current Load: 10.00%

# 임계치(10%) 도달 시 Watchdog이 SIGTERM을 발생시켜 종료 유도
# 환경에 따라 Peak 직후 종료

2026-05-15 19:25:32 [CRITICAL] [Watchdog] Resource Policy Violation: CPU_MAX_OCCUPY exceeded.

Terminated
```

### 2.2 시스템 도구(top) 출력 결과

- `top` 관제 시 `agent-app-leak` 프로세스가 연산 피크 시점에 `%CPU` 수치가 10.0~12.5%를 기록하는 것을 실시간 확인.
- 부하 생성기(`gzip`) 가동 시 시스템 부하와 맞물려 임계치를 초과함.

---

## 3. Root Cause Analysis (원인 분석)

### 기술적 원인

- 에이전트 내 `CpuWorker`가 복잡한 연산을 수행하며 순간적으로 CPU 자원을 과다 점유함.

### OS 동작 원리

- 에이전트 내부에 상주하는 `Watchdog` 스레드가 일정 주기마다 점유율을 체크함.
- 설정된 정책 위반 시 시스템 전체 응답성 저하를 막기 위해 스스로에게 `SIGTERM` 시그널을 보내 종료하는 리소스 가딩 메커니즘이 작동함.

---

## 4. Workaround & Verification (조치 및 검증)

### 4.1 조치 내용

- 환경변수 `CPU_MAX_OCCUPY`를 기존 10%에서 60%로 상향 조정하여 연산 자원 임계치를 확보함.

```bash
export CPU_MAX_OCCUPY=60
./agent-app-leak
```

### 4.2 Before & After 비교 결과

| 항목 | 조치 전 (Before) | 조치 후 (After) |
|---|---|---|
| 환경변수 설정 | CPU_MAX_OCCUPY=10 | CPU_MAX_OCCUPY=60 |
| 임계치 초과 여부 | 발생 (10% 이상 점유 시) | 미발생 (정상 연산 수행) |

---

# [Bug] Deadlock - 자원 순환 참조로 인한 스레드 교착 상태 발생

## 1. Description (현상 설명)

- 현상: 에이전트 실행 중 특정 시점에서 로그 출력이 중단되며, 프로세스는 존재하나 어떤 작업도 처리하지 못하는 `Hang` 상태가 됨.
- 조건: `MULTI_THREAD_ENABLE=1` 설정으로 병렬 처리 모드 가동 시 발생.

---

## 2. Evidence & Logs (증거 자료)

### 2.1 프로그램 실행 로그 (핵심 구간)

```bash
2026-05-15 19:24:26,607 [INFO] [AgentWorker][Worker-Thread-1] Need resource [Socket_Pool_B] to finish job.
2026-05-15 19:24:26,607 [INFO] [AgentWorker][Worker-Thread-2] Need resource [Shared_Memory_A] to write logs.

2026-05-15 19:24:26,608 [INFO] [AgentWorker][Worker-Thread-1] WAITING for [Socket_Pool_B]... (Status: BLOCKED)
2026-05-15 19:24:26,608 [INFO] [AgentWorker][Worker-Thread-2] WAITING for [Shared_Memory_A]... (Status: BLOCKED)

# 이후 로그 출력 무한 중단
```

### 2.2 시스템 도구 확인 결과

- `ps -ef | grep agent-app-leak`
  - 프로세스 PID가 여전히 존재하여 종료되지 않았음을 확인.
- `top -H`
  - CPU 점유율이 0% 근처에서 변화가 없으며 스레드들이 연산을 멈춘 상태임을 확인.

---

## 3. Root Cause Analysis (원인 분석)

### 기술적 원인

- 순환 대기(Circular Wait) 발생.
- `Worker-Thread-1`은 자원 A를 쥔 채 B를 요청하고,
- `Worker-Thread-2`는 자원 B를 쥔 채 A를 요청하며 서로 무한 대기함.

### 이론적 근거

- 교착상태 4대 조건(상호배제, 점유대기, 비선점, 순환대기) 중 `순환 대기`가 충족되어 발생한 전형적인 Deadlock 이슈임.

---

## 4. Workaround & Verification (조치 및 검증)

### 4.1 조치 내용

- 환경변수 `MULTI_THREAD_ENABLE`을 0으로 설정하여 순차 처리 모드로 변경, 자원 경합을 원천 차단함.

```bash
export MULTI_THREAD_ENABLE=0
./agent-app-leak
```

### 4.2 Before & After 비교 결과

| 항목 | 조치 전 (Before) | 조치 후 (After) |
|---|---|---|
| 멀티스레딩 설정 | ENABLED (1) | DISABLED (0) |
| 장애 현상 | 스레드 간 교착(Deadlock) 발생 | 순차적 접근으로 충돌 방지 |
| 최종 상태 | 무한 대기 (Hang) | 모든 작업 정상 종료 확인 |
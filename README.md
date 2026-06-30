# agent-leak-app 장애 분석 종합 보고서

**작성일:** 2026-06-30  
**대상 애플리케이션:** agent-leak-app (Python 기반 x86_64 바이너리)  
**테스트 환경:** OrbStack Ubuntu 22.04 LTS  
**테스트 방법:** 시스템 모니터링 + 실시간 로그 분석

---
## 기본 환경 세팅
```bash
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys
export AGENT_LOG_DIR=$AGENT_HOME/logs
export MEMORY_LIMIT=300
export CPU_MAX_OCCUPY=50
export MULTI_THREAD_ENABLE=0
```
---
## Executive Summary

`agent-leak-app` 실행 중 **3가지 시스템 장애** (OOM, CPU 과점유, Deadlock)를 의도적으로 재현하고 분석했다.

각 장애별로 **환경변수 조정 전후 비교**를 통해 원인을 규명하고 임시 해결책(Workaround)을 제시했다.

| 장애 유형 | 재현 조건 | 원인 | 상태 |
|---|---|---|---|
| **OOM** | MEMORY_LIMIT=256MB | 메모리 누수 | 해결 방안 (300MB로 상향) |
| **CPU 과점유** | CPU_MAX_OCCUPY=10% | 높은 Cooldown 빈도 | 해결 방안 (50%로 상향) |
| **Deadlock** | MULTI_THREAD_ENABLE=1 | 순환 자원 대기 | 해결 방안 (단일 스레드) |

---

## 장애별 상세 분석

### 1. OOM (Out Of Memory) - 메모리 누수

**문제:**
```
프로세스 메모리 누적 상승
25MB → 50MB → 75MB → ... → 275MB
↓
MEMORY_LIMIT(256MB) 도달
↓
MemoryGuard 정책 발동
↓
프로세스 강제 종료 (SELF-TERMINATED)
```

**증거 (Before 케이스):**
- 앱 로그: `13:12:54 SELF-TERMINATED (Memory Limit Exceeded)`
- 모니터: `13:12:54 PROCESS NOT FOUND` (타임스탐프 일치)
- CPU: 0.2% (변화 없음)
- 메모리: 2232KB (OS 관점 변화 없음 - 내부 시뮬레이션)

**조치:**
```bash
MEMORY_LIMIT=256  →  MEMORY_LIMIT=300
```

**효과 (After 케이스):**
- 300MB 도달 후 `MEMORY RECOVERED` 로그
- 프로세스 계속 생존 (30분 이상)
- 자동 정리 로직 작동 확인

**결론:** 메모리 임계치 여유 확보로 내부 정리 로직 실행 가능 상태 달성

---

### 2. CPU 과점유 - Watchdog 제어 메커니즘

**문제:**
```
CpuWorker 부하 증가
5% → 10% (임계치 도달)
↓
Watchdog Cooldown 시작
↓
5%로 감소 후 재개
↓
다시 10% 도달 → Cooldown (반복)
```

**증거 (Before 케이스, CPU_MAX_OCCUPY=10%):**
- 앱 로그: `Peak reached (10.00%). Starting cooldown...` (매 8초마다)
- 모니터: CPU 0.1~0.4% (제어 상태 지속)
- Cooldown 빈도: 자주 발생 (비효율)

**증거 (After 케이스, CPU_MAX_OCCUPY=50%):**
- 앱 로그: `Peak reached (50.00%)...` (약 21초 후 첫 발생)
- 모니터: CPU 0.5~5.5% (더 자유로움)
- Cooldown 빈도: 드물게 발생 (효율 높음)

**조치:**
```bash
CPU_MAX_OCCUPY=10  →  CPU_MAX_OCCUPY=50
```

**효과:**
- Cooldown 반복 주기 8초 → 21초 이상 확대
- 작업 연속성 향상
- 시스템 안정성 유지

**결론:** CPU 제한을 높여 작업 여유 확보, 시스템 전체 영향 최소화

---

### 3️⃣ Deadlock (교착상태) - 순환 자원 대기

**문제:**
```
Thread-1: Lock[Memory_A] 획득 → Lock[Socket_B] 대기
Thread-2: Lock[Socket_B] 획득 → Lock[Memory_A] 대기
                ↓
         서로의 자원을 무한정 대기
                ↓
          [교착상태 발생]
                ↓
     프로세스 무응답 (CPU 0%, 로그 멈춤)
```

**증거 (Before 케이스, MULTI_THREAD_ENABLE=1):**
- 부트 메시지: `WARNING: POTENTIAL DEADLOCK IN CONCURRENT MODE`
- 앱 로그:
  ```
  13:29:50 Thread-1: LOCK ACQUIRED [Shared_Memory_A]
  13:29:50 Thread-2: LOCK ACQUIRED [Socket_Pool_B]
  13:29:52 Thread-1: WAITING [Socket_Pool_B]... BLOCKED
  13:29:52 Thread-2: WAITING [Shared_Memory_A]... BLOCKED
  [로그 완전 중단]
  ```
- PID 확인: `ps -ef` → PID:2802 존재 (살아있음)
- 모니터: CPU 0.2~0.5% (고정, 변화 0)
- 타임스탐프: 13:29:52 이후 모든 활동 정지

**증거 (After 케이스, MULTI_THREAD_ENABLE=0):**
- 부트 메시지: `[ OK ]` (경고 없음)
- 앱 로그:
  ```
  13:30:59 Thread-A Task Completed (100%)
  13:30:59 Thread-B Task Completed (100%)
  13:30:59 Thread-C Task Completed (100%)
  13:30:59 All tasks completed
  ```
- 모든 작업 순차적 완료
- 모니터: CPU 점진적 감소 (정상)

**조치:**
```bash
MULTI_THREAD_ENABLE=1  →  MULTI_THREAD_ENABLE=0
# Concurrency: True → Concurrency: False
# 병렬 실행 → 순차 실행
```

**효과:**
- 리소스 경합 제거 (한 번에 1개 스레드만 실행)
- 교착상태 100% 회피
- 모든 작업 정상 완료

**결론:** 교착상태의 4대 조건(상호배제, 점유대기, 비선점, 순환대기) 모두 만족 → 순차 실행으로 완전 회피

---

## 환경변수 조정 정리

### Before vs After 비교표

| 환경변수 | Before (장애 발생 상태) | After (임시 해결 상태) | 개선 효과 |
|---|---|---|---|
| **MEMORY_LIMIT** | 256MB | 300MB | 내부 정리 로직 시간 확보 |
| **CPU_MAX_OCCUPY** | 10% | 50% | Cooldown 빈도 감소 |
| **MULTI_THREAD_ENABLE** | 1 (True) | 0 (False) | 교착상태 회피 |

---
## monitor.sh 구성 및 동작 방식

`monitor.sh`는 `agent-leak-app` 프로세스의 상태를 3초마다 확인하여 CPU와 메모리 사용량을 기록하는 모니터링 스크립트이다.

### 1. 프로세스 확인

```bash
PID=$(pgrep -f agent-leak-app | head -1)
```

`pgrep` 명령어를 사용하여 `agent-leak-app` 프로세스의 PID(Process ID)를 검색한다. 프로세스가 실행 중이지 않으면 `PROCESS NOT FOUND`를 출력하고, 실행 중이라면 해당 PID를 이용하여 자원 사용량을 확인한다.

---

### 2. CPU 사용량 확인

```bash
ps -p $PID -o %cpu
```

`ps` 명령어의 `%cpu` 옵션을 사용하여 해당 프로세스의 CPU 사용률을 확인하였다.

* %CPU : CPU 사용률
* %MEM : 메모리 사용률
* RSS : 실제 RAM 사용량
* VSZ : 가상 메모리 크기

- **%CPU** : 프로세스가 현재 사용하는 CPU 사용률(%)

---

### 3. 메모리 사용량 확인

```bash
ps -p $PID -o %mem,rss,vsz
```

`ps` 명령어를 이용하여 프로세스의 메모리 정보를 확인하였다.

- **%MEM** : 시스템 전체 메모리 대비 프로세스가 사용하는 비율(%)
- **RSS (Resident Set Size)** : 현재 실제 물리 메모리(RAM)에 적재되어 있는 메모리 크기(KB)
- **VSZ (Virtual Size)** : 프로세스가 사용하는 전체 가상 메모리 크기(KB)

---

### 4. 로그 저장

```bash
tee -a ~/monitor.log
```

`tee` 명령어를 사용하여 화면에 출력되는 내용을 동시에 `monitor.log` 파일에 저장하였다. 이를 통해 장애 발생 시점의 CPU와 메모리 사용량을 확인하고 Before와 After 결과를 비교할 수 있도록 하였다.

---

### 5. 주기적 모니터링

```bash
sleep 3
```

프로세스의 상태를 3초마다 반복적으로 확인하여 CPU와 메모리 사용량의 변화를 지속적으로 기록하였다.

---

### 근본적 해결 방안

현재 적용한 방법은 메모리와 CPU의 임계치를 조정하여 장애 발생 시점을 늦추거나 빈도를 줄인 것으로, 근본적인 해결 방법은 아니다. 근본적으로는 프로그램의 동작 방식을 개선해야 한다.

### OOM 근본 해결

메모리 누수를 방지하기 위해 사용이 끝난 메모리는 즉시 해제하도록 수정해야 한다. 또한 불필요하게 메모리가 계속 증가하지 않도록 메모리 관리 방식을 개선해야 한다.

### CPU 과점유 근본 해결

CPU를 많이 사용하는 반복 연산을 줄이고, 더 효율적인 알고리즘을 적용하여 CPU 사용량 자체를 낮춰야 한다. 이를 통해 불필요한 Cooldown 발생을 줄이고 작업 효율을 높일 수 있다.

### Deadlock 근본 해결

여러 스레드가 자원을 사용하는 순서를 동일하게 유지하여 서로가 상대방의 자원을 기다리는 상황이 발생하지 않도록 해야 한다. 또한 일정 시간 이상 자원을 획득하지 못하면 작업을 중단하거나 다시 시도하는 방법을 적용하여 교착 상태를 예방할 수 있다.

---

## 첨부 문서

| 파일명 | 내용 |
|---|---|
| `OOM.md` | OOM 상세 분석 리포트 |
| `CPU.md` | CPU 과점유 상세 분석 리포트 |
| `Deadlock.md` | 교착상태 상세 분석 리포트 |

---

## + 추가 분석
## 장애 발생 전 탐지를 위한 monitor.sh 개선 방안

현재 `monitor.sh`는 장애 발생 후 상태를 확인하는 기능만 수행한다. 이를 보완하기 위해 다음과 같이 개선할 수 있다.

- **임계치 경고:** CPU나 메모리 사용량이 일정 수준(예: 80%)을 넘으면 경고를 출력한다.
- **사용량 변화 확인:** 이전 측정값과 비교하여 메모리나 CPU 사용량이 계속 증가하는지 확인한다.
- **스레드 상태 확인:** 스레드의 대기(Blocked) 상태를 확인하여 Deadlock 발생 여부를 빠르게 판단한다.

---

### 가장 치명적인 장애 선택 및 이유, 예방 방법

3가지 장애 중 가장 치명적인 장애는 **OOM(메모리 누수)** 이라고 생각한다.

### 선택 이유

CPU 과점유는 프로그램의 속도가 느려질 수 있지만 계속 실행될 수 있다.

Deadlock은 프로그램이 멈추지만 프로세스는 살아 있으므로 원인을 분석하고 다시 실행할 수 있다.

반면 OOM은 메모리 사용량이 계속 증가하여 결국 프로세스가 강제 종료된다. 또한 심한 경우에는 운영체제의 OOM Killer가 동작하여 다른 프로세스에도 영향을 줄 수 있으므로 시스템 전체의 안정성을 떨어뜨릴 수 있다.

따라서 세 가지 장애 중 OOM이 가장 위험한 장애라고 판단하였다.

### 예방 방법

- 메모리를 할당한 후에는 사용이 끝나면 반드시 해제한다.
- MemoryGuard와 같은 메모리 보호 정책을 적용하여 임계치를 초과하기 전에 대응한다.
- 메모리 누수가 발생하는 코드를 수정하여 근본 원인을 제거한다.

---

## OOM과 Deadlock 동시 발생 시 트러블슈팅 순서 및 근거

두 장애가 동시에 나타난다면 **OOM을 먼저 해결**해야 합니다.

### 우선순위
> OOM 분석 후 조치 ➔ Deadlock 분석 ➔ 원인 규명

### 근거

OOM이 발생한 경우에는 프로세스가 즉시 종료되는 것을 확인하였다. 반면 Deadlock은 프로세스가 종료되지 않고 스레드들이 서로 자원을 기다리며 무한 대기 상태에 빠지는 것을 확인하였다.

OOM으로 인해 프로세스가 먼저 종료되면 Deadlock 상태를 분석할 대상 자체가 사라진다. 따라서 프로세스가 정상적으로 유지되는 환경을 먼저 확보한 후 Deadlock을 분석하는 것이 효율적이다. 이러한 이유로 OOM을 먼저 해결한 뒤 Deadlock을 분석하는 것이 더 합리적이다.

---

## 미션 재수행 시 다르게 접근할 점

### 장애를 하나씩 재현

미션을 수행하는 과정에서 환경변수에 대한 이해가 부족하여 원하는 결과가 나오지 않는 경우가 있었다. 따라서 다음에 수행한다면 먼저 각 환경변수의 역할과 동작 방식을 충분히 이해한 후 장애를 하나씩 재현하며 진행할 것이다.

---

### 원인을 분석한 후 해결하기

장애가 발생하면 먼저 로그를 확인하여 어떤 문제가 발생했는지 분석하는 과정이 필요하다. 이후 로그와 시스템 정보를 함께 비교하여 원인을 파악하고, 그에 맞는 해결 방법을 적용하는 방식으로 접근할 것이다.
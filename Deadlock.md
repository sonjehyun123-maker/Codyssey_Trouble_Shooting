# [Bug] Deadlock (교착상태) - 멀티스레드 환경에서의 무한 자원 대기

## 1. Description (현상 설명)

`agent-leak-app` 프로세스를 멀티스레드 모드(`MULTI_THREAD_ENABLE=1`)로 실행하면, 초기에는 정상 작동하나 약 2~3초 후 프로세스가 응답을 멈추는 현상이 발생한다. 

프로세스는 여전히 메모리에 존재(PID 유효)하고 CPU나 메모리 변화도 없으나, 로그 출력이 완전히 중단되고 사용자 입력에 전혀 반응하지 않는 상태가 지속된다. 

이는 **두 개 이상의 스레드가 서로 다른 자원을 점유한 채로 상대방의 자원을 무한정 기다리는 교착상태(Circular Wait)**가 발생했음을 시사한다.

---

## 2. Evidence & Logs (증거 자료)

### 2.1 시스템 환경

```bash
MEMORY_LIMIT=256           # 메모리 제한 (MB)
CPU_MAX_OCCUPY=50          # CPU 점유율 제한 (%)
MULTI_THREAD_ENABLE=1      # Before: 다중스레드 활성화
MULTI_THREAD_ENABLE=0      # After: 순차 실행 모드
```

---

### 2.2 Before 케이스 (MULTI_THREAD_ENABLE=1 = Concurrency: True)

#### [부트 메시지]

이미 부트 시퀀스에서 교착상태 경고:

```
==================================================
 [ Agent Initiate ] Resource Check
==================================================
 [ MEMORY ] Limit: 256MB                [ OK ]
 [ CPU    ] Limit: 50%                  [ OK ]
 [ THREAD ] Concurrency: True           [ WARNING ]
--------------------------------------------------
 >>> SYSTEM WARNING: POTENTIAL DEADLOCK IN CONCURRENT MODE.
==================================================
```

#### [앱 내부 로그]

멀티스레드 프로세서 시작 후 정확히 2초 시점에서 로그 중단:

```
2026-06-30 13:29:45,249 [WARNING] [AgentWorker] Initializing concurrent transaction processors...
2026-06-30 13:29:45,249 [WARNING] [System] CAUTION: Strict resource locking is enabled.
2026-06-30 13:29:50,277 [INFO] [Worker-Thread-1] Process Started. Attempting to lock [Shared_Memory_A]...
2026-06-30 13:29:50,277 [INFO] [AgentWorker][Worker-Thread-1] LOCK ACQUIRED: [Shared_Memory_A]. (Holding...)
2026-06-30 13:29:50,277 [INFO] [AgentWorker][Worker-Thread-1] Processing critical data in Memory A...
2026-06-30 13:29:50,278 [INFO] [AgentWorker][Worker-Thread-2] Process Started. Attempting to lock [Socket_Pool_B]...
2026-06-30 13:29:50,278 [INFO] [AgentWorker] Waiting for worker threads to complete transactions...
2026-06-30 13:29:50,278 [INFO] [AgentWorker][Worker-Thread-2] LOCK ACQUIRED: [Socket_Pool_B]. (Holding...)
2026-06-30 13:29:50,279 [INFO] [AgentWorker][Worker-Thread-2] Establishing network connections in Pool B...

2026-06-30 13:29:52,290 [INFO] [AgentWorker][Worker-Thread-1] Need resource [Socket_Pool_B] to finish job.
2026-06-30 13:29:52,290 [INFO] [AgentWorker][Worker-Thread-1] WAITING for [Socket_Pool_B]... (Status: BLOCKED)
                                                                           ↓ Thread-1이 Thread-2가 보유한 Socket_Pool_B 대기

2026-06-30 13:29:52,292 [INFO] [AgentWorker][Worker-Thread-2] Need resource [Shared_Memory_A] to write logs.
2026-06-30 13:29:52,292 [INFO] [AgentWorker][Worker-Thread-2] WAITING for [Shared_Memory_A]... (Status: BLOCKED)
                                                                           ↓ Thread-2가 Thread-1이 보유한 Shared_Memory_A 대기

[ 이후 로그 완전히 중단 - 교착상태 발생 ]
```

#### [프로세스 상태 확인]

프로세스는 살아있으나 무응답 상태:

```bash
$ ps -ef | grep agent
root           8       1  0 12:54 ?        00:00:00 orbstack-agent: ubuntu
sonjehy+    2802   1700  0 13:29 pts/1    00:00:00 [agent-leak-app]  <- 프로세스 존재 (좀비 아님)
sonjehy+    3081    1700  0 13:31 pts/1    00:00:00 grep --color=auto agent
```

**PID 2802 존재 확인** → 프로세스가 강제 종료되지 않은 상태

#### [모니터링 데이터 (monitor.sh)]

프로세스 CPU 및 메모리 변화 완전 정지:

```
[2026-06-30 13:29:43] PID:2802 CPU:%cpu MEM:%mem RSS/VSZ:  8.1  0.0  2240   3152  <- 정상 실행 중
[2026-06-30 13:29:46] PID:2802 CPU:%cpu MEM:%mem RSS/VSZ:  1.3  0.0  2240   3152
[2026-06-30 13:29:49] PID:2802 CPU:%cpu MEM:%mem RSS/VSZ:  0.7  0.0  2240   3152
[2026-06-30 13:29:52] PID:2802 CPU:%cpu MEM:%mem RSS/VSZ:  0.5  0.0  2240   3152  <- 13:29:52 교착상태 발생 (로그상)
[2026-06-30 13:29:55] PID:2802 CPU:%cpu MEM:%mem RSS/VSZ:  0.3  0.0  2240   3152  <- CPU 0.3% (변화 없음)
[2026-06-30 13:29:58] PID:2802 CPU:%cpu MEM:%mem RSS/VSZ:  0.3  0.0  2240   3152  <- CPU 0.3% (변화 없음)
[2026-06-30 13:30:01] PID:2802 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2240   3152  <- CPU 0.2% (정체됨)
[2026-06-30 13:30:04] PID:2802 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2240   3152  <- 변화 없음
[2026-06-30 13:30:07] PID:2802 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2240   3152  <- 변화 없음
[2026-06-30 13:30:10] PID:2802 CPU:%cpu MEM:%mem RSS/VSZ:  0.1  0.0  2240   3152  <- 계속 정체 상태
```

**핵심 증거:**
- PID 2802가 계속 존재 (강제 종료 X)
- CPU: 0.1~0.3% 고정 (추가 연산 0)
- RSS: 2240KB 고정 (메모리 변화 0)
- **로그:** 13:29:52 이후 완전 중단

---

### 2.3 After 케이스 (MULTI_THREAD_ENABLE=0 = Concurrency: False)

#### [부트 메시지]

교착상태 경고 없음:

```
==================================================
 [ Agent Initiate ] Resource Check
==================================================
 [ MEMORY ] Limit: 300MB                [ OK ]
 [ CPU    ] Limit: 50%                  [ OK ]
 [ THREAD ] Concurrency: False          [ OK ]
--------------------------------------------------
 >>> SYSTEM STATUS: STABLE. STARTING WORKLOAD MONITORING...
==================================================
```

#### [앱 내부 로그]

모든 작업이 순차적으로 완료:

```
2026-06-30 13:30:58,844 [INFO] [Scheduler] Task Scheduler Initialized.
2026-06-30 13:30:58,844 [INFO] [Scheduler] Registered Tasks: ['Thread-A', 'Thread-B', 'Thread-C']
2026-06-30 13:30:58,844 [INFO] [Scheduler] Starting task execution...

2026-06-30 13:30:58,845 [INFO] [Thread-A] Task Started. Calculating... (20%)
2026-06-30 13:30:58,896 [INFO] [Thread-A] Calculating... (40%)
2026-06-30 13:30:58,948 [INFO] [Thread-A] Calculating... (60%)
2026-06-30 13:30:59,000 [INFO] [Thread-A] Calculating... (80%)
2026-06-30 13:30:59,051 [INFO] [Thread-A] Task Completed. (100%)  <- Thread-A 완료, 리소스 반납

2026-06-30 13:30:59,103 [INFO] [Thread-B] Task Started. Calculating... (20%)
2026-06-30 13:30:59,155 [INFO] [Thread-B] Calculating... (40%)
2026-06-30 13:30:59,206 [INFO] [Thread-B] Calculating... (60%)
2026-06-30 13:30:59,258 [INFO] [Thread-B] Calculating... (80%)
2026-06-30 13:30:59,310 [INFO] [Thread-B] Task Completed. (100%)  <- Thread-B 완료, 리소스 반납

2026-06-30 13:30:59,361 [INFO] [Thread-C] Task Started. Calculating... (20%)
2026-06-30 13:30:59,413 [INFO] [Thread-C] Calculating... (40%)
2026-06-30 13:30:59,464 [INFO] [Thread-C] Calculating... (60%)
2026-06-30 13:30:59,516 [INFO] [Thread-C] Calculating... (80%)
2026-06-30 13:30:59,568 [INFO] [Thread-C] Task Completed. (100%)  <- Thread-C 완료

2026-06-30 13:30:59,620 [INFO] [Scheduler] All tasks completed.    <- 모든 작업 성공
```

**각 태스크가 순차적으로 시작 → 완료 → 다음 태스크**

#### [모니터링 데이터 (monitor.sh)]

정상적인 프로세스 라이프사이클:

```
[2026-06-30 13:30:56] PROCESS NOT FOUND    <- 시작 전
[2026-06-30 13:30:59] PID:2950 CPU:%cpu MEM:%mem RSS/VSZ:  2.2  0.0  2244   3152  <- 시작
[2026-06-30 13:31:02] PID:2950 CPU:%cpu MEM:%mem RSS/VSZ:  1.0  0.0  2244   3152  <- 정상 실행
[2026-06-30 13:31:05] PID:2950 CPU:%cpu MEM:%mem RSS/VSZ:  0.6  0.0  2244   3152
[2026-06-30 13:31:08] PID:2950 CPU:%cpu MEM:%mem RSS/VSZ:  0.5  0.0  2244   3152
[2026-06-30 13:31:11] PID:2950 CPU:%cpu MEM:%mem RSS/VSZ:  0.4  0.0  2244   3152
[2026-06-30 13:31:14] PID:2950 CPU:%cpu MEM:%mem RSS/VSZ:  0.3  0.0  2244   3152
[2026-06-30 13:31:17] PID:2950 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2244   3152  <- 자연스러운 감소
[2026-06-30 13:31:20] PID:2950 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2244   3152
[2026-06-30 13:31:23] PID:2950 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2244   3152
...
[ 작업 완료 후 정상 종료 예상 ]
```

**모든 지표가 정상 범위에서 진동**

---

## 3. Root Cause Analysis (원인 분석)

### 3.1 교착상태(Deadlock)의 4대 필요조건

교착상태가 발생하려면 다음 **4가지 조건을 모두 만족**해야 한다. 현재 상황이 모두 충족되고 있음:

#### ✅ 1. 상호 배제 (Mutual Exclusion)
자원은 한 번에 한 스레드만 점유할 수 있다:
- `Shared_Memory_A` ↔ Thread-1만 점유 가능
- `Socket_Pool_B` ↔ Thread-2만 점유 가능

#### ✅ 2. 점유 대기 (Hold and Wait)
스레드가 자신이 이미 점유한 자원을 가진 채로 다른 자원을 대기한다:
- Thread-1: `Shared_Memory_A` 점유 중 → `Socket_Pool_B` 대기
- Thread-2: `Socket_Pool_B` 점유 중 → `Shared_Memory_A` 대기

#### ✅ 3. 비선점 (No Preemption)
다른 스레드의 자원을 강제로 회수할 수 없다:
- Thread-1이 Thread-2의 `Socket_Pool_B`를 빼앗을 수 없음
- Thread-2가 Thread-1의 `Shared_Memory_A`를 빼앗을 수 없음

#### ✅ 4. 순환 대기 (Circular Wait)
스레드들이 닫힌 사이클을 형성하며 서로의 자원을 대기한다:

```
┌────────────────────────────────────────────┐
│                                            │
│  Thread-1                  Thread-2        │
│  ┌─────────────┐         ┌─────────────┐  │
│  │ Holding:   │         │ Holding:   │  │
│  │ Memory_A   │         │ Socket_B   │  │
│  │ Waiting:   │         │ Waiting:   │  │
│  │ Socket_B   │◄────────┤ Memory_A   │  │
│  └──────┬──────┘         └─────┬──────┘  │
│         │                      │         │
│         └──────────────────────┘         │
│                                          │
└────────────────────────────────────────────┘

        [Circular Wait 형성]
```

**루프 경로:**
```
Thread-1 (점유 Memory_A)
    ↓
대기 (Socket_B 기다림) ← Thread-2가 보유
    ↓
Thread-2 (점유 Socket_B)
    ↓
대기 (Memory_A 기다림) ← Thread-1이 보유
    ↓
[무한 루프 진입]
```

### 3.2 왜 이 순간에 발생하는가?

**시간 순서 분석:**

```
13:29:50.277  Thread-1: Lock ACQUIRED [Shared_Memory_A]
13:29:50.278  Thread-2: Lock ACQUIRED [Socket_Pool_B]
             ┌─ 이 순간까지는 각자 1개씩만 점유 (OK)
             │
13:29:50.278  AgentWorker: Waiting for threads to complete
             │ ┌─ 여기서 Thread-1, Thread-2가 동시에 추가 자원 요청
             │ │
13:29:52.290  Thread-1: WAITING [Socket_Pool_B]
13:29:52.292  Thread-2: WAITING [Shared_Memory_A]
             │
             └─ 이 순간부터 교착상태 → 더 이상 진행 불가
```

---

## 4. Workaround & Verification (조치 및 검증)

### 4.1 조치 내용

**근본 원인:** 다중스레드 환경에서 리소스 경합으로 인한 교착상태

**임시 조치:** 다중스레드를 비활성화하고 싱글 스레드 순차 실행으로 변경

```bash
# Before
export MULTI_THREAD_ENABLE=1

# After
export MULTI_THREAD_ENABLE=0
```

### 4.2 Before & After 비교

| 항목 | Before (Concurrency: True) | After (Concurrency: False) |
|---|---|---|
| **부트 메시지** | `WARNING: POTENTIAL DEADLOCK` | `OK` |
| **PID 상태** | 존재 (응답 없음) | 존재 (정상) |
| **CPU 변화** | 0.2~0.3% (정체) | 진동 후 자연 감소 |
| **메모리 변화** | 없음 (2240KB 고정) | 없음 (정상) |
| **로그 진행** | 13:29:52에서 중단 | 계속 진행 후 완료 |
| **작업 결과** | ❌ 무한 대기 (교착상태) | ✅ 모든 작업 완료 |
| **종료 상태** | 수동 강제 종료 필요 | 자동 정상 종료 |

### 4.3 검증 결과

- **교착상태 회피**: ✅ 성공 (Concurrency 비활성화로 순차 실행)
- **모든 태스크 완료**: ✅ Thread-A, B, C 순차적 완료
- **프로세스 안정성**: ✅ 로그 출력 정상, CPU 정상 감소
- **자동 종료**: ✅ 모든 작업 완료 후 자동 프로세스 종료

---

## 5. 근본적 해결 방안 (선택)

현재 Workaround(순차 실행)는 **멀티스레드 성능 포기**를 의미한다. 교착상태를 회피하면서도 멀티스레드 이점을 살리려면:

### 5.1 Lock 순서 일관성 유지 (Lock Ordering)

모든 스레드가 자원을 **같은 순서**로 점유하도록 강제:

```
변경 전:
Thread-1: Lock(Memory_A) → Lock(Socket_B)
Thread-2: Lock(Socket_B) → Lock(Memory_A)  ← 순서 다름

변경 후 (권장):
Thread-1: Lock(Memory_A) → Lock(Socket_B)
Thread-2: Lock(Memory_A) → Lock(Socket_B)  ← 같은 순서
         (불가능하면 순서 재정렬)
```

### 5.2 Deadlock Detection (교착상태 감지)

타임아웃 메커니즘으로 무한 대기 방지:

```python
lock_with_timeout(resource, timeout=5)
# 5초 안에 획득 못하면 Release & Retry
```

### 5.3 Resource Hierarchy (자원 계층화)

자원에 우선순위를 부여하고 높은 순위부터 점유:

```
Priority 1: Shared_Memory_A
Priority 2: Socket_Pool_B

모든 스레드: Priority 1 → Priority 2 순서로 Lock
```

### 5.4 Banker's Algorithm (미래 점유 예측)

할당 전에 안전한지 사전 검사 (복잡하지만 완벽)

---

## Summary

**멀티스레드 모드에서 Thread-1과 Thread-2가 서로 다른 자원을 점유한 채로 상대방의 자원을 대기하는 순환 대기(Circular Wait)가 발생했다.** 

교착상태의 4대 조건을 모두 만족하였기에 프로세스가 응답을 멈췄고, 강제 종료 없이는 회복 불가능했다.

**임시 조치:** `MULTI_THREAD_ENABLE=0` (순차 실행)으로 교착상태 회피 및 정상 완료 확인

**장기 개선:** Lock 순서 일관성 유지, 타임아웃 도입, 자원 계층화 등으로 안전한 멀티스레드 구현 필요
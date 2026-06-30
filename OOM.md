# [Bug] OOM (메모리 누수) - 메모리 임계치 도달로 인한 강제 종료

## 1. Description (현상 설명)

`agent-leak-app` 프로세스를 실행하면 초기에는 정상 작동하나, 시간이 경과함에 따라 애플리케이션 내부 힙(Heap) 메모리 사용량이 지속적으로 증가한다. 설정된 메모리 임계치(`MEMORY_LIMIT=256MB`)에 도달하면 내부 메모리 보호 정책(`MemoryGuard`)이 작동하여 프로세스를 강제 종료(`SELF-TERMINATED`)시키는 현상이 발생한다.

---

## 2. Evidence & Logs (증거 자료)

### 2.1 시스템 환경

```bash
MEMORY_LIMIT=256          # 메모리 제한 (MB)
CPU_MAX_OCCUPY=50         # CPU 점유율 제한 (%)
MULTI_THREAD_ENABLE=0     # 다중스레드 비활성화
```

### 2.2 Before 케이스 (MEMORY_LIMIT=256MB)

#### [앱 내부 로그]

메모리가 약 3초 간격으로 25MB씩 선형 증가:

```
2026-06-30 13:12:23,608 [INFO] [MemoryWorker] Current Heap: 25MB
2026-06-30 13:12:26,661 [INFO] [MemoryWorker] Current Heap: 50MB
2026-06-30 13:12:29,716 [INFO] [MemoryWorker] Current Heap: 75MB
2026-06-30 13:12:32,771 [INFO] [MemoryWorker] Current Heap: 100MB
2026-06-30 13:12:35,826 [INFO] [MemoryWorker] Current Heap: 125MB
2026-06-30 13:12:38,882 [INFO] [MemoryWorker] Current Heap: 150MB
2026-06-30 13:12:41,937 [INFO] [MemoryWorker] Current Heap: 175MB
2026-06-30 13:12:44,992 [INFO] [MemoryWorker] Current Heap: 200MB
2026-06-30 13:12:48,047 [INFO] [MemoryWorker] Current Heap: 225MB
2026-06-30 13:12:51,100 [INFO] [MemoryWorker] Current Heap: 250MB
2026-06-30 13:12:54,154 [INFO] [MemoryWorker] Current Heap: 275MB
2026-06-30 13:12:54,154 [CRITICAL] [MemoryGuard] Memory limit exceeded (275MB >= 256MB) / (Recommend Over 256MB)
2026-06-30 13:12:54,155 [CRITICAL] [MemoryGuard] Self-terminating process 1861 to prevent system instability.

>>> [SYSTEM] SELF-TERMINATED (Memory Limit Exceeded) <<<
Killed
```

#### [모니터링 데이터 (monitor.sh)]

프로세스 생명 주기 추적:

```
[2026-06-30 13:12:21] PID:1860 CPU/MEM/RSS: 28.0  0.0  2232
[2026-06-30 13:12:24] PID:1860 CPU/MEM/RSS:  2.1  0.0  2232   <- 메모리 누수 시작
[2026-06-30 13:12:27] PID:1860 CPU/MEM/RSS:  1.1  0.0  2232   <- 계속 실행 중
[2026-06-30 13:12:30] PID:1860 CPU/MEM/RSS:  0.7  0.0  2232
[2026-06-30 13:12:33] PID:1860 CPU/MEM/RSS:  0.5  0.0  2232
[2026-06-30 13:12:36] PID:1860 CPU/MEM/RSS:  0.4  0.0  2232
[2026-06-30 13:12:39] PID:1860 CPU/MEM/RSS:  0.3  0.0  2232
[2026-06-30 13:12:42] PID:1860 CPU/MEM/RSS:  0.3  0.0  2232
[2026-06-30 13:12:45] PID:1860 CPU/MEM/RSS:  0.2  0.0  2232
[2026-06-30 13:12:48] PID:1860 CPU/MEM/RSS:  0.2  0.0  2232
[2026-06-30 13:12:51] PID:1860 CPU/MEM/RSS:  0.2  0.0  2232
[2026-06-30 13:12:54] PROCESS NOT FOUND   <- 정확히 13:12:54 프로세스 종료 (앱 로그와 일치)
[2026-06-30 13:12:57] PROCESS NOT FOUND
```

---

### 2.3 After 케이스 (MEMORY_LIMIT=300MB)

#### [앱 내부 로그]

메모리가 300MB 도달 후 정리(`cleanup`) 실행:

```
2026-06-30 13:15:08,273 [INFO] [MemoryWorker] Current Heap: 25MB
2026-06-30 13:15:11,327 [INFO] [MemoryWorker] Current Heap: 50MB
2026-06-30 13:15:14,384 [INFO] [MemoryWorker] Current Heap: 75MB
2026-06-30 13:15:17,438 [INFO] [MemoryWorker] Current Heap: 100MB
2026-06-30 13:15:20,494 [INFO] [MemoryWorker] Current Heap: 125MB
2026-06-30 13:15:23,547 [INFO] [MemoryWorker] Current Heap: 150MB
2026-06-30 13:15:26,602 [INFO] [MemoryWorker] Current Heap: 175MB
2026-06-30 13:15:29,658 [INFO] [MemoryWorker] Current Heap: 200MB
2026-06-30 13:15:32,712 [INFO] [MemoryWorker] Current Heap: 225MB
2026-06-30 13:15:35,768 [INFO] [MemoryWorker] Current Heap: 250MB
2026-06-30 13:15:38,823 [INFO] [MemoryWorker] Current Heap: 275MB
2026-06-30 13:15:41,878 [INFO] [MemoryWorker] Current Heap: 300MB
2026-06-30 13:15:41,879 [WARNING] [MemoryWorker] Memory Usage Reached Limit (300MB). Starting cleanup...
2026-06-30 13:15:41,884 [INFO] [System] Memory Cache Flushed. Process Stabilized.

>>> [SYSTEM] MEMORY RECOVERED (Cache Cleared) <<<

2026-06-30 13:15:42,585 [INFO] [CpuWorker] Current Load: 44.74%
2026-06-30 13:15:44,698 [INFO] [CpuWorker] Current Load: 39.28%
```

#### [모니터링 데이터 (monitor.sh)]

프로세스가 임계치 도달 후에도 계속 생존:

```
[2026-06-30 13:15:06] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  7.2  0.0  2240   3152
[2026-06-30 13:15:09] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  1.9  0.0  2240   3152
[2026-06-30 13:15:12] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  1.1  0.0  2240   3152
[2026-06-30 13:15:15] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.7  0.0  2240   3152
[2026-06-30 13:15:18] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.6  0.0  2240   3152
[2026-06-30 13:15:21] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.4  0.0  2240   3152
[2026-06-30 13:15:24] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.4  0.0  2240   3152
[2026-06-30 13:15:27] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.3  0.0  2240   3152
[2026-06-30 13:15:30] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.3  0.0  2240   3152
[2026-06-30 13:15:33] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2240   3152
[2026-06-30 13:15:36] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2240   3152
[2026-06-30 13:15:39] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2240   3152
[2026-06-30 13:15:42] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2240   3152
[2026-06-30 13:15:45] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.1  0.0  2240   3152  <- 계속 살아있음
[2026-06-30 13:16:00] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.1  0.0  2240   3152
[2026-06-30 13:16:15] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.1  0.0  2240   3152
[2026-06-30 13:16:30] PID:2103 CPU:%cpu MEM:%mem RSS/VSZ:  0.0  0.0  2240   3152
```

---

## 3. Root Cause Analysis (원인 분석)

### 3.1 메모리 누수 (Memory Leak)

`MemoryWorker` 스레드가 약 3초 간격으로 25MB씩 할당되어 누적되고 있으나, 해당 메모리 블록이 해제되지 않는 전형적인 메모리 누수 패턴이 확인된다.

```
시간 경과에 따른 누적:
t=0s   → 25MB
t=3s   → 50MB  (해제 안 됨)
t=6s   → 75MB  (해제 안 됨)
...
t=51s  → 275MB (임계치 256MB 초과)
```

### 3.2 MemoryGuard 정책 (메모리 보호 정책)

OS 레벨의 OOM Killer 발생 전에 애플리케이션 자체가 내부적으로 메모리 사용량을 모니터링하고 있다. `MEMORY_LIMIT` 환경변수로 임계치를 설정하면:

1. **정상 상태**: 힙 메모리 < MEMORY_LIMIT → 작업 계속
2. **임계치 도달**: 힙 메모리 >= MEMORY_LIMIT → MemoryGuard 활성화
3. **강제 종료**: 프로세스 자체적으로 `SIGKILL` 실행 → 시스템 전체 불안정성 방지

---

## 4. Workaround & Verification (조치 및 검증)

### 4.1 조치 내용

메모리 정리 로직이 안전하게 실행될 수 있는 추가 공간 확보를 위해 `MEMORY_LIMIT` 환경변수를 상향 조정했다.

```bash
# Before
export MEMORY_LIMIT=256

# After
export MEMORY_LIMIT=300
```

**상향 조정 근거:**
- Before: 275MB 도달 후 즉시 강제 종료
- After: 300MB 도달 시 내부 정리 로직 시작
- 추가 공간: 25MB (내부 정리 알고리즘 완료 여유)

### 4.2 Before & After 비교

| 항목 | Before (MEMORY_LIMIT=256MB) | After (MEMORY_LIMIT=300MB) |
|---|---|---|
| **부트 메시지** | `WARNING: Recommend Over 256MB` | `[ OK ]` |
| **최대 힙 도달** | 275MB | 300MB |
| **도달 시점** | 13:12:54 | 13:15:41 |
| **동작** | SELF-TERMINATED | Memory Cache Flushed |
| **결과** | Killed (프로세스 종료) | MEMORY RECOVERED (정상화) |
| **프로세스 생존** | 강제 종료 | 계속 작동 |

---

## 5. 근본적 해결 방안

현재는 `MEMORY_LIMIT` 값을 높여 프로세스가 종료되는 시점을 늦춘 상태이다. 하지만 이는 임시 해결 방법이며, 메모리 누수를 근본적으로 해결하기 위해서는 다음과 같은 개선이 필요하다.

1. **메모리 누수 원인 찾기**
   - 메모리가 계속 증가하는 원인을 확인한다.
   - 사용이 끝난 메모리가 정상적으로 해제되는지 확인한다.

2. **메모리 올바르게 관리하기**
   - 필요한 만큼만 메모리를 할당한다.
   - 사용이 끝난 메모리는 바로 해제한다.

3. **메모리 사용량 관리하기**
   - 메모리 사용량이 계속 증가하지 않도록 주기적으로 확인한다.
   - 불필요한 메모리는 정리하여 다시 사용할 수 있도록 한다.

4. **모니터링 강화**
   - 메모리 사용량을 지속적으로 확인한다.
   - 임계치에 가까워지면 경고를 출력하여 미리 대응할 수 있도록 한다.

---

## Summary

**메모리 누수로 인해 프로세스가 강제 종료되는 현상**을 `MEMORY_LIMIT` 환경변수 조정으로 임시 완화했다. 하지만 **근본 원인인 메모리 누수 제거**를 위해서는 `MemoryWorker` 구현부에서 메모리 할당-해제 로직을 검토하고 개선해야 한다.
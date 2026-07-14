# [Bug] CPU 과점유 - 리소스 제한 임계치에 의한 Cooldown 제어

## 1. Description (현상 설명)

`agent-leak-app` 프로세스 실행 중 `CpuWorker` 스레드가 시작되면서 CPU 사용률이 지속적으로 상승한다. 앱 자체의 CPU 보호 기능은 설정된 CPU 점유율 제한(`CPU_MAX_OCCUPY`)에 도달하면 Cooldown을 실행해 부하를 낮추지만, 이와 별도로 시스템 Watchdog는 부하가 50~55% 부근에 도달하면 즉시 프로세스를 강제 종료(SIGTERM)한다.

높은 제한(`CPU_MAX_OCCUPY=90%`)에서는 앱 자체 cooldown이 발동하기 전에 부하가 Watchdog 강제종료 구간에 먼저 도달해 프로세스가 종료되는 반면, 낮은 제한(`CPU_MAX_OCCUPY=50%`)에서는 cooldown이 위험 구간 진입 전에 먼저 동작하여 프로세스가 안정적으로 유지된다.

---

## 2. Evidence & Logs (증거 자료)

### 2.1 시스템 환경

```bash
MEMORY_LIMIT=256          # 메모리 제한 (MB)
CPU_MAX_OCCUPY=90         # Before: CPU 점유율 제한 (%)
CPU_MAX_OCCUPY=50         # After: CPU 점유율 제한 (%)
MULTI_THREAD_ENABLE=0     # 다중스레드 비활성화
```

---

### 2.2 Before 케이스 (CPU_MAX_OCCUPY=90%)

#### [앱 내부 로그]

CPU 임계치인 50%가 넘어가자 프로그램 kill

```
2026-07-14 13:11:37,174 [INFO] [CpuWorker] Started. Maximum CPU Limit: 90%
2026-07-14 13:11:37,174 [INFO] [CpuWorker] Current Load: 5.00%
2026-07-14 13:11:40,293 [INFO] [CpuWorker] Current Load: 7.35%
2026-07-14 13:11:43,412 [INFO] [CpuWorker] Current Load: 14.26%
2026-07-14 13:11:46,532 [INFO] [CpuWorker] Current Load: 20.87%
2026-07-14 13:11:49,652 [INFO] [CpuWorker] Current Load: 30.62%
2026-07-14 13:11:52,770 [INFO] [CpuWorker] Current Load: 31.22%
2026-07-14 13:11:55,890 [INFO] [CpuWorker] Current Load: 41.02%
2026-07-14 13:11:59,010 [INFO] [CpuWorker] Current Load: 48.16%
2026-07-14 13:12:02,131 [INFO] [CpuWorker] Current Load: 55.41%
2026-07-14 13:12:02,233 [CRITICAL] [CpuWorker] CPU Threshold Violated! (55.410000000000004%).

>>> [SYSTEM] WATCHDOG: INITIATING EMERGENCY ABORT (SIGTERM) <<<

Terminated
```

**패턴 분석:**
- 임계치 도달시 : kill
- Cooldown 빈도 : 없음
- 작업 효율: 낮음 (작업이 자주 중단됨)

#### [모니터링 데이터 (monitor.sh)]

시스템 레벨에서 관찰한 CPU 사용률:

```
[2026-07-14 13:11:35] PID:2273 CPU:%cpu MEM:%mem RSS/VSZ: 46.1  0.0  2236   3152
[2026-07-14 13:11:38] PID:2273 CPU:%cpu MEM:%mem RSS/VSZ:  1.9  0.0  2236   3152
[2026-07-14 13:11:41] PID:2273 CPU:%cpu MEM:%mem RSS/VSZ:  0.9  0.0  2236   3152
[2026-07-14 13:11:44] PID:2273 CPU:%cpu MEM:%mem RSS/VSZ:  0.6  0.0  2236   3152
[2026-07-14 13:11:47] PID:2273 CPU:%cpu MEM:%mem RSS/VSZ:  0.4  0.0  2236   3152
[2026-07-14 13:11:50] PID:2273 CPU:%cpu MEM:%mem RSS/VSZ:  0.3  0.0  2236   3152
[2026-07-14 13:11:53] PID:2273 CPU:%cpu MEM:%mem RSS/VSZ:  0.3  0.0  2236   3152
[2026-07-14 13:11:56] PID:2273 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2236   3152
[2026-07-14 13:11:59] PID:2273 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2236   3152
```

**해석:**
- CPU_MAX_OCCUPY=90%로 설정되어 있어 앱 자체 cooldown은 90%가 되어야 발동
- 하지만 실제 부하가 50~55%대에 도달한 순간 외부 Watchdog가 먼저 SIGTERM으로 강제 종료
- 즉 앱의 자체 보호 로직(cooldown)이 발동하기도 전에 프로세스가 죽어버리는 상황

---

### 2.3 After 케이스 (CPU_MAX_OCCUPY=50%)

#### [앱 내부 로그]

CPU 부하가 더 천천히 상승 → 50% 도달 후에도 비교적 안정적:

```
2026-06-30 13:27:26,674 [INFO] [CpuWorker] Started. Maximum CPU Limit: 50%
2026-06-30 13:27:26,674 [INFO] [CpuWorker] Current Load: 5.00%
2026-06-30 13:27:29,794 [INFO] [CpuWorker] Current Load: 13.18%
2026-06-30 13:27:32,913 [INFO] [CpuWorker] Current Load: 16.85%
2026-06-30 13:27:36,033 [INFO] [CpuWorker] Current Load: 22.31%
2026-06-30 13:27:39,153 [INFO] [CpuWorker] Current Load: 31.19%
2026-06-30 13:27:42,273 [INFO] [CpuWorker] Current Load: 36.50%
2026-06-30 13:27:45,393 [INFO] [CpuWorker] Current Load: 43.68%
2026-06-30 13:27:47,506 [INFO] [CpuWorker] Peak reached (50.00%). Starting cooldown...
                       ↓ 임계치 도달 (첫 번째)
2026-06-30 13:27:48,513 [INFO] [CpuWorker] Current Load: 50.00%
2026-06-30 13:27:51,632 [INFO] [CpuWorker] Current Load: 45.17%  <- Cooldown으로 감소
2026-06-30 13:27:54,752 [INFO] [CpuWorker] Current Load: 42.18%
2026-06-30 13:27:57,871 [INFO] [CpuWorker] Current Load: 36.61%
2026-06-30 13:28:00,992 [INFO] [CpuWorker] Current Load: 34.25%
2026-06-30 13:28:04,112 [INFO] [CpuWorker] Current Load: 27.62%
```

**패턴 분석:**
- 임계치 도달 간격: ~21초 (전 케이스 대비 생존)
- Cooldown 빈도: 적음 (대부분 부하 조절 상태)
- 작업 효율: 높음 (더 높은 CPU 할당으로 연속적 작업 가능)

#### [모니터링 데이터 (monitor.sh)]

시스템 레벨 CPU 사용률:

```
[2026-06-30 13:27:25] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  5.5  0.0  2232   3152  <- 초기 시작
[2026-06-30 13:27:28] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  1.9  0.0  2232   3152
[2026-06-30 13:27:31] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  1.1  0.0  2232   3152
[2026-06-30 13:27:34] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  0.8  0.0  2232   3152
[2026-06-30 13:27:37] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  0.6  0.0  2232   3152
[2026-06-30 13:27:40] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  0.5  0.0  2232   3152  <- 점진적 감소
[2026-06-30 13:27:43] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  0.4  0.0  2232   3152
[2026-06-30 13:27:46] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  0.3  0.0  2232   3152
[2026-06-30 13:27:49] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  0.3  0.0  2232   3152
[2026-06-30 13:27:52] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  0.3  0.0  2232   3152
[2026-06-30 13:27:55] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2232   3152  <- 더 안정적
[2026-06-30 13:28:00] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  0.2  0.0  2232   3152
[2026-06-30 13:28:10] PID:2515 CPU:%cpu MEM:%mem RSS/VSZ:  0.1  0.0  2232   3152
```

**해석:**
- 초기 CPU 부하 후 안정적으로 낮아짐
- Before 대비 덜 자주 제어됨 (더 높은 CPU 할당으로 작업 지속 가능)

---

## 3. Root Cause Analysis (원인 분석)

### 3.1 CPU 부하 상승 메커니즘

CpuWorker는 연산을 계속 수행하면서 CPU 사용량이 점점 증가한다. 동시에 `MemoryWorker`와 병렬 실행되므로 전체 CPU 사용량도 함께 증가한다.

```
시간 흐름에 따른 부하 곡선:
10%
/\/\/\/...
50%
 /\  /...
/  \/
```

### 3.2 CPU 보호 정책

CPU 부하가 `CPU_MAX_OCCUPY` 환경변수로 설정된 임계치를 넘으면:

1. **부하 감지**: 프로그램이 CPU 사용량을 계속 확인한다.
2. **임계치 초과**: Current Load >= MAX_OCCUPY 감지
3. **Cooldown 실행**: 연산 속도 낮춤
4. **회복 대기**: 부하가 임계치 이하로 내려갈 때까지 대기
5. **작업 재개**: 부하 충분히 낮아지면 다시 부하 증가

### 3.3 높은 제한(90%)의 문제점

- **cooldown 발동 지연**: 앱 자체 cooldown 임계치가 90%로 설정되어 있어, 실제 부하가 낮은 구간에서는 cooldown이 동작하지 않음
- **Watchdog 선제 개입**: 부하가 50~55% 부근에 도달하면 시스템 Watchdog가 즉시 SIGTERM으로 프로세스를 강제 종료
- **결과**: 앱의 자체 보호 로직이 발동할 기회조차 없이 프로세스가 종료됨

### 3.4 낮은 제한(50%)의 이점

- **선제적 cooldown 발동**: CPU_MAX_OCCUPY를 50%로 낮추면 위험 구간(50~55%) 진입 직전에 앱 자체 cooldown이 먼저 동작
- **Watchdog 임계치 회피**: cooldown으로 부하가 낮아지므로 Watchdog의 강제종료 조건에 도달하지 않음
- **작업 연속성 확보**: 프로세스가 종료되지 않고 cooldown-재개를 반복하며 안정적으로 실행됨

---

## 4. Workaround & Verification (조치 및 검증)

### 4.1 조치 내용

앱 자체 cooldown이 Watchdog 강제종료 임계치보다 먼저 발동하도록 CPU 임계치를 하향 조정했다.

```bash
# Before
export CPU_MAX_OCCUPY=90

# After
export CPU_MAX_OCCUPY=50
```

**하향 조정 근거:**
- Before(90%): cooldown 발동이 너무 늦어 Watchdog에 의해 강제 종료됨 (비정상 종료)
- After(50%): cooldown이 위험 구간 진입 전에 발동하여 프로세스가 안정적으로 유지됨 (정상 실행)

### 4.2 Before & After 비교

| 항목 | Before (CPU_MAX_OCCUPY=90%) | After (CPU_MAX_OCCUPY=50%) |
|---|---|---|
| **cooldown 임계치** | 90.00% (도달 전 강제종료됨) | 50.00% |
| **강제종료/Peak 발생 시간** | ~25초 (Watchdog Kill) | ~21초 (Cooldown) |
| **Cooldown 발생 빈도** | 없음 (cooldown 전에 kill) | 발생함 |
| **부하 상승 속도** | 빠르게 55%대까지 상승 후 강제종료 | 완만하게 50%까지 상승 후 cooldown 반복 |
| **최대 부하 상태** | 55% 부근에서 SIGTERM | 50% 부근에서 cooldown으로 제어 |
| **작업 연속성** | 없음 (프로세스 종료) | 있음 |
| **프로세스 상태** | 강제 종료 (SIGTERM) | 정상 (cooldown으로 제어됨) |

### 4.3 검증 결과

- **강제종료 방지**: 성공 (Watchdog Kill 발생 → Cooldown으로 정상 유지)
- **부하 제어 안정성**: 확인 (cooldown이 위험 구간 진입 전에 선제적으로 동작)
- **작업 연속성 확보**: 증명 (프로세스 종료 없이 cooldown-재개 반복)
- **시스템 영향**: 최소 (다른 프로세스 지연 없음)

---

## 5. 추가 고찰

### 5.1 CPU_MAX_OCCUPY 최적 값

```
10%  → 너무 낮음 (자주 제어, 비효율)
30%  → 중간 선택지 (빈도 있지만 작업 가능)
50%  → 권장 (충분한 작업 여유 + 안정성)
100% → 너무 높음 (다른 프로세스 영향 위험)
```

### 5.2 멀티코어 시스템에서의 고려사항

- 단일 스레드: 1 코어만 사용 → CPU 사용률이 낮게 표시될 수 있음
- 멀티코어: 여러 코어 활용 → CPU 사용률이 높게 표시됨
- 본 테스트: 단일 코어 또는 제한된 환경에서 실행되었을 가능성

### 5.3 코드 레벨 개선 방안

1. **알고리즘 최적화**: O(n²) → O(n log n)으로 개선
2. **Busy-Waiting 제거**: sleep(0.01) 등으로 CPU 절약
3. **멀티스레드 활용**: (Deadlock 주의) 작업 병렬화
4. **CPU 선친화성**: 특정 코어에만 바인드하여 제어

---

## Summary

**CPU 과점유를 제어하는 Watchdog 정책**이 정상 작동하고 있으며, `CPU_MAX_OCCUPY` 환경변수로 유연한 제어가 가능함을 확인했다. 

**임계치 90%** → **임계치 50%**로 하향 조정함으로써 Watchdog에 의한 강제 종료를 방지하고 프로세스 안정성을 확보했다. 다만 **장기적 개선**을 위해서는 `CpuWorker` 알고리즘을 최적화하고 Busy-Waiting을 제거하는 코드 수정이 권장된다.
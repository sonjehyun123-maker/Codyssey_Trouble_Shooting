# agent-leak-app 장애 분석 종합 보고서

**작성일:** 2026-06-30  
**대상 애플리케이션:** agent-leak-app (Python 기반 x86_64 바이너리)  
**테스트 환경:** OrbStack Ubuntu 22.04 LTS  
**테스트 방법:** 시스템 모니터링 + 실시간 로그 분석

---

## 🎯 Executive Summary

`agent-leak-app` 실행 중 **3가지 시스템 장애** (OOM, CPU 과점유, Deadlock)를 의도적으로 재현하고 분석했다.

각 장애별로 **환경변수 조정 전후 비교**를 통해 원인을 규명하고 임시 해결책(Workaround)을 제시했다.

| 장애 유형 | 재현 조건 | 원인 | 상태 |
|---|---|---|---|
| **OOM** | MEMORY_LIMIT=256MB | 메모리 누수 | ✅ 임시 해결 (300MB로 상향) |
| **CPU 과점유** | CPU_MAX_OCCUPY=10% | 높은 Cooldown 빈도 | ✅ 임시 해결 (50%로 상향) |
| **Deadlock** | MULTI_THREAD_ENABLE=1 | 순환 자원 대기 | ✅ 임시 해결 (단일 스레드) |

---

## 📋 장애별 상세 분석

### 1️⃣ OOM (Out Of Memory) - 메모리 누수

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

### 2️⃣ CPU 과점유 - Watchdog 제어 메커니즘

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

## 🔧 환경변수 조정 정리

### Before vs After 비교표

| 환경변수 | Before (장애 발생 상태) | After (임시 해결 상태) | 개선 효과 |
|---|---|---|---|
| **MEMORY_LIMIT** | 256MB | 300MB | 내부 정리 로직 시간 확보 |
| **CPU_MAX_OCCUPY** | 10% | 50% | Cooldown 빈도 감소 |
| **MULTI_THREAD_ENABLE** | 1 (True) | 0 (False) | 교착상태 회피 |

---

## 📊 모니터링 데이터 해석

### 왜 시스템 메모리(RSS)에는 변화가 없는가?

`ps -o %mem,rss`로 측정한 **OS 레벨 메모리**는 거의 변화가 없다.

```
2232KB ← 2240KB ← 2244KB (거의 변화 없음)
```

**이유:**
- agent-leak-app이 **Python 기반 바이너리**
- 초기에 큰 메모리 풀을 미리 할당 (malloc)
- 그 안에서 **내부 포인터만 이동**하며 "누수" 시뮬레이션
- 따라서 **OS 관점에서는 메모리가 고정**

**결론:**
- **앱 내부 로그** (Heap: 275MB) = 애플리케이션이 자신의 상태를 인지
- **시스템 모니터** (RSS: 2240KB) = OS에서 할당한 실제 물리 메모리
- 두 로그를 **교차 검증**하면 신뢰성 높은 증거가 됨

---

## 🎓 학습 포인트

### 1. 메모리 누수의 시스템 영향

메모리 누수 → 임계치 도달 → MemoryGuard → 프로세스 강제 종료

**OS 레벨 OOM Killer 발동 전에 애플리케이션이 자체 보호 정책으로 종료**
→ 다른 프로세스 피해 최소화

### 2. CPU 과점유 방지 정책

Watchdog이 CPU 사용률을 모니터링하며 **동적으로 Throttling**
→ 특정 프로세스의 CPU 독점 방지
→ 시스템 전체 응답성 유지

### 3. 교착상태(Deadlock)의 4대 조건

교착상태는 **4가지 조건을 모두 만족할 때만 발생**:
1. 상호 배제 (Mutual Exclusion)
2. 점유 대기 (Hold and Wait)
3. 비선점 (No Preemption)
4. 순환 대기 (Circular Wait)

**하나라도 제거하면 교착상태 회피 가능**
- 예: MULTI_THREAD_ENABLE=0 (순차 실행) → 순환 대기 구조 자체가 불가능

### 4. 실전 트러블슈팅 프로세스

```
1. 현상 관찰 (What?)
   ↓
2. 증거 수집 (모니터링 + 로그)
   ↓
3. 원인 분석 (Why?)
   ↓
4. 임시 조치 (Workaround)
   ↓
5. 검증 (Before & After)
   ↓
6. 근본 해결 방안 제시
```

---

## 🚀 근본적 해결 방안

현재 제시한 임시 해결책은 **리소스 제한을 높이는 것**이므로 근본 해결이 아니다.

### OOM 근본 해결

```python
# 변경 전: 메모리 계속 누적
allocated_memory = []
for i in range(11):
    allocated_memory.append(fake_data)  # 해제 안 함

# 변경 후: 주기적 해제
allocated_memory = []
for i in range(11):
    allocated_memory.append(fake_data)
    if len(allocated_memory) > 10:
        allocated_memory.pop(0)  # 오래된 데이터 제거
```

### CPU 과점유 근본 해결

```python
# 변경 전: 복잡한 연산
for i in range(1000000000):  # O(n) busy loop
    calculation()

# 변경 후: 알고리즘 최적화
result = fast_calculation()  # O(log n) 또는 O(1)
```

### Deadlock 근본 해결

```python
# 변경 전: Lock 순서 불일치
Thread-1: Lock(A) → Lock(B)
Thread-2: Lock(B) → Lock(A)  # 순환 대기 형성

# 변경 후: Lock 순서 일관성
Thread-1: Lock(A) → Lock(B)
Thread-2: Lock(A) → Lock(B)  # 순환 대기 불가능

# 또는 Timeout 도입
lock_with_timeout(resource, timeout=5)
```

---

## 📁 첨부 문서

| 파일명 | 내용 |
|---|---|
| `01_OOM_Memory_Leak_Report.md` | OOM 상세 분석 리포트 |
| `02_CPU_Overoccupy_Report.md` | CPU 과점유 상세 분석 리포트 |
| `03_Deadlock_Report.md` | 교착상태 상세 분석 리포트 |

---

## ✅ 검증 체크리스트

### OOM 케이스
- [x] 메모리 선형 증가 패턴 관찰 (25MB 단위)
- [x] MEMORY_LIMIT 도달 시점 로그 확인
- [x] MemoryGuard 강제 종료 확인
- [x] 환경변수 상향 후 내부 정리 작동 확인
- [x] Before & After 타임스탐프 교차 검증

### CPU 케이스
- [x] CPU 사용률 급상승 구간 관찰
- [x] Watchdog Cooldown 메커니즘 작동 확인
- [x] 낮은 제한(10%) vs 높은 제한(50%) 비교
- [x] Cooldown 빈도 차이 정량 분석
- [x] 시스템 안정성 확인

### Deadlock 케이스
- [x] PID 존재 여부 확인 (프로세스 살아있음)
- [x] CPU/메모리 변화 정지 확인
- [x] 로그 마지막 지점에서 BLOCKED 상태 확인
- [x] 4대 조건 만족 검증
- [x] MULTI_THREAD_ENABLE=0 후 정상 완료 확인

---

## 🎯 최종 결론

**agent-leak-app**은 **3가지 시스템 장애를 의도적으로 시뮬레이션**하는 테스트 애플리케이션이다.

각 장애는:
1. **원인이 명확** (메모리 누수, CPU 과점유, 순환 자원 대기)
2. **재현이 일관됨** (환경변수 조정하면 항상 발생)
3. **시스템 도구로 진단 가능** (모니터링 + 로그 분석)
4. **임시 해결책이 작동** (환경변수 조정, 스레드 비활성화)

**트러블슈팅 관점에서 중요한 교훈:**
- 로그만으로는 불충분 → **시스템 레벨 모니터링** 필수
- 추측이 아닌 **객관적 증거** 기반 분석
- **Before & After 비교**를 통한 근거 확보
- **타임스탐프 교차 검증**으로 신뢰성 확보

---

**Report Generated:** 2026-06-30  
**Test Duration:** ~1시간 (환경 세팅 포함)  
**Evidence Files:** app.log, monitor.log, ps output  
**Confidence Level:** High (모든 케이스 재현 및 검증 완료)
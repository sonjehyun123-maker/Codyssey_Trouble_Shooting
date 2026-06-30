# [Bug] Deadlock (교착상태) - 멀티스레드 환경에서의 무한 대기

## 1. Description (현상 설명)

`agent-leak-app`을 멀티스레드 모드(`MULTI_THREAD_ENABLE=1`)로 실행하면 처음에는 정상적으로 동작하지만, 약 2~3초 후 프로그램이 더 이상 응답하지 않는 현상이 발생하였다.

프로세스는 종료되지 않고 계속 실행 중이지만 로그 출력이 중단되고 작업도 진행되지 않았다. 이는 두 개의 스레드가 서로가 사용하는 자원을 기다리면서 교착상태(Deadlock)가 발생한 것이다.

---

## 2. Evidence & Logs (증거 자료)

### 2.1 시스템 환경

```bash
MEMORY_LIMIT=256
CPU_MAX_OCCUPY=50
MULTI_THREAD_ENABLE=1      # Before
MULTI_THREAD_ENABLE=0      # After
```

---

### 2.2 Before (MULTI_THREAD_ENABLE=1)

#### 부트 메시지

```
==================================================
 [ MEMORY ] Limit: 256MB                [ OK ]
 [ CPU    ] Limit: 50%                  [ OK ]
 [ THREAD ] Concurrency: True           [ WARNING ]
--------------------------------------------------
 >>> SYSTEM WARNING: POTENTIAL DEADLOCK IN CONCURRENT MODE.
==================================================
```

멀티스레드 모드 실행 시 교착상태가 발생할 수 있다는 경고가 출력되었다.

---

#### 앱 내부 로그

```
2026-06-30 13:29:50,277 [Worker-Thread-1] LOCK ACQUIRED: [Shared_Memory_A]
2026-06-30 13:29:50,278 [Worker-Thread-2] LOCK ACQUIRED: [Socket_Pool_B]

2026-06-30 13:29:52,290 [Worker-Thread-1] WAITING for [Socket_Pool_B]...
                                  ↓ Socket_Pool_B 대기

2026-06-30 13:29:52,292 [Worker-Thread-2] WAITING for [Shared_Memory_A]...
                                  ↓ Shared_Memory_A 대기

[이후 로그 중단]
```

두 스레드가 서로 필요한 자원을 기다리면서 더 이상 작업이 진행되지 않았다.

---

#### 프로세스 상태

```bash
$ ps -ef | grep agent

sonjehy+ 2802 ... agent-leak-app
```

프로세스는 종료되지 않았으며 PID도 그대로 유지되었다.

---

#### monitor.sh

```
[13:29:49] CPU: 0.7%
[13:29:52] CPU: 0.5%
[13:29:55] CPU: 0.3%
[13:29:58] CPU: 0.3%
[13:30:01] CPU: 0.2%
```

교착상태가 발생한 이후 CPU 사용량 변화가 거의 없었으며 프로그램도 더 이상 진행되지 않았다.

---

### 2.3 After (MULTI_THREAD_ENABLE=0)

#### 부트 메시지

```
==================================================
 [ MEMORY ] Limit: 300MB                [ OK ]
 [ CPU    ] Limit: 50%                  [ OK ]
 [ THREAD ] Concurrency: False          [ OK ]
--------------------------------------------------
 >>> SYSTEM STATUS: STABLE.
==================================================
```

멀티스레드를 비활성화하자 경고 메시지가 출력되지 않았다.

---

#### 앱 내부 로그

```
Thread-A Started
Thread-A Completed

Thread-B Started
Thread-B Completed

Thread-C Started
Thread-C Completed

All tasks completed.
```

모든 작업이 순서대로 정상적으로 완료되었다.

---

#### monitor.sh

```
[13:30:59] CPU: 2.2%
[13:31:02] CPU: 1.0%
[13:31:05] CPU: 0.6%
[13:31:08] CPU: 0.5%
[13:31:11] CPU: 0.4%
```

프로세스가 정상적으로 실행되었으며 CPU 사용량도 자연스럽게 감소하였다.

---

## 3. Root Cause Analysis (원인 분석)

### 3.1 교착상태(Deadlock)의 4가지 조건

교착상태는 다음 네 가지 조건이 모두 만족될 때 발생한다.

#### 1. 상호 배제 (Mutual Exclusion)

하나의 자원은 동시에 하나의 스레드만 사용할 수 있다.

#### 2. 점유 대기 (Hold and Wait)

스레드가 자신이 사용하는 자원을 유지한 채 다른 자원을 기다린다.

#### 3. 비선점 (No Preemption)

다른 스레드가 사용하는 자원을 강제로 가져올 수 없다.

#### 4. 순환 대기 (Circular Wait)

두 스레드가 서로의 자원을 기다리면서 무한 대기 상태가 된다.

```
Thread-1
 Memory_A 사용
      │
      ▼
 Socket_B 대기

Thread-2
 Socket_B 사용
      │
      ▼
 Memory_A 대기
```

이 네 가지 조건이 모두 만족되어 교착상태가 발생하였다.

---

## 4. Workaround & Verification (조치 및 검증)

### 4.1 조치 내용

교착상태를 방지하기 위해 멀티스레드를 비활성화하고 순차 실행 방식으로 변경하였다.

```bash
# Before
export MULTI_THREAD_ENABLE=1

# After
export MULTI_THREAD_ENABLE=0
```

---

### 4.2 Before & After 비교

|항목|Before|After|
|---|---|---|
|멀티스레드|사용|미사용|
|프로세스 상태|응답 없음|정상 실행|
|로그 출력|중단|정상|
|CPU 변화|거의 없음|자연스럽게 감소|
|작업 결과|교착상태 발생|모든 작업 완료|

---

### 4.3 검증 결과

- 교착상태가 발생하지 않았다.
- 모든 작업이 정상적으로 완료되었다.
- 로그가 중단되지 않고 끝까지 출력되었다.
- 프로그램이 정상적으로 종료되었다.

---

## 5. 근본적 해결 방안

현재 방법은 멀티스레드를 끄는 임시 해결 방법이다. 멀티스레드를 유지하면서 교착상태를 방지하려면 다음과 같은 개선이 필요하다.

### 자원 사용 순서 통일

모든 스레드가 같은 순서로 자원을 사용하도록 하면 교착상태를 예방할 수 있다.

### 일정 시간 후 다시 시도

자원을 일정 시간 동안 얻지 못하면 작업을 중단하고 다시 시도하도록 한다.

### 자원 관리 방법 개선

자원의 우선순위를 정하여 항상 같은 순서로 접근하도록 하면 교착상태가 발생할 가능성을 줄일 수 있다.

---

# Summary

멀티스레드 환경에서 두 개의 스레드가 서로의 자원을 기다리면서 교착상태가 발생하였다.

이를 해결하기 위해 멀티스레드를 비활성화하여 순차적으로 작업을 수행하도록 변경하였고, 모든 작업이 정상적으로 완료되는 것을 확인하였다.

앞으로는 자원을 사용하는 순서를 통일하거나 일정 시간 이후 다시 시도하는 방법 등을 적용하면 교착상태를 예방할 수 있다.
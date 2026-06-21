# Техническая документация компилятора dhjsjs

> Внутреннее устройство языка dhjsjs, компилятора и рантайма.
> Для разработчиков и интересующихся.

---

## Оглавление

1. [Архитектура](#1-архитектура)
2. [Синтаксис языка](#2-синтаксис-языка)
3. [Парсер (parser.zig)](#3-парсер-parserzig)
4. [Генератор кода (codegen.zig)](#4-генератор-кода-codegenzig)
5. [Компилятор (compiler.zig)](#5-компилятор-compilerzig)
6. [Типы данных](#6-типы-данных)
7. [Встроенные функции (builtins)](#7-встроенные-функции-builtins)
8. [Системные вызовы (sys.zig)](#8-системные-вызовы-syszig)
9. [Графическая подсистема](#9-графическая-подсистема)
10. [Сеть и HTTP](#10-сеть-и-http)
11. [Звуковая подсистема](#11-звуковая-подсистема)
12. [Android бэкенд](#12-android-бэкенд)
13. [Формат ELF](#13-формат-elf)
14. [Внутреннее устройство GUI](#14-внутреннее-устройство-gui)
15. [Паросочетание вызовов через точку (http.get)](#15-паросочетание-вызовов-через-точку-httpget)

---

## 1. Архитектура

### Общая схема

```
Исходный код (.dhjs)
    │
    ▼
┌─────────────┐
│   Лексер    │ токены
│ (lexer.zig) │
└─────────────┘
    │
    ▼
┌─────────────┐
│   Парсер    │ AST (Abstract Syntax Tree)
│(parser.zig) │
└─────────────┘
    │
    ▼
┌─────────────┐
│ Компилятор  │ x86-64 машинный код
│(compiler.zig)│
└─────────────┘
    │
    ▼
┌─────────────┐
│  Кодоген    │ ELF64 исполняемый файл
│(codegen.zig)│
└─────────────┘
    │
    ▼
┌─────────────┐
│  Бинарник   │ ./program
│             │
└─────────────┘
```

### Файлы исходного кода

| Файл | Строк | Назначение |
|------|-------|------------|
| `lexer.zig` | 207 | Разбивает исходный код на токены |
| `parser.zig` | 836 | Строит AST из токенов |
| `codegen.zig` | 623 | x86-64 эмиттер машинных инструкций |
| `codegen_arm.zig` | 522 | ARM64 эмиттер |
| `codegen_rv.zig` | 271 | RISC-V 32bit эмиттер |
| `compiler.zig` | 2608 | Компилятор AST → машкод (x86-64) |
| `compiler_arm.zig` | 789 | Компилятор ARM64 |
| `compiler_rv.zig` | 464 | Компилятор RISC-V |
| `sys.zig` | 650+ | Системные вызовы и обёртки |
| `display.zig` | 84 | Абстракция графических бэкендов |
| `x11.zig` | 416 | X11 протокол |
| `wayland.zig` | 374 | Wayland протокол |
| `win32.zig` | 239 | Windows GDI |
| `gui.zig` | 1380 | Система виджетов |
| `gui_ext.zig` | 534 | Расширенные виджеты |
| `render.zig` | 468 | 2D рендерер |
| `http_client.zig` | 218 | HTTP клиент (исполняемый) |
| `audio.zig` | 830 | Декодеры аудио |
| `main.zig` | 336 | IDE — точка входа |
| `cli.zig` | 675 | CLI компилятор |

### Целевые архитектуры

x86-64 (Linux), ARM64 (Linux, Android), RISC-V 32-bit (ESP32), Windows x86-64

---

## 2. Синтаксис языка

### Лексика

Язык использует ключевые слова на русском и английском:

```
fn       — объявление функции
hui/var  — объявление переменной
if       — условие
uebok    — else (иначе)
while    — цикл
return   — возврат из функции
struct   — объявление структуры
true     — истина
false    — ложь
null     — пустое значение
```

### Типы литералов

```
42        — целое число (int)
"текст"   — строка (string)
true      — булево значение
```

### Операторы

```
Арифметика:    +  -  *  /  %
Сравнение:    ==  !=  <  >  <=  >=
Логические:   &&  ||  !
Присваивание: =
Склейка строк: +
```

### Синтаксис функции

```
fn имя(арг1, арг2, ...) {
    тело
}

fn имя(арг1, арг2, ...) {
    return значение
}
```

### Синтаксис структуры

```
struct Имя {
    поле1: тип
    поле2: тип
}
```

Создание: `Имя{ поле1: значение, поле2: значение }`
Доступ: `переменная.поле`

### Выражения

```
hui x = (10 + 5) * 2 / 3
hui y = x > 0 && x < 100
```

---

## 3. Парсер (parser.zig)

### Этапы парсинга

Парсер — рекурсивный спуск (recursive descent). Он читает токены слева направо
и строит AST.

### Типы узлов AST (30+ видов)

```
.no_node
.int_lit       — целое число
.str_lit       — строка
.ident         — идентификатор
.call          — вызов функции
.binary        — бинарная операция (+ - * / == < > && ||)
.unary         — унарная операция (- !)
.assign        — присваивание
.var_decl      — объявление переменной
.fn_decl       — объявление функции
.if_stmt       — условие
.while_loop    — цикл
.return_stmt   — возврат
.struct_decl   — объявление структуры
.struct_init   — создание структуры
.field_access  — доступ к полю (.name)
.block         — блок кода в { }
```

### Структура узла

```zig
AstNode {
    kind: NodeKind,          // тип узла
    first_child: NodeIdx,    // первый дочерний узел
    next_sibling: NodeIdx,   // следующий сосед
    val_start: usize,        // начало текста в исходнике
    val_len: usize,          // длина текста
    line: u32,               // строка в исходнике
    col: u32,                // столбец
}
```

### Особые случаи

**Парсинг `http.get(...)`**:
Парсер обнаруживает последовательность `ident . ident ( )` и создаёт один узел `.call`
с именем, объединяющим обе части через точку: `http.get`. Это позволяет компилятору
сопоставлять такой вызов с builtin-функцией.

---

## 4. Генератор кода (codegen.zig)

### Система кодирования инструкций

`CodeBuffer` — это динамический массив байт (4096, 8192, 12288 байт). Он растёт
по необходимости. Каждая инструкция кодируется через методы:

```
movRR(dst, src)          — mov reg, reg
movRImm64(r, val)        — mov reg, imm64
addRR(dst, src)          — add reg, reg
subRImm32(r, val)        — sub reg, imm32
pushR(r)                 — push reg
popR(r)                  — pop reg
cmpRImm32(r, val)        — cmp reg, imm32
syscall()                — syscall
jmpRel32(off)            — jmp rel32
jeRel32(off)             — je rel32
jneRel32(off)            — jne rel32
jlRel32(off)             — jl rel32
jleRel32(off)            — jle rel32
callRel32(off)           — call rel32
```

### REX префиксы

Для 64-битных инструкций автоматически проставляется REX.W префикс.
Для инструкций с r8–r15 проставляется REX.B.

### Формат ELF64

`buildElf64()` создаёт полноценный ELF64 исполняемый файл:

```
ELF Header (64-bit)
  e_machine = EM_X86_64
  e_entry = точка входа

Program Headers:
  PT_LOAD (code) — сегмент кода (R|X)
  PT_LOAD (data) — сегмент данных (R|W)

Sections (опционально):
  .text — код
  .rodata — строки, read-only данные
```

Исполняемый файл — statically linked, без libc.

---

## 5. Компилятор (compiler.zig)

### Основной цикл компиляции

```
compile(ast, pool)
  для каждого узла AST на верхнем уровне:
    если это fn_decl → запомнить функцию
    если это struct_decl → запомнить структуру

  найти main()
  скомпилировать тело main() в код
  добавить пролог (push rbp, mov rbp, rsp)
  добавить эпилог (pop rbp, ret)
  для каждой вызванной функции:
    скомпилировать её тело
  сшить всё в ELF
```

### Компиляция выражений

`compileExprNode(node, pool, cb, vars, vc, errs)`:
- для int_lit: `mov rax, imm64`
- для str_lit: `lea rax, [rip+offset]` + `jmp` через строку
- для ident: чтение переменной (из стека или регистра)
- для binary: компиляция левой части (rax), сохранение на стек (push), компиляция правой части (rax), pop в rcx, выполнение операции
- для call: компиляция аргументов, push на стек, вызов функции или builtin

### Система переменных

Переменные хранятся на стеке. Компилятор отслеживает смещение каждой переменной
относительно RBP:

```zig
Var {
    name: []const u8,
    offset: i32,    // смещение от rbp (отрицательное = ниже rbp)
    depth: usize,   // глубина вложенности (для областей видимости)
}
```

Доступ к переменной: `[rbp + offset]`.

### Пролог и эпилог функции

```
Пролог:
  push rbp
  mov rbp, rsp
  sub rsp, N    // выделить место под локальные переменные

Эпилог:
  mov rsp, rbp
  pop rbp
  ret
```

### Вызов функции

Для вызова функции компилятор:
1. Компилирует аргументы (результат в rax, push-ит на стек)
2. Генерирует `call rel32` на функцию
3. Очищает стек от аргументов (`add rsp, N*8`)

Если функция не определена, но есть builtin с таким именем — компилируется встроенный код.

---

## 6. Типы данных

### Числа (int)

Целые числа 64-битные (знаковые). Хранятся:
- в регистрах (rax, rcx, rdx, r8-r15)
- на стеке (8 байт)
- в структурах (последовательно в памяти)

### Строки (string)

Строки хранятся как указатель на данные в коде (RIP-relative).
Для строковых литералов компилятор генерирует:

```
lea rax, [rip+2]    ; rax = адрес строки
jmp over_string     ; прыжок через строку
db "строка", 0      ; данные строки (null-terminated)
over_string:
; rax указывает на "строка"
```

Строки НЕ динамические — они существуют в памяти до конца программы.

### Структуры

Структуры — это последовательность полей в памяти.
Поля выравниваются по 8 байт (каждое поле — u64).
Размер структуры = количество_полей × 8.

```
struct Point { x: int, y: int }
// в памяти: [x (8 байт)] [y (8 байт)]
// Point.x = [rbp + offset]
// Point.y = [rbp + offset + 8]
```

---

## 7. Встроенные функции (builtins)

Всего ~55+ встроенных функций. Они делятся на категории:

### Системные вызовы (прямые мосты в syscall)

Каждый builtin из этой категории просто генерирует syscall:

```
if (eq(name, "close")) {
    compileExprNode(first_child, ...); // rax = fd
    mov rdi, rax
    mov rax, 3       // SYS_CLOSE
    syscall
}
```

### Составные builtins

Некоторые builtins генерируют последовательность инструкций:

**fork-via-builtin** (guiApp, http.get, http.post, resolve):
1. pipe()
2. fork()
3. child: dup2, close, execve
4. parent: close, read, waitpid

### HTTP builtins

`http.get(host, path)` — генерирует код:
1. pipe() — создаёт канал
2. fork() — создаёт процесс
3. child:
   - close(pipe_read)
   - dup2(pipe_write, 1) — перенаправляет stdout в pipe
   - строит argv = ["http_client", "GET", host, path, NULL]
   - execve("./http_client", argv, NULL)
4. parent:
   - close(pipe_write)
   - read(pipe_read, buffer, 8192) — читает ответ
   - wait(NULL) — ждёт ребёнка
   - возвращает указатель на буфер с ответом

`http.post(host, path, body)` — аналогично, но argv = ["http_client", "POST", host, path, body]

`resolve(hostname)` — аналогично, читает 4 байта IP через pipe

---

## 8. Системные вызовы (sys.zig)

### Linux x86-64

Все системные вызовы Linux — через прямые `syscall` инструкции.
Номер вызова в `rax`, аргументы в `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`.

```
pub fn read(fd: i32, buf: [*]u8, len: usize) isize {
    return @bitCast(syscall3(SYS_READ,
        @as(usize, @bitCast(@as(isize, fd))),
        @intFromPtr(buf), len));
}
```

### Windows (Winsock)

Условная компиляция через `comptime is_windows`:
```
if (comptime is_windows) {
    // Win32 API через extern
    const kernel32 = extern "Kernel32" fn(...) ...;
}
```

Для Linux все Win32 вызовы — стабы, которые вызывают `unreachable`.

### Таблица syscall-констант

```
SYS_READ=0, SYS_WRITE=1, SYS_OPEN=2, SYS_CLOSE=3,
SYS_STAT=4, SYS_FSTAT=5, SYS_LSEEK=8, SYS_MMAP=9,
SYS_MUNMAP=11, SYS_BRK=12, SYS_PIPE=22, SYS_DUP=32,
SYS_DUP2=33, SYS_NANOSLEEP=35, SYS_GETPID=39,
SYS_SOCKET=41, SYS_CONNECT=42, SYS_ACCEPT=43,
SYS_SEND=44, SYS_RECV=45, SYS_BIND=49, SYS_LISTEN=50,
SYS_FORK=57, SYS_EXIT=60, SYS_WAIT4=61, SYS_UNAME=63,
SYS_CHDIR=80, SYS_MKDIR=83, SYS_RMDIR=84,
SYS_UNLINK=87, SYS_READLINK=89, SYS_CHMOD=90,
SYS_GETCWD=79, SYS_TIME=201, SYS_POLL=7
```

### DNS резолвинг

`resolveHostname()`:
1. Сначала проверяет `/etc/hosts`
2. Если не найдено — выполняет реальный DNS запрос:
   - UDP сокет → nameserver из `/etc/resolv.conf`
   - если nameserver не найден, используется fallback 8.8.8.8:53
   - Отправляет DNS query (header + question)
   - Получает ответ
   - Парсит ответ: пропускает question секцию, ищет A record в answer
   - Возвращает IP как u32

---

## 9. Графическая подсистема

### Display бэкенды

| Код | Бэкенд | Платформа |
|-----|--------|-----------|
| 1 | X11 | Linux |
| 2 | fbdev | Linux (framebuffer) |
| 3 | memory | Любая (без вывода) |
| 10 | Wayland | Linux |
| 20 | Win32 | Windows |

### Инициализация

`display.zig:init()` пробует бэкенды по порядку:
1. X11 (через Unix socket к `/tmp/.X11-unix/X[n]`)
2. Wayland (через `$XDG_RUNTIME_DIR/wayland-[n]`)
3. Win32
4. Linux fbdev (`/dev/fb0`)
5. TTY fallback (режим 3)

### Рендеринг

`render.zig` — софтверный рендерер, рисует в `[]u32` (framebuffer, 32bpp):
- Пиксели, прямоугольники, линии, круги, треугольники
- Скруглённые прямоугольники
- Текст (8×8 bitmap font)
- Тени
- Блендинг

### Шрифт

8×8 моноширинный bitmap шрифт, 95 глифов (ASCII 32–126).
Каждый глиф — 8 байт (8 строк по 8 пикселей).

---

## 10. Сеть и HTTP

### http_client (исполняемый файл)

Полноценный HTTP/1.0 клиент. Используется компилятором через fork+exec.

```
Usage: http_client <method> <host> [port] <path> [body]
```

Аргументы:
- method: GET, POST, resolve
- host: домен или IP
- port: (опционально) порт, по умолчанию 80
- path: путь запроса (начинается с /)
- body: (только для POST) тело запроса

### Схема работы fork+exec

```
┌─────────────────────┐
│   Программа dhjsjs   │
│   http.get(host,    │
│     path)           │
│                     │
│  ┌───────────────┐  │
│  │    pipe()     │  │
│  │  ┌────┬────┐  │  │
│  │  │ rd │ wr │  │  │
│  │  └─┬──┴──┬─┘  │  │
│  │    │     │     │  │
│  │    ▼     │     │  │
│  │  fork()  │     │  │
│  │  ┌─┼──┐  │     │  │
│  │  │P│ C│  │     │  │
│  │  └─┘  │  │     │  │
│  │  close│wr│     │  │
│  │  read │←├─────┘  │
│  │  <────┘ │       │
│  │         │ close │
│  │         │ rd    │
│  │         │ dup2  │
│  │         │ (wr→1)│
│  │         │       │
│  │         │ exec  │
│  │         │ http_c│
│  │         │ lient │
│  └─────────┴───────┘
```

### HTTP запрос

```
GET /path HTTP/1.0\r\n
Host: example.com\r\n
\r\n
```

Для POST:

```
POST /path HTTP/1.0\r\n
Host: example.com\r\n
Content-Length: 4\r\n
Content-Type: application/x-www-form-urlencoded\r\n
\r\n
body
```

---

## 11. Звуковая подсистема

### Вывод звука

Использует OSS (`/dev/dsp`):

```
audio_init(sample_rate, channels, format)
  → open("/dev/dsp")
  → ioctl(SNDCTL_DSP_SETFMT, format)
  → ioctl(SNDCTL_DSP_CHANNELS, channels)
  → ioctl(SNDCTL_DSP_SPEED, sample_rate)

audio_write(fd, data, len)
  → write(fd, data, len)
```

### media_player

Отдельный исполняемый файл для воспроизведения аудио.

Поддерживает: WAV, MP3, OGG, FLAC, AIFF.
Имеет собственный GUI: плейлист, ползунок, визуализатор, темная тема.

---

## 12. Android бэкенд

### Сборка APK

```
dhjsjs_cc build app.dhjs --target apk --package com.example.app
```

Сборка APK включает:
1. Компиляцию dhjsjs → AArch64 машинный код
2. Создание libnative.so с точкой входа NativeActivity
3. Генерацию AndroidManifest.xml
4. Упаковку в ZIP (APK) с выравниванием и подписью (RSA+SHA256)

### android_gui.zig

Реализует NativeActivity:
- Lifecycle: onCreate → onStart → onResume → onPause → onStop → onDestroy
- Input: AInputQueue (тач, клавиатура)
- Рендеринг: напрямую в Android window buffer
- Shared memory: `AndroidCmd` struct по фиксированному адресу `0x200100`

### Ограничения

- `http.get()`, `http.post()` НЕ РАБОТАЮТ на Android (fork+exec не поддерживается так же, как на Linux)
- Используйте прямые `socket()/connect()/send()/recv()` для сети
- Память ограничена стандартными Android ограничениями

---

## 13. Формат ELF

Компилятор генерирует statically-linked ELF64 executable.

### Структура

```
[ELF Header]
  e_ident: 7F 45 4C 46 (ELF magic)
  e_machine: 62 (EM_X86_64)
  e_entry: адрес _start

[Program Header - LOAD код]
  p_offset: 0
  p_vaddr: 0x400000
  p_filesz: размер кода
  p_memsz: размер кода
  p_flags: PF_R | PF_X

[Program Header - LOAD данные]
  p_offset: после кода
  p_vaddr: 0x400000 + размер кода
  p_filesz: размер данных + стек
  p_memsz: размер данных + стек
  p_flags: PF_R | PF_W

[Машинный код]

[Строковые данные]

[Стек (BSS)]
```

---

## 14. Внутреннее устройство GUI

### gui.zig — Immediate Mode GUI

GUI построен по принципу Immediate Mode: каждый кадр программа заново описывает
интерфейс. Виджеты не сохраняют состояние между кадрами — состояние хранится
в переменных программы.

### Жизненный цикл

```
1. guiApp() → fork + exec gui_srv
   (создаёт окно, настраивает display backend)

2. В цикле:
   a. guiServer() — обрабатывает события (мышь, клавиатура)
   b. beginWindow(...) — начинает окно
   c. label(...), button(...) — виджеты
   d. endWindow() — заканчивает окно
   e. return → повтор
```

### gui_srv — сервер GUI

Отдельный процесс, который:
1. Инициализирует display backend (X11/Wayland/Win32)
2. Принимает команды через pipe от dhjsjs программы
3. Рендерит виджеты
4. Отправляет события обратно

### Виджеты

Все виджеты идентифицируются по ID (автоматически вычисляемому из label и типа).

**Встроенные виджеты:**
- Button, Label, TextInput, Checkbox, Slider, ComboBox
- Collapsible, Separator, Spacer
- Window (с заголовком, перемещением, ресайзом)

**Расширенные (gui_ext.zig):**
- TabBar, TreeView, ScrollArea, MenuBar, ContextMenu, Popup
- ColorPicker, Tooltip, ProgressBar, Knob, LED, ImageView, Table, Canvas

### Рендеринг

1. Каждый кадр: очистка framebuffer
2. Для каждого окна: отрисовка фона, заголовка, границ
3. Для каждого виджета: расчёт позиции, отрисовка, проверка событий
4. Переключение буферов (present)

---

## 15. Паросочетание вызовов через точку (http.get)

### Проблема

Исходный код `http.get("host", "/path")` выглядит как доступ к полю
структуры `http`, а затем вызов метода `get`.

### Решение в парсере

В `parser.zig` (строка ~588) после парсинга идентификатора и точки,
если следующий токен — идентификатор и затем `(`, парсер объединяет
их в один вызов:

```
http.get("host", "/path")
  → парсим "http" как ident
  → парсим "." как точка
  → парсим "get" как ident
  → парсим "(" — это вызов!
  → создаём узел call с именем "http.get"
```

### В компиляторе

```
if (eq(name, "http.get") or eq(name, "http_get") or eq(name, "httpget")) {
    // компилируем HTTP GET builtin
}
```

Это позволяет использовать как `http.get(host, path)`, так и `http_get(host, path)`.

---

## Приложение: Сборка и зависимости

### Сборка

```
make all
```

Собирает 6 бинарников:
- `dhjsjs` — IDE (редактор кода)
- `dhjsjs_cc` — компилятор из командной строки
- `media_player` — аудио плеер
- `desktop_gui` — демо GUI
- `gui_srv` — сервер GUI
- `http_client` — HTTP клиент

### Зависимости

- Zig (компилятор Zig)
- Linux (для рантайма)
- Никаких внешних библиотек или libc

### Структура проекта

```
dhjsjs/
├── src/              # исходный код на Zig
│   ├── *.zig
│   └── ...
├── SUMMARY.md        # краткое описание проекта
├── GUIDE_RU.md       # это руководство
├── COMPILER_RU.md    # техническая документация
└── Makefile          # сборка
```

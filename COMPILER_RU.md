# Техническая документация компилятора dhjsjs

> Внутреннее устройство языка dhjsjs, компилятора и рантайма.
> Для разработчиков и интересующихся.

---

## Оглавление

1. [Архитектура](#1-архитектура)
2. [Синтаксис языка](#2-синтаксис-языка)
3. [Лексер (lexer.zig)](#3-лексер-lexerzig)
4. [Парсер (parser.zig)](#4-парсер-parserzig)
5. [Генератор кода (codegen.zig)](#5-генератор-кода-codegenzig)
6. [Компилятор (compiler.zig)](#6-компилятор-compilerzig)
7. [ARM64 бэкенд (compiler_arm.zig)](#7-arm64-бэкенд-compiler_armzig)
8. [RISC-V бэкенд (compiler_rv.zig)](#8-risc-v-бэкенд-compiler_rvzig)
9. [Типы данных и память](#9-типы-данных-и-память)
10. [Встроенные функции (builtins)](#10-встроенные-функции-builtins)
11. [Системные вызовы (sys.zig)](#11-системные-вызовы-syszig)
12. [Графическая подсистема](#12-графическая-подсистема)
13. [Сеть и HTTP](#13-сеть-и-http)
14. [Звуковая подсистема](#14-звуковая-подсистема)
15. [GUI — графика и виджеты](#15-gui--графика-и-виджеты)
16. [Android бэкенд](#16-android-бэкенд)
17. [Windows PE64 бэкенд](#17-windows-pe64-бэкенд)
18. [ESP32 и RISC-V](#18-esp32-и-risc-v)
19. [Криптография (crypto.zig)](#19-криптография-cryptozig)
20. [Транспиляция в C](#20-транспиляция-в-c)
21. [IDE — среда разработки](#21-ide--среда-разработки)
22. [CLI — интерфейс командной строки](#22-cli--интерфейс-командной-строки)
23. [Обработка ошибок (errors.zig)](#23-обработка-ошибок-errorszig)
24. [Форматы выходных файлов](#24-форматы-выходных-файлов)
25. [Паросочетание вызовов через точку (http.get)](#25-паросочетание-вызовов-через-точку-httpget)
26. [Ограничения компилятора](#26-ограничения-компилятора)
27. [Сборка и Makefile](#27-сборка-и-makefile)
28. [Все файлы проекта](#28-все-файлы-проекта)

---

## 1. Архитектура

### Общая схема

```
Исходный код (.dhjsjs)
    │
    ▼
┌─────────────┐
│   Лексер    │ → Токены (TokenKind, Token)
│ (lexer.zig) │
└─────────────┘
    │
    ▼
┌─────────────┐
│   Парсер    │ → AST (Abstract Syntax Tree)
│(parser.zig) │   2018 узлов max, 32+ типа узлов
└─────────────┘
    │
    ▼
┌─────────────┐
│ Компилятор  │ → Машинный код (CodeBuffer, 64KB max)
│(compiler*.zig)│
└─────────────┘
    │
    ▼
┌─────────────┐
│  Кодоген    │ → ELF64 / ELF32 / PE64 / ELF64 Dyn
│(codegen*.zig)│
└─────────────┘
    │
    ▼
┌─────────────┐
│  Бинарник   │ → ./program (statically linked, без libc)
│             │
└─────────────┘
```

### Ключевые принципы

- **Zero dependencies** — ни одной внешней библиотеки, даже libc
- **Raw syscalls** — все операции ввода-вывода через прямые системные вызовы Linux
- **Statically linked** — выходные бинарники не требуют динамических библиотек
- **Single-pass компиляция** — без промежуточных представлений (IR)
- **Immediate Mode GUI** — интерфейс перерисовывается каждый кадр

### Путь данных

1. Исходный текст → `lexer.zig` → массив токенов
2. Токены → `parser.zig` → AST (плоский массив узлов, связанных индексами)
3. AST → `compiler.zig` → `CodeBuffer` (байты машинного кода)
4. `CodeBuffer` → `codegen.zig` → ELF/PE файл на диске

### Целевые архитектуры

| Архитектура | Компилятор | Кодоген | Формат |
|-------------|-----------|---------|--------|
| x86-64 | compiler.zig | codegen.zig | ELF64 / PE64 |
| ARM64 (AArch64) | compiler_arm.zig | codegen_arm.zig | ELF64 / ELF64 Dyn |
| RISC-V 32-bit | compiler_rv.zig | codegen_rv.zig | ELF32 |

---

## 2. Синтаксис языка

### Лексика

Ключевые слова (английские и украинские/русские):

```
fn       — объявление функции
hui/var  — объявление переменной
if       — условие
uebok    — else (иначе)
while    — цикл
return   — возврат из функции
struct   — объявление структуры
break    — выход из цикла
continue — следующая итерация
const    — объявление константы
true     — истина
false    — ложь
null     — пустое значение
int      — тип: целое число
string   — тип: строка
bool     — тип: булево
void     — тип: пусто
activity — Android Activity (экспериментально)
compose  — Android Compose (экспериментально)
state    — Android State (экспериментально)
viewmodel — Android ViewModel (экспериментально)
```

### Типы литералов

```
42        — целое число (int)
0xFF      — шестнадцатеричное число
"текст"   — строка (string)
true      — булево значение (bool)
false     — булево значение (bool)
null      — нулевой указатель
```

### Операторы

Арифметика:    `+` `-` `*` `/` `%`
Битовые:       `&` `|` `^` `<<` `>>`
Сравнение:     `==` `!=` `<` `>` `<=` `>=`
Логические:    `&&` `||` `!`
Унарные:       `-` `!` `&` (адрес) `*` (разыменование)
Присваивание:  `=`
Склейка строк: `+`
Размер:        `sizeof(expr)`

### Таблица приоритетов

| Приоритет | Операторы | Ассоциативность |
|-----------|-----------|----------------|
| 2 (низший) | `\|\|` | левая |
| 3 | `&&` | левая |
| 4 | `\|` | левая |
| 5 | `^` | левая |
| 6 | `&` | левая |
| 7 | `==` `!=` `<` `>` `<=` `>=` | левая |
| 8 | `<<` `>>` | левая |
| 9 | `+` `-` | левая |
| 10 | `*` `/` `%` | левая |
| 11 | `[]` (индексация) | левая |
| 12 | `.` (доступ к полю) | левая |

Унарные операторы (`-`, `!`, `&`, `*`) имеют наивысший приоритет.

### Синтаксис функции

```
fn имя(тип арг1, тип арг2, ...) тип_возврата {
    тело
    return значение
}
```

Параметры типизированные. Тип возврата опционален. Если функция не возвращает значение, тип можно опустить или указать `void`.

### Синтаксис структуры

```
struct Имя {
    поле1: тип
    поле2: тип
}
```

Создание: `hui obj = Имя{ поле1: значение, поле2: значение }`
Доступ: `obj.поле`

### Строгий синтаксис

В реальном коде рекомендуется:
- Завершать выражения точкой с запятой `;`
- Использовать `hui` для объявления переменных
- Указывать тип возврата у функций
- Использовать скобки в сложных выражениях

---

## 3. Лексер (lexer.zig)

### Назначение

`lexer.zig` (207 строк) — разбивает исходный код на токены. Самый маленький компонент компилятора, но критически важный.

### Структура Lexer

```zig
const Lexer = struct {
    source: []const u8,  // исходный код
    pos: usize,          // текущая позиция
    line: u32,           // текущая строка
    col: u32,            // текущий столбец
    token: Token,        // текущий токен
};
```

### Типы токенов (TokenKind)

```
identifier   — идентификатор (имя переменной, функции)
integer      — целое число (десятичное или 0xhex)
string       — строковый литерал в кавычках
keyword      — ключевое слово (fn, hui, if, ...)
symbol       — оператор или знак пунктуации
invalid      — недопустимый символ
eof          — конец файла
```

### Как работает

1. Пропускает пробелы, табуляции, переводы строк
2. Проверяет комментарии:
   - `//` — однострочный: пропускает всё до конца строки
   - `/* */` — многострочный: ищет `*/`, иначе ошибка
3. Если символ — буква или `_`: читает идентификатор, проверяет на совпадение с ключевыми словами
4. Если символ — цифра: читает число. `0x` в начале → шестнадцатеричное
5. Если символ — `"`: читает строку до закрывающей `"`, обрабатывает escape-последовательности
6. Иначе — пытается сопоставить с известными символами/операторами

### Обработка escape-последовательностей в строках

```
\n  — новая строка (0x0A)
\r  — возврат каретки (0x0D)
\t  — табуляция (0x09)
\\  — обратный слеш
\"  — кавычка
\0  — нулевой байт
\x41 — байт в hex-представлении
```

### Отслеживание позиции

Лексер ведёт счёт строк (`line`) и столбцов (`col`), что позволяет выдавать точные сообщения об ошибках с указанием строки и столбца.

---

## 4. Парсер (parser.zig)

### Назначение

`parser.zig` (836 строк) — рекурсивный нисходящий парсер (recursive descent), который строит абстрактное синтаксическое дерево (AST) из потока токенов.

### Структура Parser

```zig
const Parser = struct {
    lexer: Lexer,
    nodes: [MAX_NODES]AstNode,   // 2048 — фиксированный пул
    node_count: u32,
    fn_names: [MAX_FUNCTIONS][64]u8,  // 32 — макс функций
    fn_count: u32,
    errors: *ErrorList,
};
```

### Структура узла AST (AstNode)

```zig
AstNode {
    kind: NodeKind,          // тип узла
    first_child: NodeIdx,    // индекс первого дочернего узла (-1 = нет)
    next_sibling: NodeIdx,   // индекс следующего sibling (-1 = нет)
    val_start: usize,        // начало текста в исходнике
    val_len: usize,          // длина текста
    line: u32,               // строка в исходнике
    col: u32,                // столбец
}
```

### Типы узлов AST (32+ вида)

**Литералы и идентификаторы:**
- `.no_node` — пустой узел
- `.int_lit` — целочисленный литерал (42, 0xFF)
- `.str_lit` — строковый литерал ("hello")
- `.ident` — идентификатор (имя переменной/функции)

**Объявления:**
- `.fn_decl` — объявление функции (`fn name(...) { ... }`)
- `.struct_decl` — объявление структуры
- `.var_decl` — объявление переменной (`hui x = ...`)
- `.struct_var_decl` — объявление переменной-структуры
- `.activity_decl` — Android Activity
- `.compose_decl` — Android Compose
- `.state_decl` — Android State
- `.viewmodel_decl` — Android ViewModel

**Операторы:**
- `.assign` — присваивание (`x = expr`)
- `.binary_op` — бинарная операция (+ - * / == < > && || & | ^ << >>)
- `.unary_op` — унарная операция (- ! & *)
- `.field_access` — доступ к полю структуры (obj.field)
- `.array_index` — индексация массива (arr[i])
- `.addr_of` — взятие адреса (&expr)
- `.deref` — разыменование (*expr)
- `.sizeof_expr` — sizeof(expr)
- `.call` — вызов функции

**Управляющие конструкции:**
- `.block` — блок кода в { }
- `.if_stmt` — условие if/uebok
- `.while_stmt` — цикл while
- `.ret_stmt` — return
- `.break_stmt` — break
- `.continue_stmt` — continue
- `.store` — запись по указателю (*ptr = val)

### Фазы парсинга

1. `parse()` — корневой метод: парсит верхнеуровневые объявления
2. `parseFnDecl()` — парсит `fn name(params) type? { body }`
3. `parseVarDecl()` — парсит `hui name = expr` или `hui name[size]`
4. `parseBlock()` — парсит последовательность statement-ов в { }
5. `parseStmt()` — диспетчеризует: if, while, return, break, continue, block, var_decl, выражение
6. `parseExpr(min_precedence)` — Pratt-парсинг выражений с учётом приоритетов
7. `parsePrimary()` — базовые элементы: числа, строки, идентификаторы, (выражения), struct инициализация

### Особые случаи

**Парсинг `http.get(...)`:**
Парсер обнаруживает последовательность `ident . ident ( )` и создаёт один узел `.call` с именем, объединяющим обе части через точку: `http.get`. Это позволяет компилятору сопоставлять такой вызов с builtin-функцией.

**Парсинг структур:**
```
struct Point { x: int, y: int }
```
Парсер читает `struct`, имя, `{`, список пар `имя: тип`, `}`. Создаёт узел `.struct_decl` с дочерними `.struct_var_decl` для каждого поля.

### Ограничения парсера

- Фиксированный пул: максимум 2048 узлов AST
- Максимум 32 функции на файл
- Максимум 64 переменных на функцию
- Имена функций не могут повторяться

---

## 5. Генератор кода (codegen.zig)

### Назначение

`codegen.zig` (623 строк) — кодировщик машинных инструкций x86-64 и сборщик ELF64/PE64 форматов.

### CodeBuffer

`CodeBuffer` — это байтовый буфер фиксированного размера (65536 байт, константа `code_buf_size`). Он содержит:

```zig
const CodeBuffer = struct {
    buf: [code_buf_size]u8,  // 65536 байт
    len: u32,                // текущая длина
    // ...
};
```

Буфер растёт последовательно — каждая новая инструкция дописывается в конец.

### Методы кодирования инструкций

**Пересылка данных:**
- `movRR(dst, src)` — mov reg, reg
- `movRImm64(r, val)` — mov reg, imm64 (10 байт: REX.W + opcode + modrm + 8 байт)
- `movRImm32(r, val)` — mov reg, imm32 (5 байт)
- `movRMem64(r, addr_reg, offset)` — mov reg, [addr_reg + offset]
- `movMemR64(addr_reg, offset, r)` — mov [addr_reg + offset], reg
- `movzxRR(dst, src)` — movzx (zero-extend byte to 64-bit)

**Арифметика:**
- `addRR(dst, src)` — add reg, reg
- `subRR(dst, src)` — sub reg, reg
- `subRImm32(r, val)` — sub reg, imm32
- `imulRR(dst, src)` — imul reg, reg
- `xorRR(dst, src)` — xor reg, reg
- `andRR(dst, src)` — and reg, reg
- `orRR(dst, src)` — or reg, reg
- `shlRR(dst, src)` — shl reg, reg
- `shrRR(dst, src)` — shr reg, reg
- `sarRR(dst, src)` — sar reg, reg
- `divR(r)` — div (unsigned, rdx:rax / r)
- `idivR(r)` — idiv (signed)
- `negR(r)` — neg (арифметическое отрицание)
- `notR(r)` — not (битовое НЕ)

**Стек:**
- `pushR(r)` — push reg
- `popR(r)` — pop reg

**Сравнение и переходы:**
- `cmpRR(a, b)` — cmp reg, reg
- `cmpRImm32(r, val)` — cmp reg, imm32
- `cmpRImm8(r, val)` — cmp reg, imm8
- `jmpRel32(off)` — jmp rel32
- `jeRel32(off)` — je rel32 (jump if equal)
- `jneRel32(off)` — jne rel32
- `jlRel32(off)` — jl rel32 (signed less)
- `jleRel32(off)` — jle rel32
- `jgRel32(off)` — jg rel32 (signed greater)
- `jgeRel32(off)` — jge rel32
- `sete(r)` — sete reg (set byte if equal)
- `setne(r)` — setne reg
- `setl(r)` — setl reg
- `setg(r)` — setg reg
- `setle(r)` — setle reg
- `setge(r)` — setge reg

**Вызовы:**
- `callRel32(off)` — call rel32
- `syscall()` — syscall

**Прочее:**
- `cqo()` — cqo (convert quad to oct: sign-extend rax → rdx:rax)
- `leaRMem(r, addr_reg, offset)` — lea reg, [addr_reg + offset]
- `nop()` — nop (1 байт, 0x90)

### REX префиксы

Для 64-битных инструкций автоматически проставляется REX.W префикс (0x48).
Для инструкций с регистрами r8–r15 проставляется REX.B (0x41).
Комбинация: REX.W + REX.B = 0x49.

### ModRM байт

Большинство инструкций кодируются через `modrm(reg, rm)` который вычисляет ModRM байт:
```
modrm(reg, rm) = 0xC0 | (reg << 3) | rm   // для регистр-регистр
```

Для памяти: `modrm_with_offset(mod, reg, rm)`.

### Кодирование call/jmp

`callRel32(offset)` и `jmpRel32(offset)` вычисляют смещение относительно следующей инструкции:
```
rel32 = target - (current_pos + 5)  // 5 = длина call/jmp rel32
```

---

## 6. Компилятор (compiler.zig)

### Назначение

`compiler.zig` (~3179 строк, самый большой файл) — семантический компилятор для x86-64. Обходит AST и генерирует машинный код в CodeBuffer.

### Основной цикл компиляции

```
compile(ast, pool)
  для каждого узла AST на верхнем уровне:
    если это fn_decl → запомнить функцию (имя, позиция)
    если это struct_decl → запомнить структуру (поля, размер)

  найти main()
  вычислить размер стека (countVarDecls)
  сгенерировать пролог main()
  скомпилировать тело main() в код
  добавить эпилог main()
  для каждой вызванной, но не скомпилированной функции:
    скомпилировать её тело
  сшить всё в ELF
```

### Система переменных

Переменные хранятся на стеке. Компилятор отслеживает таблицу символов:

```zig
const Var = struct {
    name: [64]u8,     // имя переменной
    len: u32,         // длина имени
    offset: i32,      // смещение от rbp (отрицательное)
    depth: u32,       // глубина вложенности (для областей видимости)
};

var vars: [MAX_VARS]Var = undefined;  // 64 переменных макс
var vc: u32 = 0;                      // счётчик переменных
```

Доступ к переменной: `[rbp + offset]`. Новые переменные получают `offset -= 8` (стек растёт вниз).

### Пролог и эпилог функции

```
Пролог:
  push rbp              ; сохраняем предыдущий rbp
  mov  rbp, rsp         ; устанавливаем новый фрейм
  sub  rsp, stack_size  ; выделяем место под локальные переменные

Эпилог:
  mov  rsp, rbp         ; восстанавливаем указатель стека
  pop  rbp              ; восстанавливаем rbp
  ret                   ; возврат
```

`stack_size` вычисляется через `countVarDecls()`, который рекурсивно подсчитывает все объявления переменных в функции, включая вложенные блоки, if-ы и while-и.

### Компиляция выражений

`compileExprNode(node, pool, cb, vars, vc, errs)`:

- `int_lit` → `mov rax, imm64`
- `str_lit` → `lea rax, [rip + offset]` + `jmp` через строку
- `ident` → `mov rax, [rbp + offset]` (чтение переменной)
- `binary_op` → компиляция левой части в rax, push rax, компиляция правой части в rax, pop rcx, выполнение операции
- `unary_op` → компиляция операнда в rax, затем операция (neg, not, etc.)
- `field_access` → `mov rax, [rbp + base_offset + field_index * 8]`
- `array_index` → вычисление базового адреса + индекс * 8
- `addr_of` → `lea rax, [rbp + offset]`
- `deref` → `mov rax, [rax]`
- `sizeof_expr` → `mov rax, size`
- `call` → компиляция аргументов (push на стек), генерация call rel32, очистка стека

### Компиляция statement-ов

`compileStmt(node, pool, cb, vars, vc, errs)`:

- `.block` → последовательная компиляция дочерних узлов
- `.var_decl` → вычисление выражения инициализации, сохранение на стек
- `.assign` → вычисление выражения, запись в переменную
- `.if_stmt` → условие, условный переход, then-блок, uebok-блок
- `.while_stmt` → метка начала, условие, переход на выход, тело, прыжок на начало, метка выхода
- `.ret_stmt` → вычисление возвращаемого значения, эпилог, ret
- `.break_stmt` → прыжок на метку выхода из цикла
- `.continue_stmt` → прыжок на метку начала цикла
- `.call` (как statement) → вызов функции, результат игнорируется
- `.store` → запись по указателю (*ptr = val)

### Компиляция if

```
  compile условие (результат в rax)
  cmp rax, 0
  je else_label       ; if (условие == 0) → else
  compile then_блок
  jmp end_label
else_label:
  compile uebok_блок  ; если есть
end_label:
```

### Компиляция while

```
loop_label:
  compile условие (результат в rax)
  cmp rax, 0
  je exit_label
  compile тело
  jmp loop_label
exit_label:
```

### Компиляция логических операций

`&&` (логическое И) и `||` (логическое ИЛИ) компилируются с short-circuit evaluation:

**x && y:**
```
  compile x в rax
  cmp rax, 0
  je false_label     ; если x == 0, результат 0
  compile y в rax
  cmp rax, 0
  sete al            ; al = (y != 0) ? 1 : 0
false_label:
```

**x || y:**
```
  compile x в rax
  cmp rax, 0
  jne true_label     ; если x != 0, результат 1
  compile y в rax
  cmp rax, 0
  sete al
  jmp end_label
true_label:
  mov rax, 1
end_label:
```

### Вызов функции

Для вызова функции компилятор:
1. Компилирует каждый аргумент (результат в rax)
2. Push-ит каждый аргумент на стек (в порядке справа налево)
3. Генерирует `call rel32` на целевую функцию
4. Очищает стек от аргументов: `add rsp, N * 8`
5. Результат функции остаётся в rax

Если имя функции совпадает с builtin — генерируется встроенный код вместо вызова.
Если функция не определена и не builtin — выдаётся ошибка компиляции.

### Неявный return

В конце `main()` компилятор добавляет неявный `return 0`, что соответствует стандартному коду возврата успешного завершения.

---

## 7. ARM64 бэкенд (compiler_arm.zig)

### Назначение

`compiler_arm.zig` (1137 строк) — компилятор для AArch64 (ARM64). Используется для Linux ARM64 и Android APK.

### Архитектура

Следует той же структуре, что и x86-64 компилятор, но:
- Использует 64-битный набор инструкций AArch64
- Регистры: X0-X30 (X30 = link register)
- Аргументы функций передаются в X0-X7 (не через стек!)
- Остальные аргументы — через стек

### Передача аргументов (AAPCS64)

```
Аргумент 1: X0
Аргумент 2: X1
...
Аргумент 8: X7
Остальные: [sp], [sp+8], ...
Возврат: X0
```

Для аргументов сверх 8 штук компилятор резервирует место на стеке.

### Пролог/эпилог

```
Пролог:
  stp  x29, x30, [sp, -16]!   ; сохраняем fp и lr
  mov  x29, sp                 ; устанавливаем fp

Эпилог:
  ldp  x29, x30, [sp], 16     ; восстанавливаем fp и lr
  ret                          ; возврат
```

### Особенности

- Компилятор резервирует 64 байта под т.н. "register save area" для аргументов
- `compileEx()` — специальная версия для Android, где после возврата из main добавляется бесконечный цикл (Android-приложения не должны завершаться)
- `buildElf64Dyn()` — собирает динамический ELF64 (shared library) для Android

---

## 8. RISC-V бэкенд (compiler_rv.zig)

### Назначение

`compiler_rv.zig` (464 строк) — компилятор для RISC-V 32-bit. Используется для ESP32-C3/C6 микроконтроллеров.

### Архитектура

- 32-битные регистры (x0-x31)
- x0 = zero (всегда 0)
- x1 = ra (return address)
- x8 = s0/fp (frame pointer)
- x2 = sp (stack pointer)
- Аргументы в x10-x17 (a0-a7)
- Возврат в x10 (a0)

### Передача аргументов

```
Аргумент 1: x10 (a0)
Аргумент 2: x11 (a1)
...
Аргумент 8: x17 (a7)
Остальные: стек
```

### Особенности

- Нет аппаратного умножения/деления на некоторых ESP32 — компилятор может генерировать программные эмуляции
- Кодогенератор RISC-V (`codegen_rv.zig`) эмулирует псевдоинструкции: `mv` (псевдоним add), `neg` (псевдоним sub), `not_` (псевдоним xori), `li` (загрузка произвольного immediate), `seqz`/`snez` (set-if-zero/set-if-not-zero)
- Выходной формат: ELF32

---

## 8.1. AVR бэкенд (compiler_avr.zig)

### Назначение

`compiler_avr.zig` (460 строк) — компилятор для AVR 8-bit. Используется для Arduino Uno/Nano/Mega (ATmega328p, ATmega2560 и других).

### Архитектура

- 8-битные регистры (r0-r31), 32 регистра
- r1 = zero (всегда 0)
- r28:r29 = Y (frame pointer)
- r30:r31 = Z (адресный регистр)
- r22-r25 = A0 (32-битный аккумулятор для выражений)
- r18-r21 = T0 (временный для бинарных операций)

### Переменные и стек

Все переменные хранятся на стеке, доступ через Y+offset. Для offset 0-63 используется прямая адресация через `ldd`/`std`. Для больших смещений — через MOVW + ADD/ADC с Z-регистром.

### 32-битные операции

32-битные целые реализованы через последовательность 8-битных инструкций с переносом:

| Операция | Инструкции |
|----------|-----------|
| ADD | 1×add + 3×adc |
| SUB | 1×sub + 3×sbc |
| AND/OR/XOR | 4×and/or/eor |
| NEG | neg + 3×sbc r, R1 |
| Сравнение | cp + 3×cpc |
| Сдвиг влево | 1×lsl + 3×rol |
| Сдвиг вправо | 1×lsr + 3×ror |

### Ветвление

- `breq`/`brne` — равенство (Z-флаг из cp/cpc)
- `brlt`/`brge` — signed сравнения
- `brlo`/`brsh` — unsigned сравнения

### Выходной формат

- Intel HEX (.hex) — для прошивки через avrdude или Arduino IDE
- Можно использовать `avrdude -p atmega328p -c arduino -P /dev/ttyUSB0 -b 115200 -U flash:w:file.hex`

### syscall на AVR

- `syscall(0, port, val)` — запись в I/O порт (OUT)
- `syscall(1, port)` — чтение из I/O порта (IN)

### Ограничения

- Нет 32-битного умножения/деления (возвращают 0)
- Строки не поддерживаются (возвращают 0)
- Максимум 16 переменных в функции (ограничение LDD-диапазона 64 байта)
- Только один `main()`, нет вызова пользовательских функций

---

## 9. Типы данных и память

### Целые числа (int)

- 64-битные знаковые (на x86-64 и ARM64)
- На RISC-V: 32-битные
- Хранятся: в регистрах (rax, rcx, rdx, r8-r15 на x86-64) или на стеке (8 байт)
- В структурах: последовательно в памяти, каждое поле размером 8 байт

### Строки (string)

- Хранятся как указатель на данные в коде (RIP-relative на x86-64)
- Null-terminated (заканчиваются нулевым байтом)
- НЕ динамические — существуют в памяти всё время работы программы
- Компилятор генерирует для строк:

```asm
lea rax, [rip+2]    ; rax = адрес строки
jmp over_string     ; прыжок через строку
db "строка", 0      ; данные строки
over_string:        ; rax указывает на "строка"
```

### Булевы значения (bool)

- Представляются как int: 0 = false, 1 = true
- Сравнения генерируют 0 или 1 через setCC инструкции

### Структуры (struct)

- Последовательность полей в памяти
- Каждое поле занимает 8 байт (u64)
- Размер структуры = количество_полей × 8
- Выравнивание: по 8 байт

```
struct Point { x: int, y: int }
// в памяти: [x (8 байт)] [y (8 байт)]
// Point.x = [rbp + offset_base]
// Point.y = [rbp + offset_base + 8]
```

Доступ к полю: базовый адрес структуры + индекс_поля * 8.

### Массивы

- Фиксированного размера, объявляются: `hui buf[256]`
- Индексация: `buf[i]` → базовый адрес + i * 8
- Размер элемента: 8 байт

### Null / указатели

- `null` — нулевой указатель (0)
- `&x` — взятие адреса переменной → `lea rax, [rbp + offset]`
- `*ptr` — разыменование → `mov rax, [rax]`
- `*ptr = val` — запись по указателю → `mov [rax], val`

---

## 10. Встроенные функции (builtins)

Всего ~60+ встроенных функций. Компилятор распознаёт их по имени и генерирует специальный машинный код вместо вызова.

### Категории builtins

1. **Прямые syscall-обёртки** — каждый builtin превращается в один syscall
2. **Inline-сеть и аудио** — inline socket/DNS/TLS/аудио­декодирование (без fork+exec)
3. **Специализированные** — генерация уникального кода (GUI, графика)

### Полный список builtins

**Печать и вывод:**

| Имя | Код | Описание |
|-----|-----|----------|
| `print(x)` | syscall write(1, x, strlen(x)) | Печать строки или числа |
| `print(ptr, len)` | syscall write(1, ptr, len) | Печать len байт |

**Системные вызовы (прямые):**

| Имя | Syscall | Описание |
|-----|---------|----------|
| `exit(code)` | SYS_EXIT (60) | Завершить процесс |
| `getpid()` | SYS_GETPID (39) | PID текущего процесса |
| `fork()` | SYS_FORK (57) | Создать процесс |
| `waitpid(pid)` | SYS_WAIT4 (61) | Подождать дочерний процесс |
| `nanosleep(sec, nsec)` | SYS_NANOSLEEP (35) | Пауза |
| `time(ptr)` | SYS_TIME (201) | Текущее время |
| `uname(buf)` | SYS_UNAME (63) | Информация о системе |
| `brk(addr)` | SYS_BRK (12) | Изменить program break |
| `mmap(addr, len, prot, flags, fd, off)` | SYS_MMAP (9) | Выделить/отобразить память |
| `munmap(addr, len)` | SYS_MUNMAP (11) | Освободить mmap |

**Файловые операции:**

| Имя | Syscall | Описание |
|-----|---------|----------|
| `open(path, flags, mode)` | SYS_OPEN (2) | Открыть файл |
| `read(fd, buf, len)` | SYS_READ (0) | Прочитать из файла |
| `write(fd, buf, len)` | SYS_WRITE (1) | Записать в файл |
| `close(fd)` | SYS_CLOSE (3) | Закрыть файл |
| `lseek(fd, offset, whence)` | SYS_LSEEK (8) | Сместить позицию |
| `stat(path, buf)` | SYS_STAT (4) | Информация о файле |
| `fstat(fd, buf)` | SYS_FSTAT (5) | Информация по fd |
| `unlink(path)` | SYS_UNLINK (87) | Удалить файл |
| `chdir(path)` | SYS_CHDIR (80) | Сменить директорию |
| `getcwd(buf, len)` | SYS_GETCWD (79) | Текущая директория |
| `mkdir(path, mode)` | SYS_MKDIR (83) | Создать папку |
| `rmdir(path)` | SYS_RMDIR (84) | Удалить папку |
| `chmod(path, mode)` | SYS_CHMOD (90) | Права доступа |
| `readlink(path, buf, len)` | SYS_READLINK (89) | Прочитать симлинк |
| `pipe(fds)` | SYS_PIPE (22) | Создать канал |
| `dup(fd)` | SYS_DUP (32) | Копировать fd |
| `dup2(oldfd, newfd)` | SYS_DUP2 (33) | Перенаправить fd |

**Сеть:**

| Имя | Код | Описание |
|-----|-----|----------|
| `socket(domain, type, protocol)` | syscall socket | Создать сокет |
| `connect(fd, ip, port)` | syscall connect | Подключиться |
| `bind(fd, ip, port)` | syscall bind | Привязать адрес |
| `listen(fd, backlog)` | syscall listen | Слушать порт |
| `accept(fd)` | syscall accept | Принять клиента |
| `send(fd, buf, len, flags)` | syscall send | Отправить |
| `recv(fd, buf, len, flags)` | syscall recv | Принять |

**Составные builtins (inline на всех платформах, без fork+exec):**

| Имя | Что делает |
|-----|-----------|
| `http.get(host, path)` | inline socket+DNS (все платформы, без внешнего бинарника) |
| `http.post(host, path, body)` | inline socket+DNS |
| `http_get(host, path)` | алиас для http.get |
| `httpget(host, path)` | алиас для http.get |
| `http_post(host, path, body)` | алиас для http.post |
| `httppost(host, path, body)` | алиас для http.post |
| `resolve(host)` | inline UDP DNS |
| `resolve_hostname(host)` | алиас для resolve |
| `tls.get(host, path)` | TLS/HTTPS GET builtin (встроенный TLS handshake) |
| `tls_get(host, path)` | алиас для tls.get |
| `tlsget(host, path)` | алиас для tls.get |
| `tls.post(host, path, body)` | TLS/HTTPS POST builtin |
| `tls_post(host, path, body)` | алиас для tls.post |
| `tlspost(host, path, body)` | алиас для tls.post |
| `https.get(host, path)` | алиас для `tls.get` |
| `https_get(host, path)` | алиас для https.get |
| `httpsget(host, path)` | алиас для https.get |
| `https.post(host, path, body)` | алиас для `tls.post` |
| `https_post(host, path, body)` | алиас для https.post |
| `httpspost(host, path, body)` | алиас для https.post |
| `guiApp()` / `guiapp()` | fork + вызов gui_srv.main() (без exec) |

**Графика (Framebuffer):**

| Имя | Описание |
|-----|----------|
| `fb_open()` | Открыть /dev/fb0 |
| `fb_close(fb)` | Закрыть |
| `fb_width(fb)` | ioctl FBIOGET_VSCREENINFO → ширина |
| `fb_height(fb)` | ioctl FBIOGET_VSCREENINFO → высота |
| `fb_pixel(fb, x, y, color)` | Запись пикселя в mmap-буфер |
| `fb_fill(fb, x, y, w, h, color)` | Заливка прямоугольника |

**Аудио:**

| Имя | Описание |
|-----|----------|
| `audio_init(rate, channels, fmt)` | open("/dev/dsp") + ioctl |
| `audio_write(fd, buf, len)` | write(fd, data, len) |
| `audio_close(fd)` | close(fd) |
| `audio_pause(fd)` | ioctl SNDCTL_DSP_RESET |
| `audio_stop(fd)` | алиас паузы |
| `audio_play(fd)` | ioctl SNDCTL_DSP_RESUME |
| `wavplay(path)` | fork + exec media_player для WAV |
| `mp3play(path)` | fork + exec media_player для MP3 |
| `audioplay(path)` | fork + exec media_player |
| `playerapp()` | Запустить GUI-плеер |

**GUI (виджеты):**

| Имя | Описание |
|-----|----------|
| `guiApp()` / `guiapp()` | Запустить gui_srv |
| `guiServer()` / `guiserver()` | Обработка событий GUI |
| `guiCmd(fd, type, id, x, y, w, h, val, label)` | Низкоуровневая команда |
| `setTheme(fd, theme_id)` | Сменить тему (0=Dark, 1=Light, 2=Modern Dark, 3=Modern Light, 4=Diamond) |
| `setStyle(fd, field_id, value)` | Установить поле стиля (0-29: цвета/rounding/shadow/spacing/padding) |
| `guiTriangle(x1,y1,x2,y2,x3,y3)` | Закрашенный треугольник |
| `guiGlassPanel(x,y,w,h,bg,border)` | Стеклянная панель |
| `guiShadow(x,y,w,h,intensity)` | Мягкая тень |

**Android:**

| Имя | Описание |
|-----|----------|
| `android_width()` | Ширина экрана |
| `android_height()` | Высота экрана |
| `android_fb_ptr()` | Указатель на буфер |
| `android_fb_stride()` | Шаг строки |
| `android_pixel(x, y, color)` | Пиксель |
| `android_rect(x, y, w, h, color)` | Прямоугольник |
| `android_touch_x()` / `android_touch_y()` | Координаты касания |
| `android_touch_down()` | Есть ли касание |
| `android_should_finish()` | Запрос закрытия |
| `android_has_focus()` | Фокус приложения |
| `android_touch_count()` | Количество касаний |
| `android_touch_x_index(i)` | X касания i |
| `android_touch_y_index(i)` | Y касания i |
| `android_touch_down_index(i)` | Состояние касания i |
| `android_touch_id_index(i)` | ID касания i |
| `android_http_get(ip, port, path)` | HTTP GET inline (без fork) |
| `android_http_post(ip, port, path, body)` | HTTP POST inline (без fork) |

### Как builtin определяется в компиляторе

В `compiler.zig` (x86-64) код выглядит так:

```zig
fn compileBuiltin(name: []const u8, first_child: NodeIdx, ...) bool {
    if (eq(name, "close")) {
        compileExprNode(first_child, ...)  // rax = fd
        emit(`mov rdi, rax`)
        emit(`mov rax, 3`)    // SYS_CLOSE
        emit(`syscall`)
        return true;
    }
    if (eq(name, "fork")) {
        emit(`mov rax, 57`)   // SYS_FORK
        emit(`syscall`)
        return true;
    }
    // ... 60+ builtins
    return false;  // не builtin
}
```

---

## 11. Системные вызовы (sys.zig)

### Назначение

`sys.zig` (783 строк) — обёртки над системными вызовами Linux (и Win32 стабы) на языке Zig. Используется самим компилятором и рантайм-инструментами.

### Linux x86-64

Все системные вызовы Linux идут через прямые `syscall` инструкции:
- Номер вызова: `rax`
- Аргументы: `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`
- Возврат: `rax`

```zig
pub fn read(fd: i32, buf: [*]u8, len: usize) isize {
    return @bitCast(syscall3(SYS_READ,
        @as(usize, @bitCast(@as(isize, fd))),
        @intFromPtr(buf), len));
}
```

### Список syscall-констант

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

### Вспомогательные функции в sys.zig

Помимо прямых syscall-обёрток, sys.zig содержит:

- `openRead(path)` — открыть файл на чтение
- `openWrite(path)` — открыть файл на запись
- `readAll(fd)` — прочитать всё содержимое файла (с многократными read)
- `fileExists(path)` — проверить, существует ли файл
- `readLine(reader)` — построчное чтение
- `parseInt(buf)` — парсинг числа из строки
- `allocPages(size)` — выделение памяти через mmap
- `resolveHostname(hostname)` — DNS резолвинг (UDP запрос)
- `writeFile(path, data)` — записать файл целиком

### Windows (Win32)

Условная компиляция через `comptime is_windows`:
```zig
if (comptime is_windows) {
    const kernel32 = extern "Kernel32" fn(...) ...;
    // Win32 API через FFI
}
```

Для Linux все Win32 вызовы — стабы, вызывающие `@panic("not implemented")` или `unreachable`.

### DNS резолвинг

`resolveHostname()` — полноценный DNS-резолвер:
1. Проверяет `/etc/hosts`
2. Читает DNS-сервер из `/etc/resolv.conf`
3. Отправляет UDP DNS query на порт 53
4. Парсит DNS ответ: Header (12 байт) → Question → Answer
5. Извлекает A-запись (IPv4 адрес)
6. Fallback: 8.8.8.8:53 если nameserver не найден

---

## 12. Графическая подсистема

### Display бэкенды

| Код | Бэкенд | Платформа | Файл |
|-----|--------|-----------|------|
| 1 | X11 | Linux | x11.zig (416 строк) |
| 2 | fbdev | Linux (framebuffer) | — |
| 3 | memory | Любая (без вывода) | — |
| 10 | Wayland | Linux | wayland.zig (389 строк) |
| 20 | Win32 | Windows | win32.zig (248 строк) |

### Инициализация

`display.zig:init()` пробует бэкенды по порядку:
1. X11 (через Unix socket к `/tmp/.X11-unix/X[n]`)
2. Wayland (через `$XDG_RUNTIME_DIR/wayland-[n]`)
3. Win32 (только на Windows)
4. Linux fbdev (`/dev/fb0`)
5. TTY fallback (режим 3, без графики)

### Абстракция Display

`display.zig` (92 строки) определяет единый интерфейс:
```
init() — инициализация
deinit() — завершение
present(fb) — показать буфер на экране
width / height — размеры окна
```

### Рендеринг (render.zig)

`render.zig` (468 строк) — софтверный 2D-рендерер, рисует в `[]u32` (framebuffer, 32bpp, RGBA):

**Примитивы:**
- Пиксели: `pixel(fb, x, y, color)`
- Прямоугольники: `fillRect(fb, x, y, w, h, color)`
- Линии: `drawLine(fb, x1, y1, x2, y2, color)`
- Окружности: `fillCircle(fb, x, y, r, color)`
- Треугольники: базовый рендеринг треугольников
- Скруглённые прямоугольники: `fillRoundRect(fb, x, y, w, h, r, color)`
- Градиенты: горизонтальные, вертикальные

**Текст:**
- 8x8 моноширинный bitmap шрифт, 95 глифов (ASCII 32–126)
- Каждый глиф — 8 байт (8 строк по 8 пикселей)
- Масштабирование: 1x–3x на основе ширины окна

**Изображения:**
- `blitImage(fb, img, x, y, w, h)` — копирование изображения
- Поддержка альфа-блендинга

**Прочее:**
- Тени: размытые прямоугольники
- Блендинг: альфа-смешивание (src.alpha + dst.(1-alpha))

---

## 13. Сеть и HTTP

### Архитектура

Сеть в dhjsjs реализована единым inline-способом на всех платформах (без fork+exec, без внешних бинарников):

| Способ | Где используется | Описание |
|--------|-----------------|----------|
| Inline socket syscalls | Все платформы | Прямые сисвызовы socket/connect/send/recv, inline DNS, inline TLS |

### HTTP/HTTPS builtins (все платформы)

`http.get()`, `http.post()` и `resolve()` генерируют inline машинный код — без fork+exec, без внешнего `http_client`.

**DNS resolve (`emitInlineResolveX64` / `emitInlineResolveAarch64`):**
1. Создаёт UDP socket
2. Отправляет DNS query на 8.8.8.8:53
3. Ждёт ответ с таймаутом через ppoll
4. Читает ответ
5. Парсит DNS header (12 байт), вопрос, A-запись (type=1, class=1)
6. Возвращает 4 байта IPv4

**HTTP:**
1. Вызывает inline DNS resolve для преобразования hostname → IP
2. Создаёт TCP socket
3. Подключается к серверу
4. Отправляет HTTP/1.0 запрос
5. Читает ответ в цикле до закрытия соединения
6. Возвращает указатель на ответ (стековый буфер)

**TLS/HTTPS:**
- `tls.get()` / `tls.post()` используют встроенную TLS-подсистему (`tls.zig`): handshake, шифрование, расшифровка выполняются inline.
- `https.get()` / `https.post()` — алиасы для `tls.get()` / `tls.post()`.
- Никаких `curl` или внешних программ не требуется.

**`guiApp()` / `guiapp()`:** fork + вызов `gui_srv.main()` (без exec).

### http.zig (клиент для IDE)

`http.zig` (178 строк) — HTTP/1.1 клиент на сокетах (без fork+exec), используется в IDE и инструментах. Это Zig-библиотека, не связанная с компилятором.

---

## 14. Звуковая подсистема

### Вывод звука (OSS)

Использует Open Sound System (`/dev/dsp`):
```
audio_init(sample_rate, channels, format)
  → open("/dev/dsp", O_WRONLY)
  → ioctl(SNDCTL_DSP_SETFMT, format)    // AFMT_S16_LE = 0x10
  → ioctl(SNDCTL_DSP_CHANNELS, channels) // 1=mono, 2=stereo
  → ioctl(SNDCTL_DSP_SPEED, sample_rate) // 44100, 48000, etc.

audio_write(fd, data, len)
  → write(fd, data, len)

audio_close(fd)
  → close(fd)

audio_pause(fd)
  → ioctl(SNDCTL_DSP_RESET)

audio_play(fd)
  → ioctl(SNDCTL_DSP_RESUME)
```

Форматы:
- `0x10` = AFMT_S16_LE (16-bit signed little-endian PCM)
- `0x08` = AFMT_U8 (8-bit unsigned PCM)

### media_player (исполняемый файл)

`media_player.zig` (828 строк) — отдельный исполняемый файл для воспроизведения аудио. Имеет собственный GUI:

- **Поддерживаемые форматы:** WAV, MP3, OGG, FLAC, AIFF
- **Функции:** плейлист, ползунок громкости/позиции, визуализатор, тёмная тема
- **Архитектура:** может быть отдельным процессом; `playerapp()` запускает его через fork+вызов `main()` (без exec). Прямые вызовы `wavplay`/`mp3play` декодируют inline, без отдельного процесса.

### Декодеры (audio.zig)

`audio.zig` (864 строк) содержит декодеры для:

- **WAV** — простой RIFF парсинг, поддержка PCM 8/16/24/32-bit, mono/stereo
- **MP3** — MPEG-1 Layer III декодер (common case: 44.1kHz, joint/simple stereo)
- **OGG Vorbis** — Vorbis декодер (floor type 1, residue 0/1, различные codebooks)
- **FLAC** — Free Lossless Audio Codec (битовый поток, предсказание, остаток)
- **AIFF** — Audio Interchange File Format

Все декодеры реализованы с нуля, без внешних библиотек. На выходе: signed 16-bit PCM 44.1kHz stereo.

Файл также содержит модуль `player.zig` (вынесен в отдельный файл на 377 строк) — движок воспроизведения с буферизацией и микшированием.

---

## 15. GUI — графика и виджеты

### gui.zig — Immediate Mode GUI

`gui.zig` (1531 строк) — библиотека виджетов, построенная по принципу Immediate Mode: каждый кадр программа заново описывает интерфейс. Виджеты не хранят состояние между кадрами.

### mouse.zig — библиотека мыши

`mouse.zig` — отдельный слой ввода для GUI, не использующий `std`, `builtin` или внешние библиотеки.

#### Архитектура

```
Display Backend (X11/Wayland/Win32)
    ↓ sys.Event (mouse_move, mouse_down, mouse_up, scroll)
mouse.State.applyEvent(event)  ← обработка событий
    ↓
mouse.beginFrame() / mouse.endFrame()  ← подготовка кадра
    ↓
InputState.fromMouse(mouse.State)  ← мост в gui.zig
    ↓
Gui.widget(...)  ← виджеты используют состояние
```

#### Структура `mouse.State` (mouse.zig:39-63)

```zig
pub const State = struct {
    x: i32, y: i32,           // текущая позиция курсора
    dx: i32, dy: i32,          // смещение за кадр
    wheel_x: i32, wheel_y: i32, // накопленный скролл
    entered: bool, left: bool,  // вход/выход из окна
    moved: bool,                // движение в этом кадре

    // Удобные поля для PRIMARY (левой кнопки):
    primary_down, primary_pressed, primary_released,
    primary_clicked, primary_double_clicked: bool,

    any_down, any_pressed, any_released: bool, // любая кнопка

    capture_id: u32,   // ID виджета, захватившего мышь (0 = нет)
    hover_id: u32,     // ID виджета под курсором

    buttons: [MAX_BUTTONS+1]ButtonState, // состояние каждой кнопки (1-5)
};
```

#### Структура `ButtonState` (mouse.zig:21-37)

Хранит полное состояние одной кнопки мыши:

| Поле | Описание |
|------|----------|
| `down` | Кнопка зажата |
| `pressed` | Нажата в этом кадре (фронт) |
| `released` | Отпущена в этом кадре (фронт) |
| `clicked` | Отпущена без перетаскивания |
| `double_clicked` | Двойной клик |
| `dragging` | Идёт перетаскивание |
| `drag_started` | Перетаскивание началось в этом кадре |
| `drag_released` | Перетаскивание завершено отпусканием |
| `press_x/y` | Координаты нажатия |
| `release_x/y` | Координаты отпускания |
| `last_click_x/y/frame` | Для детекции двойного клика |

#### Детекция двойного клика (mouse.zig:280-286)

Двойной клик определяется по трём критериям:
- **Время:** не более `DOUBLE_CLICK_FRAMES = 24` кадров между кликами
- **Расстояние:** не более `DOUBLE_CLICK_DIST = 4` пикселей от предыдущего клика
- **Условие:** второй клик должен быть `clicked` (без перетаскивания)

#### Перетаскивание (drag) (mouse.zig:297-309)

Drag активируется при смещении более чем на `DRAG_THRESHOLD = 3` пикселя от точки нажатия. Проверка выполняется как при движении (`moveTo` → `updateDragFlags`), так и при отпускании (`release`).

Вспомогательные функции:
- `isDragging(btn)` — идёт ли перетаскивание
- `dragStarted(btn)` — началось ли в этом кадре
- `dragReleased(btn)` — завершилось ли отпусканием
- `dragX(btn)` / `dragY(btn)` — смещение от точки нажатия

#### Захват мыши (capture) (mouse.zig:161-171)

Позволяет виджету удерживать мышь между кадрами:
- `setCapture(id)` — захватить мышь
- `releaseCapture(id)` — отпустить захват
- `hasCapture(id)` — проверить, удерживает ли виджет захват

**Авто-сброс:** в `endFrame()` capture_id сбрасывается в 0, если ни одна кнопка не зажата (`!any_down`).

В `gui.zig` capture сохраняется между кадрами через `Gui.mouse_capture_id`: в `beginFrame()` он восстанавливается в `mouse_state.capture_id`, в `endFrame()` сохраняется обратно. Это гарантирует, что виджет, захвативший мышь в предыдущем кадре, продолжит получать события.

#### Хит-тесты (mouse.zig:173-188)

Три метода на `mouse.State`:

| Метод | Описание |
|-------|----------|
| `hit(Rect)` | Проверка попадания курсора в прямоугольник |
| `hot(id, Rect)` | Как `hit`, но если захват у другого виджета — возвращает false. Также устанавливает `hover_id`. |
| `capturedOrHot(id, Rect)` | Если виджет владеет захватом — всегда true. Иначе `hot`. |

Утилита `mouse.rect(x, y, w, h)` создаёт `Rect`.

#### Событийный цикл

Каждый кадр:
1. `mouse.beginFrame()` — сбрасывает флаги-однодневки (`pressed`, `released`, `clicked`, `double_clicked`, `drag_started`, `drag_released`), обнуляет `wheel_*`, инкрементирует счётчик кадров
2. Цикл `disp.pollEvent()` → `mouse.applyEvent(event)` — обрабатывает все накопленные события
3. `mouse.endFrame()` — копирует per-button флаги в удобные поля (`primary_*`, `any_*`), авто-сброс capture
4. `InputState.fromMouse(mouse_state)` — создаёт состояние ввода для gui.zig
5. `gui.beginFrame(input_state)` — рисование виджетов
6. `gui.endFrame()` — сохранение capture_id

#### Обработка событий в бэкендах

**X11** (display.zig:69-91): Button 4/5 → scroll вверх/вниз, Button 6/7 → scroll влево/вправо. Остальные кнопки → mouse_down/mouse_up.

**Wayland** (wayland.zig:289-363): Pointer enter/motion → mouse_move (op 0, 2). Button press → mouse_down/mouse_up (op 3) с маппингом: 272→1(L), 273→3(R), 274→2(M), 275→X1, 276→X2. Axis → scroll (op 4).

**Win32** (win32.zig:99-196): WM_MOUSEMOVE/LBUTTONDOWN/UP/RBUTTONDOWN/UP/MBUTTONDOWN/UP/XBUTTONDOWN/UP/MOUSEWHEEL/MOUSEHWHEEL → соответствующие Event.

#### Миграция со старых полей

`gui.zig` всё ещё содержит legacy-поля (`mouse_x`, `mouse_y`, `mouse_down`, `mouse_clicked`, `mouse_released`, `scroll`). В `beginFrame()` (gui.zig:682-687) они перекопируются из `mouse_state` для обратной совместимости. Большинство виджетов (`button`, `slider`, `checkbox`, `textInput`, `collapsible`, `comboBox`) продолжают использовать legacy-поля; `mouse_state` используется через `testHot()` и `setCapture/releaseCapture`.

`gui_srv.zig` использует `mouse.State` напрямую (минуя `InputState`), так как его демо-режим (gui_srv.zig:285-354) был написан после внедрения `mouse.zig`.

#### Полные примеры циклов

**desktop_gui.zig (новый стиль):**
```zig
var m = mouse.State.init();
while (!done) {
    m.beginFrame();
    while (disp.pollEvent()) |event| {
        switch (event) {
            .mouse_move, .mouse_down, .mouse_up, .scroll => m.applyEvent(event),
            else => {}
        }
    }
    m.endFrame();
    var input = gui.InputState.fromMouse(m, ...);
    gui.beginFrame(&input, ...);
    // ... виджеты ...
    gui.endFrame();
}
```

**gui_demo.zig (новый стиль):**
```zig
var m = mouse.State.init();
while (!should_close) {
    m.beginFrame();
    while (disp.pollEvent()) |event| {
        switch (event) {
            .mouse_move, .mouse_down, .mouse_up, .scroll => m.applyEvent(event),
            else => {}
        }
    }
    m.endFrame();
    // ...
}
```

### Жизненный цикл GUI-программы

```
1. guiApp() → fork + exec gui_srv
   (создаёт окно, инициализирует display backend)

2. В цикле:
   a. guiServer() — обрабатывает события (мышь, клавиатура)
   b. beginWindow(...) — начинает окно
   c. label(...), button(...), slider(...) — виджеты
   d. endWindow() — заканчивает окно
```

### gui_srv — сервер GUI

`gui_srv.zig` (585 строк) — отдельный процесс:
1. Инициализирует display backend (X11/Wayland/Win32)
2. Принимает команды через pipe от dhjsjs программы
3. Рендерит виджеты в framebuffer
4. Отправляет события обратно (нажатия, координаты мыши)
5. Поддерживает несколько окон (compositor.zig, 53 строки)

### Система тем (style)

Полностью настраиваемая система стилей (37 полей):

```zig
const Style = struct {
    background: u32,         // цвет фона
    text: u32,               // цвет текста
    button: u32,             // цвет кнопки
    button_hover: u32,
    button_active: u32,
    border: u32,
    title: u32,
    titlebar: u32,
    scrollbar: u32,
    scrollbar_hover: u32,
    // ... 37 полей
};
```

Встроенные темы: `style_dark`, `style_light`, `style_dracula`.

### Встроенные виджеты (gui.zig)

- `beginWindow(title, x, y, w, h, resizable)` / `endWindow()` — окно
- `button(label)` → bool — кнопка
- `label(text)` — текстовая метка
- `labelColored(text, color)` — цветная метка
- `textInput(label, buf)` — поле ввода
- `checkbox(label, checked)` → bool — чекбокс
- `slider(label, value, min, max)` → int — ползунок
- `comboBox(label, items, current)` → int — выпадающий список
- `collapsible(label, open)` → bool — сворачиваемый блок
- `separator()` — разделитель
- `sameLine(spacing)` — следующий виджет на той же строке
- `addSpace(w, h)` — пустое место

### Расширенные виджеты (gui_ext.zig)

`gui_ext.zig` (613 строк):

- `tabBar(labels, count, active)` — вкладки
- `treeView(...)` — дерево
- `scrollArea(...)` — прокручиваемая область
- `menuBar(...)` — строка меню
- `contextMenu(...)` — контекстное меню
- `popup(...)` — всплывающее окно
- `colorPicker(...)` — выбор цвета
- `tooltip(...)` — подсказка
- `progressBar(value, max)` — прогресс-бар
- `knob(...)` — крутилка (knob)
- `led(...)` — индикатор (светодиод)
- `imageView(fb, img, x, y, w, h)` — просмотр изображения
- `table(...)` — таблица
- `canvas(...)` — рисование

### Протокол GUI-команд

guiCmd использует числовые типы команд:

| Type | Команда |
|------|---------|
| 0 | quit |
| 1 | button |
| 2 | slider |
| 3 | label |
| 4 | checkbox |
| 5 | frame |
| 6 | pixel |
| 7 | fill rect |
| 8 | draw line |
| 9 | fill circle |
| 10 | horizontal gradient |
| 11 | vertical gradient |
| 12 | wait |
| 13 | set theme |

---

## 16. Android бэкенд

### Сборка APK

```
dhjsjs_cc build app.dhjsjs --target apk --package com.example.app
```

Процесс сборки APK состоит из 4 этапов:

### Этап 1: Компиляция

Исходник компилируется `compiler_arm.zig` с флагом `keep_alive=true` — после возврата из `main()` добавляется бесконечный цикл, чтобы приложение не завершалось. Результат: ELF64 динамическая библиотека (`buildElf64Dyn()`).

### Этап 2: AndroidManifest.xml (axml.zig)

`axml.zig` (429 строк) генерирует бинарный XML (AXML) — проприетарный формат Android для AndroidManifest.xml:

- Строковый пул (StringPool)
- Список атрибутов с namespace, именем, значением
- Ресурсные ID (android:name → 0x01010003 и т.д.)

Параметры манифеста:
```
package: com.example.app
app-name: "Моё приложение"
min-sdk: 26 (Android 8.0)
version: 1
version-name: "1.0"
permissions: [android.permission.INTERNET, ...]
debuggable: true/false
```

### Этап 3: ZIP/APK сборка (zip.zig)

`zip.zig` (136 строк) — минимальный ZIP-архиватор. Собирает APK:

```
APK = ZIP {
  [Local File Header] AndroidManifest.xml (binary)
  [Local File Header] lib/arm64-v8a/libnative.so (ELF)
  [Central Directory]
  [End of Central Directory]
}
```

- CRC32 вычисляется для каждого файла
- Local File Headers + Central Directory + EOCD
- Минимальная реализация без сжатия (store method)

### Этап 4: Подпись APK (crypto.zig)

`signApk()` подписывает APK:

1. Загружает или генерирует RSA-2048 ключ (сохраняется в `~/.dhjsjs-key.raw`)
2. Вычисляет SHA-256 хеш содержимого APK
3. Создаёт PKCS#7-style signature block
4. Добавляет signature block в конец APK (JAR signing scheme)
5. Флаг `--no-sign` отключает подпись

### android_gui.zig

`android_gui.zig` (246 строк) — реализация NativeActivity:

- **Жизненный цикл:** onCreate → onStart → onResume → onPause → onStop → onDestroy
- **Ввод:** AInputQueue — тач, клавиатура (мультитач до 10 пальцев)
- **Рендеринг:** напрямую в Android window buffer
- **Shared memory:** `AndroidCmd` struct по фиксированному адресу `0x200100`

### android_bridge.zig

`android_bridge.zig` (78 строк) — структуры данных для JNI-моста:

```zig
const AndroidCmd = extern struct {
    activity: ?*anyopaque,
    window: ?*anyopaque,
    width: i32,
    height: i32,
    fb_ptr: ?*anyopaque,
    stride: i32,
    // touch input queue
    touch_count: i32,
    touch_x: [10]f32,
    touch_y: [10]f32,
    touch_down: [10]bool,
    touch_id: [10]i32,
    // lock/unlock
    lock: ?*anyopaque,
    unlock: ?*anyopaque,
    // present
    present: ?*anyopaque,
};
```

### Android-специфичные builtins

На Android `http.get()`, `http.post()` и `resolve()` РАБОТАЮТ через inline ARM64 код — они генерируют прямые сисвызовы socket/connect/send/recv и inline DNS-запросы без создания дочернего процесса.

Также доступны низкоуровневые `android_http_get(ip, port, path)` и `android_http_post(ip, port, path, body)`, которые принимают IP как 32-битное число и не выполняют DNS — полезно, когда IP уже известен.

### android_styles.zig

`android_styles.zig` (646 строк) — константы цветов и стилей Material Design для Android-тем.

---

## 17. Windows PE64 бэкенд

### Сборка

```
dhjsjs_cc build app.dhjsjs --target windows
```

### buildPe64() в codegen.zig

Генерирует полноценный PE32+ исполняемый файл для Windows x86-64:

```
DOS Header (MZ)
  e_magic: 0x5A4D ('MZ')
  e_lfanew: смещение到 PE Header

PE Header (PE32+)
  Machine: 0x8664 (AMD64)
  NumberOfSections: 2

Section .text (code):
  VirtualSize: размер кода
  Characteristics: CODE | EXECUTE | READ

Section .data (данные):
  VirtualSize: размер данных
  Characteristics: INITIALIZED_DATA | READ | WRITE

Optional Header:
  AddressOfEntryPoint: RVA точки входа
  ImageBase: 0x140000000
  SizeOfStackReserve: 0x100000 (1MB)
  SizeOfStackCommit: 0x1000 (4KB)
  Subsystem: 3 (CONSOLE)
```

### Ограничения Windows бэкенда

- Только x86-64
- Нет libc — все системные вызовы через Win32 API
- Нет GUI-виджетов (используются только Win32 GDI примитивы)
- Сеть через Winsock

---

## 18. Микроконтроллеры: ESP32 (RISC-V) и AVR (Arduino)

### Сборка и прошивка

```
# RISC-V (ESP32-C3/C6)
dhjsjs_cc build app.dhjsjs --target riscv32
dhjsjs_cc flash app.dhjsjs --target esp32 --port /dev/ttyUSB0

# AVR (Arduino Uno/Nano/Mega)
dhjsjs_cc build app.dhjsjs --target avr -o app.hex
# прошивка через avrdude:
# avrdude -p atmega328p -c arduino -P /dev/ttyUSB0 -b 115200 -U flash:w:app.hex
```

### esp.zig (291 строка) — ESP32 протокол прошивки

Реализует протокол esptool для последовательного порта:

1. SLIP-кодирование (0xC0 фрейминг, экранирование байтов 0xDB)
2. Команды:
   - `SYNC` — синхронизация с чипом (до 15 попыток)
   - `FLASH_BEGIN` — начало записи flash
   - `FLASH_DATA` — передача пакета данных
   - `FLASH_END` — завершение
3. Настройки UART: 115200 бод, 8N1, termios
4. Парсинг ELF: чтение Program Headers, извлечение .text сегмента
5. Отправка данных пакетами по 4096 байт с CRC-проверкой

### compiler_rv.zig для ESP32

- 32-битные регистры (x0-x31)
- Программная эмуляция умножения/деления при необходимости
- Выходной формат: ELF32
- Размер кода ограничен доступной flash-памятью ESP32 (обычно 4MB)

---

## 19. Криптография (crypto.zig)

### Назначение

`crypto.zig` (837 строк) — криптографическая библиотека, реализованная с нуля для подписи APK. Содержит SHA-256 и RSA.

### SHA-256

Полная реализация хеш-функции SHA-256 (FIPS 180-4):
- 64 раунда с K-константами
- Функция сжатия: `sha256Block(state, block)`
- Padding: дополнение до 56 mod 64 байт + 8 байт длины в битах
- Big-endian представление

```zig
fn sha256(data: []const u8) [32]u8 {
    var state: [8]u32 = [8]u32{
        0x6A09E667, 0xBB67AE85, 0x3C6EF372,
        0xA54FF53A, 0x510E527F, 0x9B05688C,
        0x1F83D9AB, 0x5BE0CD19,
    };
    // обработка блоков по 64 байта
    // ...
    return result;
}
```

### RSA-2048

Генерация и подпись RSA-2048:
- **Большие числа:** `Bi` struct с массивом лимбов (2048 бит ≈ 32 лимба по 64 бит)
- Операции: `biFromBytes()`, `biToBytes()`, сложение, умножение, модульное возведение в степень
- `rsaGenerateKey()` — генерация пары (p, q, n, e, d, dp, dq, qinv)
- Подпись: возведение в степень d по модулю n (m^d mod n)

### APK Signing

Схема JAR-подписи APK:
1. Вычисляется SHA-256 дайджест всего APK-файла
2. Дайджест кодируется в PKCS#7-подобный signature block
3. Signature block подписывается RSA-2048
4. Подпись дописывается в конец APK

Генерация ключа при первом запуске, сохранение в `~/.dhjsjs-key.raw`.

---

## 20. Транспиляция в C

### Команда

```
dhjsjs_cc transpile app.dhjsjs -o app.c
```

### Как работает

Транспилятор обходит AST и генерирует эквивалентный код на C:

1. **Пролог:** добавляет `#include <stdlib.h>`, `<stdio.h>`, `<stdint.h>`
2. **Функции:** для каждого `fn_decl` генерирует `int64_t name() { ... }`
3. **Типы:** все переменные — `int64_t` (упрощение, так как dhjsjs не имеет строгой типизации struct на уровне C)
4. **Управление:**
   - `if/uebok` → `if (...) { ... } else { ... }`
   - `while` → `while (...) { ... }`
   - `return` → `return expr;`
5. **Выражения:**
   - Литералы → числа/строки
   - Идентификаторы → имена переменных
   - Бинарные операции → `(left op right)`
   - Вызовы функций → `name(args...)`
   - Доступ к полям → `base.field`
   - Индексация массивов → `arr[index]`
   - Адрес/разыменование → `(&expr)` / `(*expr)`
   - sizeof → `sizeof(expr)`

### Ограничения транспилятора

- Не обрабатывает `struct_decl` (все значения — int64_t)
- Не обрабатывает `activity_decl` и Android-специфичные конструкции
- Не обрабатывает builtin-функции (print, open, и т.д.)
- Результат — это скелет, требующий ручной доработки

---

## 21. IDE — среда разработки

### main.zig (336 строк) — точка входа IDE

IDE обнаруживает доступный display backend:
1. X11
2. Wayland
3. fbdev
4. TTY fallback

Окружение: `DHJSJS_W` и `DHJSJS_H` для размера окна.

### ide.zig (617 строк) — редактор кода

`IdeState` — состояние редактора:

```zig
const IdeState = struct {
    filename: [256]u8,     // имя текущего файла
    data: [65536]u8,       // буфер исходного кода
    data_len: u32,         // длина данных
    cx: u32, cy: u32,      // позиция курсора
    modified: bool,        // флаг изменений
    blink: bool,           // мигание курсора
    scroll_x: u32,         // скролл
    console: [8192]u8,     // буфер консоли
    console_len: u32,
    mode: enum { edit, save, open, ... },
};
```

### Интерфейс IDE (сверху вниз)

1. **Меню-бар:** "File Edit Sketch Tools Help"
2. **Тулбар:** "[Verify] [Upload] [New] [Open] [Save]"
3. **Табы:** имя активного файла с индикатором изменений
4. **Редактор:** нумерация строк + подсветка синтаксиса
5. **Консоль:** панель вывода сборки
6. **Статус-бар:** сообщения о состоянии сборки

### Подсветка синтаксиса

Алгоритм — `isKw()` определяет ключевые слова:
- Синий: `fn`, `hui`, `if`, `uebok`, `return`, `while`, `struct`, `true`, `false`
- Оранжевый/коричневый: строки в кавычках
- Зелёный: числа
- Серый/зелёный: комментарии `//` и `/* */`

### Сборка из IDE

`buildProject()` в `main.zig`:
1. Читает исходник из буфера
2. Парсит в AST
3. Компилирует для x86-64 → `output/out.bin` (ELF)
4. Компилирует для ARM64 → `output/out_arm64.bin` (ELF)
5. Выводит ошибки в консоль

### TTY fallback

`tty.zig` (254 строки) — текстовый режим для терминалов без графики. Использует ANSI escape-коды для позиционирования и цветов. Поддерживает:
- Редактирование текста
- Псевдографику для кнопок и меню
- Цветовое выделение

---

## 22. CLI — интерфейс командной строки

### cli.zig (675 строк) — драйвер компилятора

Парсит `/proc/self/cmdline` (raw null-separated строки, без libc) и выполняет команды:

```
dhjsjs_cc <command> [src] [flags]
```

### Команды

| Команда | Описание |
|---------|----------|
| `build` | Собрать исполняемый файл |
| `run` | Собрать и сразу запустить |
| `new` | Создать проект-заготовку |
| `flash` | Собрать и прошить ESP32 |
| `transpile` | Преобразовать в C |
| `--help`, `-h` | Справка |

### Флаги build

| Флаг | Описание |
|------|----------|
| `-o <path>` / `--output <path>` | Выходной файл |
| `--target <arch>` | Целевая архитектура |
| `--release` | Режим релиза (APK) |
| `--package <name>` | Android package name |
| `--app-name <name>` | Имя Android приложения |
| `--permission <perm>` | Android permission (можно多次) |
| `--min-sdk <n>` | Минимальный Android SDK |
| `--version <n>` | Android versionCode |
| `--version-name <s>` | Android versionName |
| `--no-sign` | Не подписывать APK |

### compileSource() — ядро компиляции

1. Читает исходный файл в буфер (ReadResult)
2. Инициализирует ErrorList и Parser
3. Парсит AST
4. Если ошибки — выводит и завершается
5. Выбирает target (native → uname, или указанный)
6. Диспетчеризует на нужный компилятор:
   - `.x86_64` → `compiler.zig`, `codegen.zig:buildElf64()`
   - `.aarch64` → `compiler_arm.zig`, `codegen_arm.zig:buildElf64()`
   - `.riscv32` → `compiler_rv.zig`, `codegen_rv.zig:buildElf32()`
   - `.apk` → `compiler_arm.zig:compileEx()`, `codegen_arm.zig:buildElf64Dyn()` + упаковка в APK
   - `.windows` → `compiler.zig`, `codegen.zig:buildPe64()`
   - `.raw` → `compiler_arm.zig`, сырой бинарник
7. Записывает выходной файл с правами 0755

### cmdRun

Собирает временный ELF в `/tmp/dhjsjs_run_XXXXXX`, делает `chmod +x`, запускает через `execve` и ждёт завершения.

### cmdNew

Создаёт директорию проекта:
```
myapp/
  src/
    main.dhjsjs   // шаблон с fn main()
```

### Разрешение target

`--target native` → `hostTarget()` читает `uname()` (SYS_UNAME=63, поле `machine`):
- `"x86_64"` → `.x86_64`
- `"aarch64"` → `.aarch64`
- Всё остальное → `.x86_64` (по умолчанию)

---

## 23. Обработка ошибок (errors.zig)

### Назначение

`errors.zig` (185 строк) — система сбора и отображения ошибок компиляции.

### ErrorKind (24 типа)

**Лексер (3):**
- `invalid_char` — недопустимый символ
- `unterminated_string` — незакрытая строка
- `unterminated_block_comment` — незакрытый блочный комментарий

**Парсер (12):**
- `unexpected_eof` — неожиданный конец файла
- `unexpected_token` — неожиданный токен
- `expected_semicolon` — ожидалась `;`
- `expected_open_paren` — ожидалась `(`
- `expected_close_paren` — ожидалась `)`
- `expected_open_brace` — ожидалась `{`
- `expected_close_brace` — ожидалась `}`
- `expected_expression` — ожидалось выражение
- `expected_identifier` — ожидался идентификатор
- `expected_colon` — ожидалось `:`
- `duplicate_fn` — функция с таким именем уже объявлена
- `invalid_declaration` — неверное объявление

**Компилятор (9):**
- `undefined_var` — переменная не определена
- `undefined_fn` — функция не определена
- `type_mismatch` — несоответствие типов
- `wrong_arg_count` — неверное количество аргументов
- `unused_var` — переменная не используется
- `missing_return` — отсутствует return
- `deref_non_pointer` — разыменование не-указателя
- `stack_overflow` — превышение размера стека
- `internal_error` — внутренняя ошибка

### ErrorList

```zig
const ErrorList = struct {
    errors: [64]Error,       // максимум 64 ошибки
    count: u32,
};

const Error = struct {
    kind: ErrorKind,
    line: u32,
    col: u32,
    message: [128]u8,
    hint: [128]u8,
};
```

### Вывод ошибок

`printAll()` форматирует ошибки в читаемый вид:

```
error [строка:столбец]: описание ошибки
ожидалось '...'
 | ваш код
 | ^
```

Пример:
```
error [5:12]: undefined variable 'x'
expected expression
 |     hui y = x + 1
 |             ^
```

---

## 24. Форматы выходных файлов

### ELF64 (x86-64, AArch64 Linux)

`buildElf64()` в codegen.zig / codegen_arm.zig:

```
[ELF Header]
  e_ident: 7F 45 4C 46 (ELF magic)
  e_machine: 62 (EM_X86_64) или 0xB7 (EM_AARCH64)
  e_entry: адрес _start

[Program Header - LOAD код]
  p_offset: 0
  p_vaddr: 0x400000
  p_filesz: размер кода
  p_memsz: размер кода
  p_flags: PF_R | PF_X

[Program Header - LOAD данные]
  p_offset: после кода
  p_vaddr: 0x400000 + размер_кода
  p_filesz: размер данных + стек
  p_memsz: размер данных + стек
  p_flags: PF_R | PF_W

[Машинный код]

[Строковые данные (R/O)]

[Стек (BSS)]
```

### ELF64 Dynamic (Android)

`buildElf64Dyn()` — ELF64 shared library для Android linker:
- Program headers: PT_DYNAMIC, PT_LOAD
- Динамические секции для Android ld

### ELF32 (RISC-V)

`buildElf32()` — 32-битная версия ELF:
```
e_machine: 243 (EM_RISCV)
p_vaddr: 0x400000 (32-битный)
```

### PE64 (Windows)

`buildPe64()` in codegen.zig:
```
DOS Header (MZ) + PE Header (PE32+)
  Machine: 0x8664 (AMD64)
  ImageBase: 0x140000000

Section .text: CODE | EXECUTE | READ
Section .data: DATA | READ | WRITE

Subsystem: 3 (CONSOLE)
Stack: 1MB reserve, 4KB commit
```

### Размеры бинарников

| Бинарь | Размер (stripped) |
|--------|-------------------|
| dhjsjs_cc | ~10 MB |
| dhjsjs | ~6 MB |
| Hello World (dhjsjs) | ~292 bytes |

Большой размер обусловлен тем, что Zig 0.16 не выкидывает неиспользуемый код при `build-exe` без `std`.

---

## 25. Паросочетание вызовов через точку (http.get)

### Проблема

Исходный код `http.get("host", "/path")` выглядит как доступ к полю структуры `http`, а затем вызов метода `get`.

### Решение в парсере

В `parser.zig` (~строка 588) после парсинга идентификатора и точки, если следующий токен — идентификатор и затем `(`, парсер объединяет их в один вызов:

```
http.get("host", "/path")
  → парсим "http" как ident
  → парсим "." как точку
  → парсим "get" как ident
  → парсим "(" — вызов!
  → создаём узел call с именем "http.get"
```

### В компиляторе

Компилятор проверяет имя функции на совпадение с `http.get`, `http_get`, `httpget` (и аналогично для post) и генерирует соответствующий builtin.

Это позволяет использовать три формы записи:
- `http.get(host, path)`
- `http_get(host, path)`
- `httpget(host, path)`

---

## 26. Ограничения компилятора

### Фиксированные размеры

| Параметр | Максимум | Константа |
|----------|----------|-----------|
| Узлов AST | 2048 | `MAX_NODES` |
| Переменных на функцию | 64 | `MAX_VARS` |
| Функций на файл | 32 | `MAX_FUNCTIONS` |
| Размер CodeBuffer | 65536 байт | `code_buf_size` |
| Размер исходного файла | 65536 байт | — |
| Ошибок компиляции | 64 | `MAX_ERRORS` |
| Длина имени переменной | 63 символа | `MAX_NAME_LEN` |
| Длина сообщения ошибки | 127 символов | — |

### Языковые ограничения

- Нет динамического выделения памяти для строк
- Нет замыканий (closures)
- Нет анонимных функций
- Нет generic-типов
- Нет модульной системы
- Нет сборщика мусора
- Нет исключений (только коды возврата)
- Типизация — номинальная, без приведения типов

### Платформенные ограничения

- Аудио только через OSS (`/dev/dsp`), не ALSA/PulseAudio
- GUI только через pipe-протокол с gui_srv
- ESP32-C3/C6: RISC-V 32-bit (ESP32, ESP32-S2/S3 с Xtensa — в разработке)
- AVR: Arduino (ATmega, ATtiny) — базовая поддержка, без умножения/деления

---

## 27. Сборка и Makefile

### Makefile

Собирает 6 бинарников одной командой `make`:

```
make          # сборка всех бинарников (debug)
make release  # сборка с оптимизацией ReleaseSafe + strip
make clean    # очистка
```

### Цели сборки

```
dhjsjs           — IDE, редактор кода (обязателен)
dhjsjs_cc        — компилятор командной строки (обязателен)
media_player     — аудио плеер (опционально, standalone)
desktop_gui      — демо GUI (опционально)
gui_srv          — сервер GUI (опционально)
http_client      — HTTP клиент (опционально, standalone)
```

Каждый бинарник собирается отдельной командой `zig build-exe` с указанием всех исходных файлов.

### Зависимости

- Zig 0.16+ (единственная зависимость)
- Linux (для рантайма, но компилятор кроссплатформенный)
- Никаких внешних библиотек, libc, LLVM

---

## 28. Все файлы проекта

### Исходный код (src/)

| Файл | Строк | Назначение |
|------|-------|------------|
| `compiler.zig` | 3179 | Компилятор x86-64 (AST → машкод) |
| `gui.zig` | 1531 | Библиотека GUI-виджетов |
| `compiler_arm.zig` | 1137 | Компилятор ARM64 |
| `audio.zig` | 864 | Декодеры аудио + player |
| `crypto.zig` | 837 | SHA-256, RSA, APK подпись |
| `parser.zig` | 836 | Парсер (рекурсивный спуск) |
| `media_player.zig` | 828 | Аудио плеер (исполняемый) |
| `sys.zig` | 783 | Системные вызовы |
| `cli.zig` | 675 | CLI драйвер |
| `android_styles.zig` | 646 | Material Design темы |
| `codegen.zig` | 623 | x86-64 кодогенератор |
| `ide.zig` | 617 | Редактор IDE |
| `gui_ext.zig` | 613 | Расширенные виджеты |
| `gui_srv.zig` | 585 | GUI сервер |
| `codegen_arm.zig` | 549 | ARM64 кодогенератор |
| `render.zig` | 468 | 2D рендерер |
| `compiler_rv.zig` | 464 | Компилятор RISC-V |
| `axml.zig` | 429 | Android AXML генератор |
| `x11.zig` | 416 | X11 протокол |
| `wayland.zig` | 389 | Wayland протокол |
| `player.zig` | 377 | Плеер (движок) |
| `main.zig` | 336 | IDE точка входа |
| `esp.zig` | 291 | ESP32 прошивка |
| `codegen_rv.zig` | 271 | RISC-V кодогенератор |
| `codegen_avr.zig` | 280 | AVR кодогенератор |
| `compiler_avr.zig` | 460 | Компилятор AVR (Arduino) |
| `desktop_gui.zig` | 255 | Демо GUI |
| `tty.zig` | 254 | TTY интерфейс |
| `win32.zig` | 248 | Win32 GDI |
| `android_gui.zig` | 246 | Android GUI |
| `gui_demo.zig` | 232 | Демо GUI |
| `http_client.zig` | 217 | HTTP клиент |
| `lexer.zig` | 207 | Лексер |
| `errors.zig` | 185 | Ошибки компиляции |
| `http.zig` | 178 | HTTP клиент (библиотека) |
| `zip.zig` | 136 | ZIP/APK архиватор |
| `display.zig` | 92 | Абстракция дисплея |
| `android_bridge.zig` | 78 | JNI мост |
| `utils.zig` | 65 | Утилиты (memcpy, strlen) |
| `compositor.zig` | 53 | Композитор окон |
| `builtin.zig` | 1 | Заглушка (page_size) |

**Всего:** ~19,800 строк Zig-кода.

### Примеры (examples/)

| Файл | Описание |
|------|----------|
| `test_simple.dhjsjs` | Hello World (5 строк) |
| `test_basic.dhjsjs` | Базовый синтаксис |
| `test_var_add.dhjsjs` | Сложение переменных |
| `test_if_else.dhjsjs` | If/uebok |
| `test_while.dhjsjs` | While цикл |
| `test_struct.dhjsjs` | Структуры |
| `test_array.dhjsjs` | Массивы |
| `test_ptr_var.dhjsjs` | Указатели |
| `test_addr_deref.dhjsjs` | Адрес и разыменование |
| `test_sizeof.dhjsjs` | Sizeof |
| `test_bits.dhjsjs` | Битовые операции |
| `test_comparison.dhjsjs` | Сравнения |
| `test_mul.dhjsjs` | Умножение |
| `test_nested_block.dhjsjs` | Вложенные блоки |
| `test_syscall.dhjsjs` | Системные вызовы |
| `lexer.dhjsjs` | Самодостаточный лексер (self-hosting) |
| `gui_app.dhjsjs` | GUI приложение |
| `gui_demo.dhjsjs` | Демо GUI |
| `gui_android.dhjsjs` | Android GUI |
| `audio_player.dhjsjs` | Аудио плеер |
| `http_test.dhjsjs` | HTTP клиент |
| `simple_sock.dhjsjs` | Сокеты |

### Документация

| Файл | Описание |
|------|----------|
| `README.md` | Быстрый старт и описание |
| `GUIDE_RU.md` | Руководство пользователя |
| `COMPILER_RU.md` | Техническая документация (этот файл) |
| `SUMMARY.md` | Краткое описание |

### Внешние файлы

| Файл | Описание |
|------|----------|
| `syntaxes/dhjsjs.tmLanguage.json` | Подсветка для VS Code / Sublime |
| `syntaxes/dhjsjs.vim` | Подсветка для Vim |
| `.vscode/` | Настройки VS Code |
| `Makefile` | Сборка |

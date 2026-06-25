# dhjsjs

Минималистичный компилятор собственного языка программирования, написанный на **Zig** с нуля — без libc, без LLVM, только raw syscalls и ручная кодогенерация. Поддерживает HTTP/HTTPS, GUI, аудио, кросс-компиляцию под Windows, Android, ARM64, RISC-V.

## Возможности

- **Нативный x86-64 ELF** — компиляция в исполняемые бинарники без внешних зависимостей
- **Кросс-компиляция** — aarch64 (ELF64) и riscv32 (ELF32), а также ESP32 (с настройкой)
- **Свой язык** — простой синтаксис с функциями, переменными, условиями, циклами
- **Среда разработки** — встроенный терминальный IDE с подсветкой, запуском и сборкой
- **Красивый GUI** — immediate-mode виджеты, градиенты, тени, свечение, кастомные стили (5 тем + setStyle)
- **Собственный шрифт** — переработанный 8x8 битмап-шрифт (95 глифов ASCII 32-126)
- **Zero deps** — единственная зависимость: Zig 0.16 компилятор

## Быстрый старт

```bash
# Сборка
make

# Новый проект
./dhjsjs_cc new myapp
cd myapp
../dhjsjs_cc build
../dhjsjs_cc run

# Запуск одного файла
./dhjsjs_cc run examples/hello.dhjsjs

# Сборка под другую архитектуру
./dhjsjs_cc build examples/hello.dhjsjs --target aarch64
./dhjsjs_cc build examples/hello.dhjsjs --target riscv32
```

## CLI

```
dhjsjs_cc new <project>    — создать каркас проекта
dhjsjs_cc build [src]      — скомпилировать в ELF
dhjsjs_cc run   [src]      — скомпилировать и запустить
dhjsjs_cc flash <src>      — скомпилировать и прошить на ESP32 через UART
dhjsjs_cc transpile <src>  — транспилировать dhjsjs-код в C
```

Флаги:
- `-o <file>` / `--output <file>` — путь выходного файла (build)
- `--target <arch>` — архитектура: `x86_64`, `aarch64`, `riscv32`

## Синтаксис языка

```
fn main() int {
    hui x = 42;
    if x {
        return x;
    }
    return 0;
}
```

### Ключевые слова

`fn`, `hui`, `if`, `uebok`, `return`, `while`,
`activity`, `compose`, `state`, `viewmodel`,
`true`, `false`, `null`, `int`, `string`, `bool`, `void`

### Операторы (по приоритету)

| Приоритет | Операторы | Описание |
|-----------|-----------|----------|
| 5 (унарные) | `!` `-` | логическое НЕ, унарный минус |
| 4 | `*` `/` | умножение, деление |
| 3 | `+` `-` | сложение, вычитание |
| 2 | `==` `!=` `<` `>` `<=` `>=` | сравнения |
| 1 | `&&` | логическое И |
| 0 | `\|\|` | логическое ИЛИ |

### Типы данных

- `int` — целое число (64-bit signed)
- `string` — строка
- `bool` — булево
- `void` — отсутствие значения

## Структура проекта

```
src/
  main.zig      — IDE (терминальный редактор)
  cli.zig       — CLI утилита (компиляция, запуск, создание проектов)
  lexer.zig     — лексический анализатор
  parser.zig    — синтаксический анализатор
  compiler.zig  — кодогенерация (обёртка над codegen)
  codegen.zig   — x86-64 + ELF64 кодогенератор
  codegen_arm.zig — AArch64 + ELF64 кодогенератор
  codegen_rv.zig  — RISC-V 32-bit + ELF32 кодогенератор
  sys.zig       — raw syscall обёртки
  x11.zig       — X11 протокол (IDE)
  wayland.zig   — Wayland протокол (IDE)
  render.zig    — рендеринг шрифтов/графики (IDE)
  ide.zig       — логика редактора
  tty.zig       — TTY/Terminal интерфейс (IDE)
syntaxes/
  dhjsjs.tmLanguage.json — TextMate грамматика (VS Code, Sublime)
  dhjsjs.vim             — Vim подсветка синтаксиса
```

## Сборка под ESP32

```bash
./dhjsjs_cc build src/main.dhjsjs --target riscv32
# или используйте кодогенератор напрямую для интеграции
```

## Размер бинарников

| Бинарь | Размер (stripped) |
|--------|-------------------|
| dhjsjs_cc | ~10 MB |
| dhjsjs     | ~6 MB  |
| helloworld (dhjsjs) | ~292 bytes |

Большой размер обусловлен тем, что Zig 0.16 не умеет выкидывать неиспользуемый код из корневой точки входа при `build-exe` без `std`. Оптимизация размера — в планах.

## Кросс-компиляция: RISC-V 32 и ARM64

Генерация кода для нескольких архитектур из одного исходника:

| Архитектура | Формат | Целевые устройства |
|-------------|--------|-------------------|
| x86_64 | ELF64 | Десктоп, сервер |
| aarch64 | ELF64 | Raspberry Pi, Apple Silicon |
| riscv32 | ELF32 | ESP32-C3, ESP32-C6 |

Примеры сборки:

```bash
./dhjsjs_cc build app.dhjsjs --target riscv32
./dhjsjs_cc build app.dhjsjs --target aarch64
```

## Команда flash (ESP32)

Компилирует код и прошивает его на ESP32-C3/C6 через UART:

```bash
./dhjsjs_cc flash app.dhjsjs
```

Флаги:
- `--port <port>` — порт UART (по умолчанию `/dev/ttyUSB0`)
- `--baud <rate>` — скорость (по умолчанию `115200`)

## Команда transpile (dhjsjs → C)

Транспиляция dhjsjs-кода в чистый C без внешних зависимостей:

```bash
./dhjsjs_cc transpile app.dhjsjs -o app.c
```

Сгенерированный C-файл можно скомпилировать любым C-компилятором (gcc, clang, zig cc).

## Самостоятельная компиляция (self-hosting)

Компилятор dhjsjs способен скомпилировать сам себя. Пример лексического анализатора, написанного на dhjsjs, находится в `examples/lexer.dhjsjs`:

```bash
./dhjsjs_cc run examples/lexer.dhjsjs
```

Это демонстрирует, что язык достаточно выразителен для написания собственных инструментов разработки.

## Лицензия

MIT

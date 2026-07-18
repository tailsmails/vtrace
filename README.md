# vtrace

An automated execution tracer and step-by-step source code instrumenter for the V programming language. It modifies your V code at compile-time to log variable state changes, function entry scopes, line-by-line execution elapsed times, and thread-safe output formatting.

---

## Quick Start

Run this one-liner command to update your system package list, install compiler dependencies, build V from source (if not already installed), clone this repository, compile the tool with production optimizations, and link it globally:

```bash
apt update -y && apt install -y git clang make && if ! command -v v >/dev/null 2>&1; then git clone --depth=1 https://github.com/vlang/v && cd v && make && ./v symlink && cd ..; fi && git clone --depth=1 https://github.com/tailsmails/vtrace && cd vtrace && v -prod vtrace.v -o vtrace && ln -sf $(pwd)/vtrace $PREFIX/bin/vtrace
```

---

## How It Works

This tool intercepts your source code before compilation:
1. It copies your target directory or file into an isolated temporary folder (`.vtrace_temp`).
2. It parses each `.v` file, injecting tracing logic at function entry points and after assignments, updates, or channel transmissions.
3. It generates an embedded, thread-safe module called `vtrace_helpers.v` to safely log metrics using global mutex locks.
4. It compiles the modified code. If run in standard mode, it executes the binary immediately and cleans up. If run in compile-only mode, it keeps the compiled assets and outputs a single self-contained tracing source file.

---

## Usage

```bash
vtrace [flags] <file_or_directory> [compiler_flags] [-- program_arguments]
```

### Options

* **`-bw`**  
  Disables ANSI escape colors, rendering the trace output in plain black-and-white.
  
* **`-c`**  
  Traces and compiles only. Skipping execution, this option outputs:
  * A compiled binary with the `.vt` extension (e.g., `app.vt`).
  * A self-contained instrumented source file with the `.vt.v` extension (e.g., `app.vt.v`).

---

## Compilation Output

When running with the `-c` flag on a single file like `test.v`, the directory will contain:
* `test.vt`: The compiled, trace-enabled binary.
* `test.vt.v`: A single, self-contained V source file containing all instrumented code alongside the internal thread-safe tracer implementation.

You can compile or run the generated `.vt.v` file manually at any time. Because V prevents unreferenced global variables by default, you must always append the `-enable-globals` flag:

```bash
v -enable-globals run test.vt.v
```

---

## Sample Output

Given a standard parallel work loop with shared memory access, the trace log prints structured lines depicting depth levels, function context, execution timestamp, file position, line elapsed duration, and updated variable structures:

```text
Walking and instrumenting directory: . ...
Compiling: v -cc gcc -enable-globals -o "./.vtrace_temp/vtrace_temp_exec" "./.vtrace_temp" ...
Executing: "./.vtrace_temp/vtrace_temp_exec"
----------------------------------------
┌── Entering main()
├── [main] [13:25:01.104] main.v:14 (0 ns) === Launching Parallel Workers ===
├── [main] [13:25:01.104] main.v:17 (320 μs) -> spawn worker(1)
├── [main] [13:25:01.105] main.v:18 (90 μs) -> spawn worker(2)
┌── Entering worker(id = 1)
├── [worker] [13:25:01.105] main.v:7 (0 ns) -> task_counter = 0
├── [worker] [13:25:01.105] main.v:8 (150 ns) -> task_counter = 1
├── [worker] [13:25:01.110] main.v:9 (5.006 ms) -> time.sleep(5 * time.millisecond)
├── [worker] [13:25:01.110] main.v:10 (45 ns) -> task_counter = 11
┌── Entering worker(id = 2)
├── [worker] [13:25:01.110] main.v:7 (0 ns) -> task_counter = 0
├── [worker] [13:25:01.110] main.v:8 (145 ns) -> task_counter = 1
├── [worker] [13:25:01.115] main.v:9 (5.004 ms) -> time.sleep(5 * time.millisecond)
├── [worker] [13:25:01.115] main.v:10 (40 ns) -> task_counter = 11
├── [main] [13:25:01.120] main.v:20 (15.120 ms) -> time.sleep(15 * time.millisecond)
├── [main] [13:25:01.120] main.v:21 (150 μs) === Complete ===
```

---

## License
![License](https://img.shields.io/badge/License-MIT-green.svg)

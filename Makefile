all: dhjsjs dhjsjs_cc

dhjsjs: src/*.zig
	zig build-exe src/main.zig --name dhjsjs --cache-dir .zig-cache

dhjsjs_cc: src/*.zig
	zig build-exe src/cli.zig --name dhjsjs_cc --cache-dir .zig-cache

release: src/*.zig
	zig build-exe src/main.zig --name dhjsjs --cache-dir .zig-cache -Doptimize=ReleaseSafe
	strip dhjsjs
	zig build-exe src/cli.zig --name dhjsjs_cc --cache-dir .zig-cache -Doptimize=ReleaseSafe
	strip dhjsjs_cc

run: dhjsjs
	./dhjsjs

clean:
	rm -rf dhjsjs dhjsjs_cc .zig-cache zig-out output

.PHONY: all release run clean

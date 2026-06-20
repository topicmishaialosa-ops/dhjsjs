all: dhjsjs dhjsjs_cc media_player

dhjsjs: src/*.zig
	zig build-exe src/main.zig --name dhjsjs --cache-dir .zig-cache

dhjsjs_cc: src/*.zig
	zig build-exe src/cli.zig --name dhjsjs_cc --cache-dir .zig-cache

media_player: src/*.zig
	zig build-exe src/media_player.zig --name media_player --cache-dir .zig-cache

release: src/*.zig
	zig build-exe src/main.zig --name dhjsjs --cache-dir .zig-cache -Doptimize=ReleaseSafe
	strip dhjsjs
	zig build-exe src/cli.zig --name dhjsjs_cc --cache-dir .zig-cache -Doptimize=ReleaseSafe
	strip dhjsjs_cc
	zig build-exe src/media_player.zig --name media_player --cache-dir .zig-cache -Doptimize=ReleaseSafe
	strip media_player

run: dhjsjs
	./dhjsjs

run-player: media_player
	./media_player

clean:
	rm -rf dhjsjs dhjsjs_cc media_player .zig-cache zig-out output

.PHONY: all release run run-player clean

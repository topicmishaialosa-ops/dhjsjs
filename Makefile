all: dhjsjs dhjsjs_cc media_player desktop_gui gui_srv http_client tls_client

dhjsjs: src/*.zig
	zig build-exe src/main.zig --name dhjsjs --cache-dir .zig-cache

dhjsjs_cc: src/*.zig
	zig build-exe src/cli.zig --name dhjsjs_cc --cache-dir .zig-cache -lvulkan -lX11 -fPIC

media_player: src/*.zig
	zig build-exe src/media_player.zig --name media_player --cache-dir .zig-cache

desktop_gui: src/*.zig
	zig build-exe src/desktop_gui.zig --name desktop_gui --cache-dir .zig-cache

gui_srv: src/*.zig
	zig build-exe src/gui_srv.zig --name gui_srv --cache-dir .zig-cache -lvulkan -lX11 -fPIC

http_client: src/*.zig
	zig build-exe src/http_client.zig --name http_client --cache-dir .zig-cache

tls_client: src/*.zig
	zig build-exe src/tls_client.zig --name tls_client --cache-dir .zig-cache

release: src/*.zig
	zig build-exe src/main.zig --name dhjsjs --cache-dir .zig-cache -Doptimize=ReleaseSafe
	strip dhjsjs
	zig build-exe src/cli.zig --name dhjsjs_cc --cache-dir .zig-cache -Doptimize=ReleaseSafe -lvulkan -lX11 -fPIC
	strip dhjsjs_cc
	zig build-exe src/media_player.zig --name media_player --cache-dir .zig-cache -Doptimize=ReleaseSafe
	strip media_player
	zig build-exe src/desktop_gui.zig --name desktop_gui --cache-dir .zig-cache -Doptimize=ReleaseSafe
	strip desktop_gui
	zig build-exe src/gui_srv.zig --name gui_srv --cache-dir .zig-cache -Doptimize=ReleaseSafe -lvulkan -lX11 -fPIC
	strip gui_srv
	zig build-exe src/http_client.zig --name http_client --cache-dir .zig-cache -Doptimize=ReleaseSafe
	strip http_client
	zig build-exe src/tls_client.zig --name tls_client --cache-dir .zig-cache -Doptimize=ReleaseSafe
	strip tls_client

run: dhjsjs
	./dhjsjs

run-player: media_player
	./media_player

run-desktop: desktop_gui
	./desktop_gui

run-gui: gui_srv
	./gui_srv

clean:
	rm -rf dhjsjs dhjsjs_cc media_player desktop_gui gui_srv http_client tls_client .zig-cache zig-out output

.PHONY: all release run run-player clean

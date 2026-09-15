#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
source_root="$repo_root/src"; patch_root="$repo_root/patches"; build_root="$repo_root/build"; work_root="$build_root/work"; cache_root="$build_root/cache"; tools_root="$build_root/tools"; output_root="$repo_root/output"
target=all; clean=false; check=false; download=false; zig="${ZIG:-}"
zig_version=0.14.1; zig_archive="$tools_root/zig-x86_64-linux-0.14.1.tar.xz"; zig_install="$tools_root/zig-x86_64-linux-0.14.1/zig"; zig_url='https://ziglang.org/download/0.14.1/zig-x86_64-linux-0.14.1.tar.xz'; zig_sha256='24aeeec8af16c381934a6cd7d95c807a8cb2cf7df9fa40d359aa884195c4716c'

usage() { printf '%s\n' '用法：build.sh [--target windows-amd64|linux-amd64|all] [--zig /path/to/zig] [--check] [--clean] [--download-toolchain]'; }
while [[ $# -gt 0 ]]; do case "$1" in --target) target="$2"; shift 2;; --zig) zig="$2"; shift 2;; --check) check=true; shift;; --clean) clean=true; shift;; --download-toolchain) download=true; shift;; -h|--help) usage; exit 0;; *) usage >&2; exit 2;; esac; done
case "$target" in windows-amd64|linux-amd64|all) ;; *) echo '仅支持 windows-amd64、linux-amd64 或 all。' >&2; exit 2;; esac
assert_layout() { [[ -f "$source_root/COPYING" && -f "$source_root/udp-sender.c" && -f "$source_root/udp-receiver.c" && -f "$patch_root/0001-windows-amd64-types.patch" ]] || { echo '缺少锁定 UDPcast 源码或补丁。' >&2; exit 2; }; }
assert_safe_delete() { local path="$1"; case "$path" in "$work_root"|"$work_root"/*|"$cache_root"|"$cache_root"/*|"$output_root"|"$output_root"/*) ;; *) echo "拒绝删除非构建路径：$path" >&2; exit 2;; esac; [[ ! -L "$path" ]] || { echo "拒绝删除符号链接：$path" >&2; exit 2; }; }
clean_local() { local path; for path in "$work_root" "$cache_root" "$output_root"; do if [[ -e "$path" || -L "$path" ]]; then assert_safe_delete "$path"; find "$path" -type l -print -quit | grep -q . && { echo "拒绝删除包含符号链接的路径：$path" >&2; exit 2; }; rm -rf -- "$path"; fi; done; }
resolve_zig() { if [[ -z "$zig" ]]; then if [[ ! -x "$zig_install" ]]; then if ! $download; then echo '缺少固定 Zig 0.14.1；传 --zig 或显式 --download-toolchain。' >&2; exit 2; fi; mkdir -p "$tools_root"; curl --fail --location --proto '=https' --tlsv1.2 "$zig_url" -o "$zig_archive"; echo "$zig_sha256  $zig_archive" | sha256sum -c -; tar -C "$tools_root" -xf "$zig_archive"; fi; zig="$zig_install"; fi; [[ -x "$zig" ]] || { echo "Zig 不可执行：$zig" >&2; exit 2; }; [[ "$("$zig" version)" == "$zig_version" ]] || { echo "需要 Zig $zig_version。" >&2; exit 2; }; }
new_work() { local name="$1" work="$work_root/$name"; assert_safe_delete "$work"; if [[ -e "$work" || -L "$work" ]]; then rm -rf -- "$work"; fi; mkdir -p "$work"; cp -R "$source_root/." "$work/"; local patch_file; for patch_file in "$patch_root"/*.patch; do [[ -e "$patch_file" ]] || continue; patch -d "$work" -p1 < "$patch_file"; done; printf '%s' "$work"; }
compile() { local name="$1" zig_target="$2" host="$3" extension="$4" links="$5" work out; work=$(new_work "$name"); out="$output_root/$name"; mkdir -p "$out" "$cache_root/zig-global" "$cache_root/zig-local"; export ZIG_GLOBAL_CACHE_DIR="$cache_root/zig-global" ZIG_LOCAL_CACHE_DIR="$cache_root/zig-local"; ( cd "$work"; CC="$zig cc -target $zig_target" CFLAGS='-O2 -Wall -D_FILE_OFFSET_BITS=64' sh ./configure --host="$host" ); local sender=(udp-sender.c socklib.c udpcast.c strparse.c rateGovernor.c rate-limit.c auto-rate.c sender-diskio.c senddata.c udps-negotiate.c fifo.c produconsum.c participants.c log.c statistics.c fec.c udpc_version.c console.c process.c); local receiver=(udp-receiver.c socklib.c udpcast.c strparse.c receiver-diskio.c receivedata.c udpr-negotiate.c produconsum.c fifo.c log.c statistics.c fec.c udpc_version.c console.c process.c); (cd "$work"; "$zig" cc -target "$zig_target" -O2 -g0 -s -Wall -DNO_BB -D_FILE_OFFSET_BITS=64 -I. "${sender[@]}" $links -o "$out/udp-sender$extension"; "$zig" cc -target "$zig_target" -O2 -g0 -s -Wall -DNO_BB -D_FILE_OFFSET_BITS=64 -I. "${receiver[@]}" $links -o "$out/udp-receiver$extension"); printf '已生成 %s\n' "$out"; }

assert_layout
if $clean; then clean_local; exit 0; fi
resolve_zig
if $check; then printf '%s\n' '检查通过：锁定源码、补丁与 Zig 0.14.1 已就绪。'; exit 0; fi
[[ "$target" == windows-amd64 || "$target" == all ]] && compile windows-amd64 x86_64-windows-gnu x86_64-w64-mingw32 .exe '-lws2_32 -liphlpapi'
[[ "$target" == linux-amd64 || "$target" == all ]] && compile linux-amd64 x86_64-linux-musl x86_64-linux-musl '' '-pthread'

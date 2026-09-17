# RootPXE Multicast

本仓库独立维护 RootPXE 所使用的 UDPcast 20250223 源码、下游补丁和可复现构建。RootPXE 主仓库不再携带 UDPcast 源码或编译工具；它只消费从本仓库构建或 Release 下载后放入 `assets/multicast/<target>/udp-sender` 的发送端二进制。

## 目录

```text
src/                 锁定的 UDPcast 20250223 原始源码
patches/             仅在忽略的工作副本上应用的下游补丁
tests/               结构、二进制和本机流测试
build.ps1 build.sh   Windows/Linux 构建入口
build/               忽略：工具链、工作副本和缓存
output/              忽略：构建产物
```

`src/` 保持上游解压后的原始内容。版本、上游地址、源码 SHA-256 和 Zig 固定版本见 [upstream.lock.json](upstream.lock.json)。`patches/` 不会改写 `src/`，每次构建先复制源码再按文件名顺序应用补丁。

## 本地构建

只支持 Windows amd64 和 Linux amd64，两个目标都生成发送端和接收端：

```powershell
./build.ps1 -Target all
./build.ps1 -Check
./build.ps1 -Clean
```

```sh
./build.sh --target all --zig /opt/zig-0.14.1/zig
./build.sh --check --zig /opt/zig-0.14.1/zig
./build.sh --clean
```

首次准备工具链可显式传入 `-DownloadToolchain` 或 `--download-toolchain`。下载地址与 SHA-256 被锁定在脚本和 lock 文件中；普通构建不会联网下载。Windows 构建还需要 Git for Windows 提供的 `bash` 和 `patch`。

输出固定为：

```text
output/windows-amd64/udp-sender.exe
output/windows-amd64/udp-receiver.exe
output/linux-amd64/udp-sender
output/linux-amd64/udp-receiver
```

将需要的 `udp-sender` 拷入 RootPXE 主仓库的被忽略本地路径 `assets/multicast/<target>/` 后，再运行 RootPXE 的普通构建。接收端由 PXEOS 使用；RootPXE 服务端不释放或调用 `udp-receiver`。

Release 的 Linux 包用于提供原始二进制，Windows runner 制作 ZIP 不承诺保留 POSIX 执行位。RootPXE 在 Linux 首次将内嵌 sender 释放到 `data/multicast/udp-sender` 时会明确设为可执行；因此交给 RootPXE 嵌入前无需依赖压缩包的模式位。

本仓库的 Windows/Linux amd64 目标仅描述 RootPXE 服务端 sender。PXEOS 的 receiver 与其 x86、x64、arm64 产物一同构建；不要将本仓库输出范围误写为 PXEOS 架构限制。RootPXE 的手动会话、存储和网络边界见主仓库 `docs/multicast.md`。

## 验证

```powershell
node --test tests/*.test.mjs
./tests/Test-UdpcastPackage.ps1 -Target WindowsAmd64 -RequireBinary
./tests/Test-UdpcastPackage.ps1 -Target LinuxAmd64 -RequireBinary
./tests/Test-UdpcastNetwork.ps1 -RunLocalStream
```

本机流测试仅验证 Windows 二进制的标准输入/输出和 UDPcast 协商，不代表跨主机、跨平台或真实网络多播验收。

## GitHub Actions

每次推送 `main`、Pull Request 和手动触发都会构建两个 amd64 目标、校验 PE/ELF 架构，并上传可下载的构建产物。`v*` tag 在同样验证通过后额外创建 GitHub Release，发布 Windows 和 Linux 压缩包及对应 SHA-256。工作流从 lock 文件固定的 Zig 0.14.1 下载并校验哈希；不会发布未验证的二进制。

## 许可证

UDPcast 主要采用 GPL-2.0-only；`fec.c` 的 BSD-like 条款见 [src/COPYING](src/COPYING)。本仓库顶层 [LICENSE](LICENSE) 为上游许可证副本。

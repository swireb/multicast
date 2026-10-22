## RootPXE Multicast

- 本仓库独立维护 RootPXE 所使用的 UDPcast 20250223 源码、下游补丁和可复现构建。RootPXE 主仓库不再携带 UDPcast 源码或编译工具；它只消费从本仓库构建或 Release 下载后放入资源目录的发送端二进制。

```text
# RootPXE 主仓库中的发送端输入
assets/multicast/<target>/udp-sender
```

## 目录

- 源码、下游补丁、测试、构建入口及忽略的本地输出按以下目录组织。

```text
# 锁定的 UDPcast 20250223 原始源码
src/
# 仅在忽略的工作副本上应用的下游补丁
patches/
# 结构、二进制和本机流测试
tests/
# Windows/Linux 构建入口
build.ps1
build.sh
# 忽略：工具链、工作副本和缓存
build/
# 忽略：构建产物
output/
```

- 原始源码目录保持上游解压后的内容。版本、上游地址、源码 SHA-256 和 Zig 固定版本见[上游锁文件](upstream.lock.json)。补丁不会改写原始源码，每次构建先复制源码再按文件名顺序应用补丁。

## 本地构建

- 只支持 Windows amd64 和 Linux amd64，两个目标都生成发送端和接收端。

```powershell
./build.ps1 -Target all
./build.ps1 -Check
./build.ps1 -Clean
```

```shell
./build.sh --target all --zig /opt/zig-0.14.1/zig
./build.sh --check --zig /opt/zig-0.14.1/zig
./build.sh --clean
```

- 首次准备工具链可显式传入下载参数。下载地址与 SHA-256 被锁定在脚本和 lock 文件中；普通构建不会联网下载。Windows 构建还需要 Git for Windows 提供的 Bash 和 patch 工具。

```text
# Windows 构建所需的 Git for Windows 工具
bash
patch
# 首次显式下载工具链的参数
-DownloadToolchain     # Windows 显式下载工具链
--download-toolchain  # Linux 显式下载工具链
```

- 输出固定为以下四个文件。

```text
# Windows amd64
output/windows-amd64/udp-sender.exe
output/windows-amd64/udp-receiver.exe
# Linux amd64
output/linux-amd64/udp-sender
output/linux-amd64/udp-receiver
```

- 将需要的发送端拷入 RootPXE 主仓库的版本化资源路径后，再运行 RootPXE 的普通构建。接收端由 PXEOS 使用；RootPXE 服务端不释放或调用接收端。

```text
# RootPXE 主仓库中的资源路径
assets/multicast/<target>/
# 发送端名称
udp-sender
udp-sender.exe
# 接收端名称
udp-receiver
udp-receiver.exe
```

- Release 的 Linux 包用于提供原始二进制，Windows runner 制作 ZIP 不承诺保留 POSIX 执行位。RootPXE 在 Linux 首次将内嵌 sender 释放到运行目录时会明确设为可执行；因此交给 RootPXE 嵌入前无需依赖压缩包的模式位。

```text
# Linux 发送端运行路径
data/multicast/udp-sender
```

- 本仓库的 Windows/Linux amd64 目标仅描述 RootPXE 服务端 sender。PXEOS 的 receiver 与其 x86、x64、arm64 产物一同构建；不要将本仓库输出范围误写为 PXEOS 架构限制。RootPXE 的手动会话、存储和网络边界见[主仓库多播说明](../../docs/multicast.md)。

## 验证

- 验证命令如下。

```powershell
node --test tests/*.test.mjs
./tests/Test-UdpcastPackage.ps1 -Target WindowsAmd64 -RequireBinary
./tests/Test-UdpcastPackage.ps1 -Target LinuxAmd64 -RequireBinary
./tests/Test-UdpcastNetwork.ps1 -RunLocalStream
```

- 本机流测试仅验证 Windows 二进制的标准输入/输出和 UDPcast 协商，不代表跨主机、跨平台或真实网络多播验收。

## GitHub Actions

- 每次推送主分支、Pull Request 和手动触发都会构建两个 amd64 目标、校验 PE/ELF 架构，并上传可下载的构建产物。版本 tag 在同样验证通过后额外创建 GitHub Release，发布 Windows 和 Linux 压缩包及对应 SHA-256。工作流从 lock 文件固定的 Zig 0.14.1 下载并校验哈希；不会发布未验证的二进制。

```text
# 主分支
main
# 发布 tag 匹配规则
v*
```

## 许可证

- UDPcast 主要采用 GPL-2.0-only；FEC 源码的 BSD-like 条款见[上游许可证](src/COPYING)。本仓库顶层[许可证](LICENSE)为上游许可证副本。

```text
# 采用 BSD-like 条款的源码
fec.c
```

# 下游补丁

构建脚本只会把 `patches/*.patch` 应用于忽略的 `work/` 副本，绝不修改 `src/udpcast-20250223` 中的上游原始源码。

`0001-windows-amd64-types.patch` 修复 x86_64 Windows 构建中的两处类型问题：FIFO 缓冲区对齐不再把指针截断为 32 位 `unsigned long`，日志时间戳不再把 `long` 传给要求 `time_t *` 的 `localtime`。该补丁已随 Windows amd64 构建和同机二进制流测试验证。

若后续必须加入兼容性修复，每个补丁都应说明其上游问题、适用目标和回归验证，并以 `patch -p1` 可重放的统一 diff 形式保存。

## 下游补丁

- 构建脚本只会把补丁应用于忽略的工作副本，绝不修改上游原始源码。

```text
# 补丁匹配规则
patches/*.patch
# 忽略的工作副本
work/
# 上游原始源码
src/udpcast-20250223
```

- Windows amd64 补丁修复 x86_64 Windows 构建中的两处类型问题：FIFO 缓冲区对齐不再把指针截断为 32 位整数，日志时间戳不再把错误类型传给本地时间函数。该补丁已随 Windows amd64 构建和同机二进制流测试验证。

```text
# 补丁文件
0001-windows-amd64-types.patch
# FIFO 原指针截断类型
unsigned long
# 日志时间戳原参数类型、目标参数类型与函数
long
time_t *
localtime
```

- 若后续必须加入兼容性修复，每个补丁都应说明其上游问题、适用目标和回归验证，并以可重放的统一 diff 形式保存。

```shell
patch -p1
```

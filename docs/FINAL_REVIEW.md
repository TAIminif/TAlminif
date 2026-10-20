# MoonC3D 最终验收复现指南

MoonC3D 已通过十月黑客松报名初审。本页对应 `0.2.1` 的代码、证据和复现方法，供审核者检查工程完成情况；最终验收结果由组委会认定。

## 官方要求与当前交付

本届来源为[十月黑客松官网](https://moonbitlang.github.io/Hackathon2026/)、[官方 GitHub 网站源码](https://github.com/moonbitlang/Hackathon2026/blob/main/src/App.tsx)及其所链[正式章程](https://bxup9uklfcb.feishu.cn/wiki/Dx4Bwd6D1i3GfHkajQCcF7SznEd)。官网明确本期报名与验收截止为 **2026 年 10 月 31 日**；章程仍有旧月份文字，具体执行及提交通道以组委会本期通知为准。

| 正式验收要求 | 本项目实现或证据 | 状态 |
| --- | --- | --- |
| MoonBit 为主要实现语言；完成申报核心功能 | `lib/` 原生编解码、校准、同步编辑；[兼容清单](COMPATIBILITY.md)逐项定义终点 | 已实现；按下方命令复现 |
| 公开 GitHub 仓库、清晰且真实的开发记录 | [公开仓库](https://github.com/TAIminif/TAlminif)、提交历史、[CHANGELOG](../CHANGELOG.md) | 已具备；保留历史，不制造提交 |
| 可复现 README、安装及使用说明 | [README](../README.md)、本页、独立源码使用方示例 | 已具备 |
| 至少一个可运行示例 | `moon run examples/memory`、下方三个文件处理场景 | 已具备 |
| CI 覆盖检查、构建、测试 | [工作流](../.github/workflows/ci.yml)、[GitHub Actions](https://github.com/TAIminif/TAlminif/actions/workflows/ci.yml) | 以所交付提交对应的实际运行结果为准 |
| 测试覆盖核心功能 | 82 项 MoonBit 核心测试；文件双向对照、跨编码及多通道案例 | 已有通过记录；本次复现生成新报告 |
| OSI 开源许可、来源及上游合规 | [MIT LICENSE](../LICENSE)、[第三方来源说明](../THIRD_PARTY_NOTICES.md) | 已具备；测试数据不随 MIT 源码再分发 |
| 发布到 Mooncakes | 当前仅提供 GitHub 源码及 `moon.work` 跨模块使用方式 | **待发布或取得组委会豁免**；尚未执行发布 |
| 成果由参赛者理解并负责 | [设计与边界](DESIGN.md)、独立验证、可追溯开发记录 | 需参赛者本人解释技术选择及实际贡献 |

初审通过不等于终验通过。参赛者已收到终验通知，将按该通知自行提交；本文不代交材料，也不将公开网页未列出的专用入口、视频或 PPT 要求推断为新增统一门槛。

## 验证范围与计数

[最新工程验证摘要](VERIFICATION-20261020.json)记录干净源码副本的完整检查、独立回归、外部模块消费及本地包检查；[VERIFICATION-20261016.json](VERIFICATION-20261016.json)保留此前验证快照。重新运行生成新报告，不覆盖历史记录，不将不同类型计数相加充当测试总数。

| 独立计数 | 范围及判据 |
| --- | --- |
| 82 项核心测试 | 每个后端执行同一套测试，不能把四后端结果写成328个不同测试；覆盖编码、校准、事件、编辑、限额和错误路径 |
| 5233 行生产 MoonBit | `scripts/count_code.py` 的非空、非纯注释物理行；生成接口及依赖排除，测试、示例单列；用于说明规模，不代表赛事认可的有效贡献量 |
| 21 个兼容案例 | 9 个511点/511模拟通道、每通道每帧3子采样的合成案例，10个未经修改的有效官方原件，2个明确修正的副本 |
| 54 个转码输出 | 21案例套件中另外独立解码的目标编码文件：18个合成输出、36个官方样本输出 |
| 48 个新增回归配置 | `scripts/review_regressions.py`：36个小数率配置及12个半开时间裁剪配置；与21案例、54输出分别统计，实际通过数见本次 `report.json` |
| 独立模块消费验证 | `scripts/verify_consumer.py` 在新模块中仅导入公开库 API，三编码验证59.94 Hz、3子采样、时间与索引往返及裁剪；不需要注册表登录 |

四后端、小数率物理值回归和独立模块消费验证是本项目提供的额外工程保障，未将其描述为本届统一的数量门槛。新增脚本随工作流运行；新提交是否通过应检查其对应 Actions 结果，不能用旧提交的成功记录代替。

小数率回归覆盖 `59.94/29.97/23.976 Hz × 3/10子采样 × 三编码 × 两种存储`。时间裁剪回归在100 Hz下精确检查 `[0.07,0.09)` 对应原索引 `[7,8]`，以及 `[0,0.07)` 对应 `[0,1,2,3,4,5,6]`；检查校准物理值、标签、单位、事件和同步关系。独立 Python 字节解码器及预定义公式作为数值依据，不使用 MoonC3D 自己的 JSON 输出充当正确性证明。

## 从干净克隆复现

需要 MoonBit 工具链、Node.js 22+、Python 3.11+；native 测试另外需要本机 C 编译器。历史基线为 `moon 0.1.20261012` / `moonc v0.10.15+943464bfa`，CI 会记录实际安装的官方稳定版。Python 对照依赖固定在 [requirements-test.txt](../requirements-test.txt)，核心库自身不依赖 Python 或外部 C3D 实现。完整官方样本验证需要网络下载；已缓存且哈希匹配时复用缓存。

### Windows PowerShell

```powershell
git clone https://github.com/TAIminif/TAlminif.git
Set-Location TAlminif
py -3.11 -m venv .tools/review-venv
$reviewPython = (Resolve-Path .tools/review-venv/Scripts/python.exe).Path
& $reviewPython -m pip install -r requirements-test.txt
pwsh -File scripts/verify.ps1 -Python $reviewPython
```

`verify.ps1` 运行格式检查、检查/构建、wasm-gc/wasm/js 核心测试、内存示例、独立对照、官方样本兼容、新增48配置回归、独立模块消费和代码统计；存在仓库本地隔离工具链时自动使用。已配置 C 编译器时增加 `-Native` 运行 native 测试，CI 同样覆盖 native。

### Linux / macOS

以下命令从克隆后的仓库根目录运行，Python 虚拟环境路径按 POSIX 系统使用。native 行需要 C 编译器；缺少时应记录环境限制，并核对对应提交的 native CI 结果。

```sh
python3.11 -m venv .tools/review-venv
. .tools/review-venv/bin/activate
python -m pip install -r requirements-test.txt
moon version
moonc -v
moon fmt --check
moon check --deny-warn
moon check --target js --deny-warn
moon build
moon test --target wasm-gc
moon test --target wasm
moon test --target js
moon test --target native
moon run examples/memory
moon build --target js --release
python scripts/interop.py
python scripts/compatibility_cases.py --download-official
python scripts/review_regressions.py
python scripts/verify_consumer.py --target js
python scripts/count_code.py > artifacts/code-count.json
moon package --list > artifacts/package-manifest.txt
moon package
python scripts/check_package.py
```

脚本失败应返回非0退出码，不能只检查“是否生成了文件”。Python 独立验证不要加 `-O`，否则会关闭解码器使用的断言。`--skip-official` 只运行合成兼容案例，报告会标注缩减范围，不能代替完整官方样本验证。

### 报告与证据位置

| 输出 | 内容 |
| --- | --- |
| `artifacts/interop-*/result.json` | 固定版本 py-c3d 双向对照、编辑、统计、CSV及异常退出核对 |
| `artifacts/compatibility-*/report.json` | 21案例、54转码输出、原件/修正副本及哈希、数据对照 |
| `artifacts/review-regressions-*/report.json` | 新增48配置的实际通过数、失败项、文件哈希及独立数值核对 |
| `artifacts/source-consumer-*/result.json` | 独立模块检查及运行命令、退出码和三编码成功输出 |
| `artifacts/code-count.json` | 本次生产、测试、示例代码统计 |
| `artifacts/package-manifest.txt`、`_build/publish/*.zip` | 本地打包清单与源码包；打包不等于已发布注册表 |
| `artifacts/package-check.json` | 源码包必需文件、CRC、SHA-256及本机目录排除检查；`--list` 后须实际执行 `moon package` |
| Actions 中的 `c3d-verification` 附件 | 工作流上传的上述报告；在对应提交的运行页面下载 |

每次运行会新建目录，脚本最后打印具体报告路径。`artifacts/` 和官方样本缓存 `.tools/compatibility/` 被 Git 忽略；审核者运行命令后取得完整产物，仓库不重新分发外部实验数据。

## 三个可核对使用场景

下面命令适用于 Windows PowerShell 和 POSIX shell，从仓库根目录运行。首次使用 `artifacts/final-demo`，已存在时另换目录名；CLI 不覆盖已有文件。

```sh
node -e "require('node:fs').mkdirSync('artifacts/final-demo', {recursive: true})"
node bin/moonc3d.mjs demo artifacts/final-demo/trial.c3d
node bin/moonc3d.mjs inspect artifacts/final-demo/trial.c3d
node bin/moonc3d.mjs check artifacts/final-demo/trial.c3d
node bin/moonc3d.mjs stats artifacts/final-demo/trial.c3d
```

**实验数据质量检查：**输入示例试验，`inspect` 应报告20帧、两个标记点、两个模拟通道；`stats` 中 RightHeel 缺失3个样本、最长连续缺失3帧，每个模拟通道有40个样本。`check` 输出结构化诊断供接收人员复核。

```sh
node bin/moonc3d.mjs crop artifacts/final-demo/trial.c3d artifacts/final-demo/clip.c3d 5 15
node bin/moonc3d.mjs select-points artifacts/final-demo/clip.c3d artifacts/final-demo/heel.c3d 0
node bin/moonc3d.mjs csv artifacts/final-demo/heel.c3d artifacts/final-demo/heel.csv points
node bin/moonc3d.mjs csv artifacts/final-demo/clip.c3d artifacts/final-demo/analog.csv analog
node bin/moonc3d.mjs csv artifacts/final-demo/clip.c3d artifacts/final-demo/events.csv events
```

**同步动作片段提取：**原索引半开区间 `[5,15)` 生成10帧、每模拟通道20个样本；新帧号从1开始，区间内事件减去片段起点。CSV保留校准物理值与子采样时间，缺失点坐标留空。新增回归脚本另核对小数时间边界选帧，避免用四舍五入掩盖漏帧。

```sh
node bin/moonc3d.mjs dump artifacts/final-demo/trial.c3d artifacts/final-demo/trial.json
node bin/moonc3d.mjs pack artifacts/final-demo/trial.json artifacts/final-demo/repacked.c3d
node bin/moonc3d.mjs convert artifacts/final-demo/repacked.c3d artifacts/final-demo/integer.c3d 0.01
node bin/moonc3d.mjs convert-encoding artifacts/final-demo/integer.c3d artifacts/final-demo/vax.c3d dec
node bin/moonc3d.mjs convert-encoding artifacts/final-demo/vax.c3d artifacts/final-demo/mips.c3d mips
node bin/moonc3d.mjs check artifacts/final-demo/mips.c3d
```

**跨工具交换：**JSON往返、整数存储及Intel→DEC/VAX→SGI/MIPS转换得到可检查文件。整数转换按比例量化，不能要求字节相同或无限精度；独立对照脚本按可表示精度核对物理值与元数据。CLI成功退出码为0，格式/参数错误为1，文件或构建错误为2。

## 已知样本缺陷与兼容边界

- 官方 Sample01 的六种表示直接对照。Sample02 的两个 SGI/MIPS 原件在偏移5429处包含错误的末尾记录跳转，应得到结构化 `invalid`；仅名含 `-repaired` 的本地副本将 `3f01` 修正为 `013f` 后继续验证，报告保留原件缺陷及前后哈希。**这两份不能描述为未经修改原件通过。**
- 511通道、分段校准和部分小数率配置使用独立字节解码器；py-c3d 0.6.0 的分段数组与精确比率限制使它不能独自担任这些配置的数值依据。其适用的官方样本和双向对照继续保留。
- 兼容终点为标准点、同步模拟信号、参数与事件交换；范围及限额见 [COMPATIBILITY](COMPATIBILITY.md) 和 [DESIGN](DESIGN.md)。不实现力平台动力学求解或厂商私有语义推断；有有效力平台引用时拒绝模拟通道选择，避免误改引用。未知厂商通道引用不自动重映射，规范化写出不保证逐字节一致。

## 最终提交前

核对最终公开提交的 Actions、报告与上述功能范围一致，并完成 Mooncakes 发布或取得组委会明确豁免。参赛者按已收到的终验通知自行提交，保留报名初审通过通知与提交成功凭证；本文不代交。不要将工程准备完成写成已通过组委会最终验收。

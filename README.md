# TAlminif — MoonC3D

[![CI](https://github.com/TAIminif/TAlminif/actions/workflows/ci.yml/badge.svg)](https://github.com/TAIminif/TAlminif/actions/workflows/ci.yml)

MoonC3D 是用 MoonBit 编写的 C3D 动作捕捉文件工具库。它将三维标记点、不同采样率的模拟信号和事件放在同一时间轴上，支持文件交换、质量检查和同步编辑。

模块名：`TAIminif/TAlminif`；库包：`TAIminif/TAlminif/lib`；许可证：[MIT](LICENSE)。仓库名中第三个字符是小写 `l`。

## 支持范围

| 功能 | 0.2.0 范围 |
| --- | --- |
| 二进制文件 | Intel/IEEE、DEC/VAX、SGI/MIPS 三种编码，512 字节块，int16 或 float32 点存储 |
| 标记点 | XYZ、残差、7 位相机掩码、缺失点；支持 LABELS/LABELS2/LABELS3 等连续分段 |
| 模拟信号 | 每帧多个子采样，偏移、每通道比例和总比例校准；有符号/无符号整数及浮点存储 |
| 元数据 | 参数组、锁定标记、说明、最多7维数组；数值按处理器转码，字符/字节载荷保留 |
| 事件 | EVENT 参数和传统2/4字符头部事件读取与合并；写出统一采用 EVENT |
| 访问 | 顺序、批次、随机帧读取；每帧处理的在线统计 |
| 编辑 | 按帧/时间裁剪，同步保留模拟量和区间内事件；选择/重排通道、改名、转换存储 |
| 交换 | `MoonC3D/1` JSON 双向交换，点/模拟量/事件 CSV 导出 |
| 检查 | 文件界限、计数、采样率、比例、帧布局；缺失段、重复标签及事件区间诊断 |

容量：点和模拟通道计数各受 uint16 限制，每帧模拟样本数也不得超过65535；参数区最多255个512字节块，实际可容纳通道数还取决于元数据大小。标准通道字段每段最多255项，最后一段允许预留容量；缺少的可选文本用默认值补齐，数值校准不能缺项。

边界：不进行力平台到力/力矩的推导计算。存在使用中的 FORCE_PLATFORM 时，模拟通道选择报错，避免改变其通道引用。未知厂商参数的结构、锁定状态和说明被保留；数值载荷跨编码时会转码，但不会自动重映射其中的通道引用。编辑后文件规范化写出，不保证逐字节相同。

## 安装与运行

安装 [MoonBit 工具链](https://www.moonbitlang.cn/download/)。文件 CLI 需要 Node.js 22 或更新版本，独立对照脚本使用 Python 3.11，核心库无需 Node、Python 或外部 C3D 库。使用 `moon 0.1.20261012` / `moonc v0.10.15+943464bfa` 或兼容更新版本；CI 安装官方当前稳定工具链并记录实际版本。

```sh
git clone https://github.com/TAIminif/TAlminif.git
cd TAlminif
moon check
moon build
moon test
moon run examples/memory
```

发布后，依赖本库的项目执行 `moon add TAIminif/TAlminif`，并在 `moon.pkg` 中配置：

```text
import {
  "TAIminif/TAlminif/lib" @c3d,
}
```

## 三个可复现使用流程

命令从仓库根目录运行，每个输出路径必须是新路径，CLI 不覆盖已有文件。

### 1. 检查实验数据质量

```sh
mkdir artifacts
node bin/moonc3d.mjs demo artifacts/trial.c3d
node bin/moonc3d.mjs inspect artifacts/trial.c3d
node bin/moonc3d.mjs check artifacts/trial.c3d
node bin/moonc3d.mjs stats artifacts/trial.c3d
```

示例包含20帧、两个标记点、两个模拟通道及事件。RightHeel 有3个缺失样本，最长连续缺失段为3帧；每个模拟通道有40个样本。`check` 的结构化诊断可接入实验数据接收流程。

### 2. 提取动作片段，同时保留信号同步

```sh
node bin/moonc3d.mjs crop artifacts/trial.c3d artifacts/clip.c3d 5 15
node bin/moonc3d.mjs select-points artifacts/clip.c3d artifacts/heel.c3d 0
node bin/moonc3d.mjs csv artifacts/heel.c3d artifacts/heel.csv points
node bin/moonc3d.mjs csv artifacts/clip.c3d artifacts/force.csv analog
node bin/moonc3d.mjs csv artifacts/clip.c3d artifacts/events.csv events
```

裁剪采用从0开始的半开帧索引 `[5,15)`。输出10帧、每通道20个模拟样本，帧号从1开始，区间内事件时间减去片段起点。CSV 使用校准物理值和实际子采样时间，缺失点坐标留空。

### 3. 在工具之间交换及转换存储

```sh
node bin/moonc3d.mjs dump artifacts/trial.c3d artifacts/trial.json
node bin/moonc3d.mjs pack artifacts/trial.json artifacts/repacked.c3d
node bin/moonc3d.mjs convert artifacts/repacked.c3d artifacts/integer.c3d 0.01
node bin/moonc3d.mjs check artifacts/integer.c3d
node bin/moonc3d.mjs convert-encoding artifacts/integer.c3d artifacts/vax.c3d dec
node bin/moonc3d.mjs convert-encoding artifacts/vax.c3d artifacts/mips.c3d mips
```

JSON 包含语义数据和原始参数载荷，可编辑后重新生成 C3D。正比例使用 int16 坐标，负比例使用 float32。整数转换会量化；超出坐标、残差或模拟量可表示范围时返回错误。

`node bin/moonc3d.mjs help` 列出全部命令。输出为 JSON，成功退出码0，格式/参数错误为1，文件或构建错误为2。批处理可在执行 `moon build --target js --release` 后设置 `MOONC3D_NO_BUILD=1` 复用 JS 产物。

## 库示例

完整可运行示例：[examples/memory/main.mbt](examples/memory/main.mbt)。

```moonbit
let frames : Array[@c3d.Frame] = [
  { number: 1, points: [@c3d.Marker::new(1.0, 2.0, 3.0)], analog: [] },
  { number: 2, points: [@c3d.Marker::new(2.0, 3.0, 4.0)], analog: [] },
]
let document = @c3d.Document::new(["Heel"], [], frames)
let reader = @c3d.Reader::new(@c3d.write(document))
let second = reader.frame(1)
let report = @c3d.check(reader)
let statistics = @c3d.analyze(reader)
```

失败操作抛出 `@c3d.C3dError`，用 `.kind()` / `.message()` 获取诊断。`Frame.analog` 外层是通道，内层是该帧子采样；库中的模拟量均为校准后的物理值。用户文本用 UTF-8，参数标识符用 ASCII 字母、数字或下划线。

`@c3d.write(document, processor=@c3d.Dec)` 或 `@c3d.Mips` 可指定目标编码；默认保留来源编码。参数独立文件使用 `read_parameter_file` / `write_parameter_file`，不通过三维帧接口读取。

在本工作区，旧的系统工具链保持原样，新版安装在 `.tools/moon-20261012`。CLI 自动使用存在的隔离工具链，也可通过 `MOONC3D_MOON_HOME` 指定其他目录。Windows 运行 `pwsh -File scripts/verify.ps1` 可复现全部本地验证；有多个 Python 时加 `-Python <Python3.11路径>`，已有本机 C 编译器时可加 `-Native`。隔离工具链和依赖不会发布到仓库或库包。

编码矩阵、案例和兼容终点见 [COMPATIBILITY.md](docs/COMPATIBILITY.md)，语义和上限见 [DESIGN.md](docs/DESIGN.md)。公共 API 可运行 `moon info` 查看 [lib/pkg.generated.mbti](lib/pkg.generated.mbti)。

## 验证与来源

```sh
moon test --target wasm-gc
moon test --target wasm
moon test --target js
python -m pip install -r requirements-test.txt
python scripts/interop.py
python scripts/compatibility_cases.py
python scripts/count_code.py
```

独立脚本用 `py-c3d 0.6.0` 生成整数和浮点试验，双向比较点数据、残差、相机掩码、通道校准、元数据、裁剪/选择/转换结果，检查统计值、CSV 时间及错误退出。跨编码脚本另下载并校验官方 Sample01、Sample02 的 SHA-256，逐帧对照12个原始文件及各目标编码写出结果；合成511点/511模拟通道案例独立核对文件字节、校准值和跨分段编辑。报告与合成数据留在被 Git 忽略的 `artifacts/`，官方数据留在 `.tools/compatibility/`，不随 MIT 源码重新分发。Python 只用于验证。

实现依据 [C3D 官方指南](https://www.c3d.org/docs/C3D_User_Guide.pdf)，独立编写 MoonBit 实现；[py-c3d](https://github.com/EmbodiedCognition/py-c3d) 仅为外部对照工具，未复制其源码。来源许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，生态查重范围见 [UNIQUENESS.md](docs/UNIQUENESS.md)。

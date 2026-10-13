# 公开生态查重记录

核查时间：2026-10-13，MoonC3D 实现推送前。结果是在所查公开索引中未发现直接实现 C3D 参数、点和模拟通道读写的 MoonBit 库；不能保证未索引、私有或使用不同术语的项目不存在。

## 检索

- [Mooncakes 全部模块元数据](https://mooncakes.io/api/v0/modules)：2955条。响应 UTF-8 SHA-256：`43f86e9ed75ef3ae5d0f89d84c2444f68fbd8b5c4185f48593f36897062a3d12`。扫描 C3D / mocap / motion capture / BVH 及近邻术语。
- Mooncakes 定向搜索 `c3d`、`motion-capture`、`mocap`、`bvh`。C3D 未匹配；动作捕捉近邻为 MoonBVHKit，另有光追空间索引类 BVH。
- [GitHub 官方仓库搜索](https://docs.github.com/en/rest/search/search#search-repositories)：`c3d MoonBit in:readme`、`mocap MoonBit in:readme`、`c3d language:MoonBit`、`c3d MoonBit in:name,description,readme` 均为0条；`bvh MoonBit in:readme` 为6条，响应未标记结果不完整。检索结果仍受 GitHub 索引范围限制。

## 最接近的项目

完整读取 [MoonBVHKit](https://github.com/zhangbowen2006/MoonBVHKit) 英文 README 与公开 API。README blob `78dc33ead5a321488e7f295bb521369274e83e5a`；API blob `502b3766296890c6534a372766fe20094b2deff4`。

该项目处理 ASCII BVH 骨架、旋转通道、运动帧、裁剪/重采样和导入质量，公开接口未提供 C3D 二进制参数区、同步模拟通道或 C3D 写出。双方的裁剪/报告场景有交集；MoonC3D 聚焦 C3D 文件交换及多采样率物理信号，不提供 BVH 骨架、动画重定向和插值。

另外定向读取 Kai-Junhan/moon-ray 和 mizchi/three-mbt 的 README；前者 BVH 是光追索引，后者是文本 BVH loader/动画绑定。未完整核查这两个大型仓库的全部源码，不视为源码级排除证明。

开发前已因直接重合排除 LAS、rsync、SEG-Y 和 FlexBuffers 方向。本项目采用 C3D 官方文档作为格式依据，独立实现；外部 py-c3d 仅用于实际互操作验证。

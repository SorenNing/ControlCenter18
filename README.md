# ControlCenter18

**ControlCenter18（iOS 18 风格控制中心）整合 CCLess++ 30 个模块 + 中文汉化**

> 基于原版 ControlCenter18 3.0-beta4（evgeniy558）构建，未改动其本体；额外打包了 CCLess++ 2.1.0.1 的 30 个 CC 模块与辅助工具，均为标准 `/Library/ControlCenter/Bundles/` 模块，经 CCSupport 加载。

## 内容

| 路径 | 说明 |
| --- | --- |
| `zh-Hans/` | 设置页中文汉化（36 条 Localizable + 页名 InfoPlist） |
| `deb/` | 整合版安装包（ControlCenter18 + CCLess++ + 汉化，iphoneos-arm64e，版本 3.0-beta4） |
| `C18OwnerRow.m` | 预留：设置页自定义行（未启用） |
| `.github/workflows/build-ownerrow.yml` | macOS 工具链构建（arm64e） |

## 安装

Sileo 安装 `deb/` 下 deb 即可（需先卸载旧版），安装后 respring。

依赖：`mobilesubstrate`、`firmware (>= 16.0)`、`firmware (<< 18.0)`、`preferenceloader`、`com.opa334.ccsupport`

## 致谢

- [ControlCenter18](https://repo.ya-ebal.mom) by evgeniy558
- CCLess++ by 妖刀

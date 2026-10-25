# ControlCenter18

**ControlCenter18（iOS 18 风格控制中心）整合 CCLess++ 30 个模块 + 中文汉化 + 设置页作者头像行**

> 基于原版 ControlCenter18 3.0-beta（evgeniy558）构建，未改动其本体；额外打包了 CCLess++ 2.1.0.1 的 30 个 CC 模块与辅助工具，均为标准 `/Library/ControlCenter/Bundles/` 模块，经 CCSupport 加载。

## 内容

| 路径 | 说明 |
| --- | --- |
| `C18OwnerRow.m` | 注入 Preferences 的源码：在设置页作者横幅下新增「头像 + Ning自用二改版」行，点击跳转 GitHub |
| `C18OwnerRow.plist` | 注入过滤器（com.apple.Preferences） |
| `zh-Hans/` | 设置页中文汉化（36 条 Localizable + 页名 InfoPlist） |
| `avatar/` | 圆形头像资源（设置页头像行用） |
| `deb/` | 整合版安装包（ControlCenter18 + CCLess++ + 汉化 + 头像行，iphoneos-arm64e） |
| `.github/workflows/build-ownerrow.yml` | macOS 工具链构建 C18OwnerRow.dylib（arm64e） |

## 安装

```text
Sileo 安装 deb/ 下 deb 即可（需先卸载旧版 Com * .evgeniy558.controlcenter18），安装后 respring。
```

依赖：`mobilesubstrate`、`firmware (>= 16.0)`、`firmware (<< 18.0)`、`preferenceloader`、`com.opa334.ccsupport`

## 设置页

- 顶部：原版作者横幅（原样）
- 横幅下方：**圆形头像 + 「Ning自用二改版」**，点击打开 https://github.com/SorenNing
- 全部设置项已汉化（中文系统自动生效）

## 构建

- `C18OwnerRow.dylib`：macOS（Xcode ld64）编译，见 workflow；产物 arm64e + PAC 签名
- 整合 deb：本地 dpkg 打包（`dpkg-deb --build --compression=gzip`），不依赖 GitHub Actions

## 致谢

- [ControlCenter18](https://repo.ya-ebal.mom) by evgeniy558
- CCLess++ by 妖刀
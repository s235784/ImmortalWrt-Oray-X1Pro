# ImmortalWrt-Oray-X1Pro

这是为 **向日葵 X1 Pro** 构建轻量 ImmortalWrt 固件的仓库。已在 ImmortalWrt v25.12.2 上测试通过。

## 前言

截至本文编写时，网络上主要有两套适配向日葵 X1 Pro 的 U-Boot：

1. [小路由完美刷OpenWrt | 蒲公英X1 Pro刷机＋恢复原厂 - OpenRouter](https://www.bilibili.com/video/BV1Wr8k6gEf5)
2. [全网首发：蒲公英 X1Pro 刷机OpenWrt系统教程，原厂固件竟然不支持手动升级 - 猫点饭](https://mao.fan/article/501)

两者的区别在 Flash 分区布局：OpenRouter 版本沿用向日葵原厂布局（主 UBI 分区起点为 `0x800000`），可以通过该 U-Boot 重新刷回原厂系统；猫点饭版本则采用 Cudy TR3000 布局（主 UBI 分区起点为 `0x5c0000`），刷入后无法回退至原厂系统。此外，这两个版本的 Uboot 似乎不能互相升级（[参考地址](https://www.bilibili.com/video/BV1Wr8k6gEf5?comment_on=1&comment_root_id=313164441777&share_tag=s_i#reply313164441777)，我没有进行测试）。

虽然 X1 Pro 的硬件与 Cudy TR3000 接近，但使用 OpenRouter 的 Uboot 的设备不能直接刷入 [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/) 或 [ImmortalWrt Firmware Selector](https://firmware-selector.immortalwrt.org/) 提供的 Cudy TR3000 固件。同时，目前官方还没有适配 向日葵 X1 Pro。

网上由民间大佬编译的版本或多或少与我的需求不符，存在太臃肿、编译内容不透明、安全性没办法保证的情况，最终决定自己动手丰衣足食。

## 说明

本仓库提供两份 `diffconfig`：

`config/x1pro-minimal.config`：除 X1 Pro 运行所需依赖外，仅包含 LuCI WebUI 与简体中文语言包。

`config/x1pro-daily.config`：包含了以下软件包或功能

- WebUI
- PBR
- USB 网络共享
- luci-app-package-manager
- luci-app-wifischedule
- luci-app-autoreboot
- htop
- vim
- argon 主题
- 简体中文语言包

## 编译步骤

以下示例在 Debian 12 AMD64 的普通用户下执行；不要以 `root` 运行 `make`，源码路径不能包含空格或非 ASCII 字符。

建议给编译环境至少分配 4 vCPU、8 GB RAM、4 GB Swap、40 GB 可用磁盘空间。

### 1. 准备环境

安装 ImmortalWrt 官方 [README](https://github.com/immortalwrt/immortalwrt#requirements) 中列出的 Debian/Ubuntu 构建依赖。如果在国内网络环境下构建，建议设置代理环境变量：

```sh
export http_proxy=http://<proxy-host>:<port>
export https_proxy=http://<proxy-host>:<port>
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
```

### 2. 获取本仓库与固定的 ImmortalWrt 源码

设置本仓库与官方源码目录。请将下列两个路径替换为实际的绝对路径：

```sh
export PROJECT_DIR=/path/to/ImmortalWrt-Oray-X1Pro
export SOURCE_DIR=/path/to/immortalwrt
```

目录结构建议如下：

```text
<workspace>/
├── ImmortalWrt-Oray-X1Pro/  # 本仓库（PROJECT_DIR）
└── immortalwrt/             # 官方 ImmortalWrt 源码（SOURCE_DIR）
```

将本仓库置于 `PROJECT_DIR` 后，拉取并固定官方源码：

```sh
mkdir -p "$SOURCE_DIR"
cd "$SOURCE_DIR"

git clone --branch v25.12.2 --single-branch --filter=blob:none \
  https://github.com/immortalwrt/immortalwrt.git .

test "$(git rev-parse HEAD)" = \
  4fc16f2985a358bd43bb522e43f05395fcbd6ed5
```

### 3. 初始化 feeds 并应用 X1 Pro 适配

```sh
cd "$SOURCE_DIR"

./scripts/feeds update -a
./scripts/feeds install -a

"$PROJECT_DIR/scripts/apply-x1pro-port.sh" "$PWD"
```

上述步骤会复制 X1 Pro 的 DTS，并应用镜像、网络默认接口、MAC 地址和 sysupgrade 所需补丁。

### 4. 准备 Argon 并选择配置档

本仓库提供两份配置：

```text
config/x1pro-minimal.config  # 最简版
config/x1pro-daily.config    # 日常版
```

若构建最简版：

```sh
cp "$PROJECT_DIR/config/x1pro-minimal.config" .config
make defconfig
```

日常版使用 Argon 主题与设置插件，因此必须先准备第三方包，再运行 `make defconfig`：

```sh
cd "$SOURCE_DIR"

"$PROJECT_DIR/scripts/prepare-argon-packages.sh" "$PWD"

cp "$PROJECT_DIR/config/x1pro-daily.config" .config
make defconfig
```

### 5. 下载与编译

```sh
cd "$SOURCE_DIR"

make download -j$(nproc)
make -j$(nproc)
```

首次编译需要下载、构建工具链、内核和所选软件包，耗时较长（在 6 vCPU、16 GB RAM、4 GB Swap 虚拟机上耗时一个半小时）。失败时不要立刻运行 `make clean`；保留现场并使用单线程详细日志定位：

```sh
make -j1 V=s
```

成功后，X1 Pro 的原始镜像位于：

```text
bin/targets/mediatek/filogic/*oray_x1pro*sysupgrade.bin
```

日常升级应使用 `*-sysupgrade.bin`，不要将 `*-initramfs-kernel.bin` 当作普通 sysupgrade 镜像使用。

### 6. 归档构建产物

编译完成后运行归档脚本；它会验证镜像元数据、保存配置快照与校验和，并生成可追溯的文件名：

```sh
cd "$SOURCE_DIR"

"$PROJECT_DIR/scripts/collect-artifact.sh" "$PWD" daily
```

最小版使用 `minimal` 参数：

```sh
"$PROJECT_DIR/scripts/collect-artifact.sh" "$PWD" minimal
```

归档示例：

```text
output/20260919-163000_25.12.2_4fc16f2985a3_daily/
├── immortalwrt-25.12.2-oray_x1pro-sysupgrade-md5_<md5>.bin
├── md5sums
├── sha256sums
├── build-info.txt
├── x1pro-daily.config
└── x1pro-daily.generated.config
```

`build-info.txt` 记录源码 tag/commit、镜像大小、MD5、SHA256、配置状态及 Argon 的固定 commit。

## 参考

- X1 Pro 设备树 [`mt7981b-oray-x1-pro.dts`](https://github.com/yvzz/Action-Oray-X1Pro/blob/v25.12/devices/mt7981b-oray-x1-pro.dts) 和适配补丁 [`0001-mediatek-filogic-add-oray-x1-pro.patch`](https://github.com/yvzz/Action-Oray-X1Pro/blob/v25.12/patches/0001-mediatek-filogic-add-oray-x1-pro.patch) 均来源于 [`yvzz/Action-Oray-X1Pro`](https://github.com/yvzz/Action-Oray-X1Pro) 的 `v25.12` 分支，引用 commit：`efa43e3586023bac96e6fd9da5f63963f749feb0`。

![GitHub License](https://img.shields.io/github/license/itv3/homeproxy?style=for-the-badge&logo=github)
![GitHub Release](https://img.shields.io/github/v/release/itv3/homeproxy?style=for-the-badge&logo=github)
![GitHub Downloads](https://img.shields.io/github/downloads/itv3/homeproxy/total?style=for-the-badge&logo=github)

# HomeProxy Custom

这是基于 [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy) 的个人自定义版本。

当前维护分支：[`custom/homeproxy-enhancements`](https://github.com/itv3/homeproxy/tree/custom/homeproxy-enhancements)

适用环境：

- ImmortalWrt / OpenWrt 使用 `apk` 包管理器的版本
- 已启用 firewall4
- 已安装或可从系统源安装 `sing-box`

已在以下环境验证：

- ImmortalWrt 25.12.0
- sing-box 1.12.25
- apk-tools 3.0.5

## 与上游的关系

上游原版仓库：

<https://github.com/immortalwrt/homeproxy>

本仓库只维护个人使用所需的增强功能，尽量跟随上游代码。上游 HomeProxy 更新后，需要把上游变更合并到本分支，再重新构建自定义 APK。

## 优化内容

1. 支持 SS2022 + ShadowTLS 节点

   - Shadowsocks 节点页面增加 `启用 ShadowTLS`。
   - 勾选后显示 ShadowTLS 地址、端口、密码、伪装 SNI、版本。
   - 生成 sing-box 配置时使用 Shadowsocks outbound + ShadowTLS detour。

2. 路由节点支持 Selector

   - 路由节点类型新增 `Selector`。
   - Selector 可包含具体代理节点。
   - Selector 也可包含已有路由节点，例如 `Proxy_Auto`。
   - 增加递归引用检查，避免路由节点互相引用形成循环。

3. 路由规则可直接选择具体节点

   - 路由规则的出站不再只能选择路由节点。
   - 可以直接选择某个具体代理节点。
   - 生成器会自动补齐该节点需要的 sing-box outbound。

4. 默认开启 Clash API

   - 默认启用 `experimental.clash_api`。
   - 默认监听 `192.168.9.1:9090`。
   - 默认允许 MetaCubeXD / Yacd 页面访问。
   - 默认允许浏览器 Private Network Access。

5. 增加 MetaCubeXD 快捷入口

   - HomeProxy 客户端页面增加 `打开面板` 按钮。
   - 默认跳转到 <https://metacubexd.pages.dev/#/overview>。
   - 跳转时自动带入 Clash API 的 host、port、secret 等参数。

6. 自定义 APK 自动发布

   - push 到 `custom/homeproxy-enhancements` 后自动构建 APK。
   - 最新 APK 会提交到 `dist/`。
   - 打 tag 后会自动发布到 GitHub Releases。

## 安装和更新

### A. 一键安装

在 OpenWrt / ImmortalWrt 路由器上执行：

```sh
wget -O - https://github.com/itv3/homeproxy/raw/refs/heads/custom/homeproxy-enhancements/install.sh | ash
```

### B. 手动安装

下载最新发布版 APK：

```sh
wget -O /tmp/luci-app-homeproxy-custom.apk https://github.com/itv3/homeproxy/releases/latest/download/luci-app-homeproxy-custom_all.apk
apk add --allow-untrusted /tmp/luci-app-homeproxy-custom.apk
rm -f /tmp/luci-app-homeproxy-custom.apk
```

清理升级产生的 `.apk-new` 文件：

```sh
find /etc/homeproxy /etc/config -name "*.apk-new" -exec rm -f {} \; 2>/dev/null || true
```

重启服务：

```sh
/etc/init.d/homeproxy restart
```

### C. 从本仓库 `dist/` 安装

也可以直接下载分支中的 APK：

<https://github.com/itv3/homeproxy/tree/custom/homeproxy-enhancements/dist>

## 验证

安装后可执行：

```sh
apk list -I | grep luci-app-homeproxy
ucode -L "/etc/homeproxy/scripts/*.uc" /etc/homeproxy/scripts/generate_client.uc
sing-box check -c /var/run/homeproxy/sing-box-c.json
/etc/init.d/homeproxy status
sleep 2
ubus call luci.homeproxy connection_check '{"site":"google"}'
```

## 给开发者 / AI 的维护说明

只看本 README 应该能完成一次新功能开发和发布。当前自定义版主要涉及下面几类文件：

```text
htdocs/luci-static/resources/view/homeproxy/client.js   # 客户端页面、路由节点、路由规则、打开面板按钮
htdocs/luci-static/resources/view/homeproxy/node.js     # 节点页面、SS2022 + ShadowTLS 表单
root/etc/homeproxy/scripts/generate_client.uc           # 生成 sing-box 客户端配置
root/etc/homeproxy/scripts/migrate_config.uc            # 旧配置迁移和默认配置补齐
root/etc/config/homeproxy                               # 新安装时的默认配置
.github/build-ipk.sh                                    # APK/IPK 打包脚本
.github/workflows/build-ipk.yml                        # push 后自动构建并把 APK 写入 dist/
.github/workflows/release-dist.yml                     # tag 后发布 GitHub Release
install.sh                                              # 路由器一键安装脚本
dist/luci-app-homeproxy_*.apk                           # 当前分支最新构建包，由 Actions 自动更新
```

### 开发新功能

```sh
git clone git@github.com:itv3/homeproxy.git
cd homeproxy
git checkout custom/homeproxy-enhancements
git remote add upstream https://github.com/immortalwrt/homeproxy.git 2>/dev/null || true
git fetch origin
git fetch upstream
```

修改代码后先做基本检查：

```sh
git diff --check
sh -n install.sh
```

如果改了 GitHub Actions workflow，可额外检查 YAML：

```sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build-ipk.yml"); YAML.load_file(".github/workflows/release-dist.yml"); puts "yaml ok"'
```

提交并推送：

```sh
git add <changed-files>
git commit -m "feat: describe the change"
git push origin custom/homeproxy-enhancements
```

推送后 GitHub Actions 会自动构建 APK，并由 bot 再提交一次 `dist/luci-app-homeproxy_*.apk`。发布 Release 前必须先拉取这个 bot 提交，否则 Release 里会拿到旧 APK：

```sh
git pull --ff-only origin custom/homeproxy-enhancements
ls -lh dist/luci-app-homeproxy_*.apk
shasum -a 256 dist/luci-app-homeproxy_*.apk
```

### 发布新版本

tag 必须打在已经包含最新 `dist/` APK 的提交上。推荐格式：

```sh
FEATURE_SHA="$(git log --format=%h --no-merges -n 1 -- . ':!dist')"
TAG="custom-$(date +%Y%m%d)-${FEATURE_SHA}"
git tag -a "$TAG" -m "HomeProxy Custom ${TAG#custom-}"
git push origin "$TAG"
```

推送 tag 后，`Release custom APK` workflow 会创建 GitHub Release，并只上传两个文件：

```text
luci-app-homeproxy-custom_all.apk
SHA256SUMS.txt
```

发布后检查：

```sh
curl -fsSL https://api.github.com/repos/itv3/homeproxy/releases/latest \
  | jq -r '.tag_name, .assets[].name, .assets[].digest'
```

### 路由器实机验证

推荐至少验证一次安装和服务状态：

```sh
wget -O - https://github.com/itv3/homeproxy/raw/refs/heads/custom/homeproxy-enhancements/install.sh | ash
apk list -I | grep luci-app-homeproxy
find /etc/homeproxy /etc/config -name "*.apk-new" -print
ucode -L "/etc/homeproxy/scripts/*.uc" /etc/homeproxy/scripts/generate_client.uc
sing-box check -c /var/run/homeproxy/sing-box-c.json
/etc/init.d/homeproxy status
sleep 2
ubus call luci.homeproxy connection_check '{"site":"google"}'
```

## HomeProxy 上游更新后怎么办

不要直接用上游包覆盖本自定义包。推荐流程：

```sh
git fetch upstream
git fetch origin
git checkout custom/homeproxy-enhancements
git merge upstream/master
git push origin custom/homeproxy-enhancements
```

等待 GitHub Actions 构建完成后，安装新的自定义 APK。

容易发生冲突的文件：

```text
htdocs/luci-static/resources/view/homeproxy/client.js
htdocs/luci-static/resources/view/homeproxy/node.js
root/etc/homeproxy/scripts/generate_client.uc
root/etc/homeproxy/scripts/migrate_config.uc
root/etc/config/homeproxy
```

## 提交给上游的建议

如果要向上游提交合并请求，建议拆成几个小 PR：

1. SS2022 + ShadowTLS 节点支持。
2. 路由节点支持 Selector。
3. 路由规则出站支持直接选择具体节点。
4. Clash API 和 MetaCubeXD 快捷入口。

其中第 4 点可能有安全和默认行为争议，更适合做成可选配置，不建议强制默认开启。

不建议提交给上游的内容：

- `dist/` 下的 APK。
- 个人 fork 的 Release 自动发布逻辑。
- 自定义 `99.` 版本号策略。

## 注意

MetaCubeXD 的规则开关对当前 sing-box Clash API 不生效。sing-box 当前只提供 `/rules` 读取接口，没有实现 `PATCH /rules/disable` 这种运行时禁用规则的接口。

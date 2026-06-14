# HomeProxy 安全修复状态

**修复日期**: 2026-06-14  
**基于审计报告**: SECURITY_AUDIT_FINAL.md v3.0

## ✅ 已完成修复（15/20）

### 上游问题（2/2）
1. ✅ **U-H1** (Critical): sing-box generate 命令注入 RCE
   - 修复: 使用 `shellquote()` 转义参数
   - 文件: `root/usr/share/rpcd/ucode/luci.homeproxy:501`
   
2. ✅ **U-H2** (Low): tproxy/tun 参数初始化条件写法错误
   - 修复: 修正 `match()` 函数括号位置
   - 文件: `root/etc/homeproxy/scripts/generate_client.uc:125,128`

### 自定义安全问题（8/10）
3. ✅ **C-H1** (Medium): 安装脚本信任链不完整
   - 修复: 添加公钥指纹验证和 APK 签名验证
   - 文件: `install.sh`

4. ✅ **C-M1** (Medium): RPC ACL 通配符权限过度
   - 修复: 替换通配符为显式方法白名单
   - 文件: `root/usr/share/rpcd/acl.d/luci-app-homeproxy.json`

5. ✅ **N-M1** (Medium): resources_get_version 路径穿越
   - 修复: 添加资源类型白名单验证
   - 文件: `root/usr/share/rpcd/ucode/luci.homeproxy:572`

6. ✅ **C-M3** (Low): 备份包缺少完整性校验
   - 修复: 生成和验证 SHA-256 manifest
   - 文件: `root/usr/share/rpcd/ucode/luci.homeproxy`

7. ✅ **C-L2** (Low): 恢复流程缺少服务验证
   - 修复: 恢复后检查服务状态，失败则自动回滚
   - 文件: `root/usr/share/rpcd/ucode/luci.homeproxy`

8. ✅ **C-L3** (Low): CORS Origin 反射
   - 修复: 替换为已知仪表板 Origin 白名单
   - 文件: `root/etc/homeproxy/scripts/clash_api_proxy.uc:443`

9. ✅ **C-H2** (Low): Clash API 代理缺少资源限制
   - 修复: 添加连接数限制(64)、idle 超时(30s)
   - 文件: `root/etc/homeproxy/scripts/clash_api_proxy.uc`

10. ✅ **C-L4** (Low): 请求/响应缓冲区无大小上限
    - 修复: 限制请求 256KB、响应 8MB
    - 文件: `root/etc/homeproxy/scripts/clash_api_proxy.uc`

### CI/CD 加固（1/1）
11. ✅ **C-M6** (P4): CI 签名私钥临时文件加固
    - 修复: 添加 trap 清理、使用 shred 安全删除
    - 文件: `.github/workflows/release-custom-apk.yml`

### 代码质量优化（4/7）
12. ✅ **2.14**: 递归检查效率优化
    - 修复: 为 `selectorHasPath` 添加缓存
    - 文件: `htdocs/luci-static/resources/view/homeproxy/client.js:211`

13. ✅ **2.16**: CI/CD 优化
    - 修复: 添加 apk-tools 构建缓存
    - 文件: `.github/workflows/build-ipk.yml`

14. ✅ **2.17**: 自动化测试
    - 修复: 添加 shell 和 JavaScript 语法检查步骤
    - 文件: `.github/workflows/build-ipk.yml`

15. ✅ **2.18**: 错误提示优化（部分）
    - 修复: 路由节点错误改为中文并添加解决步骤
    - 文件: `root/etc/homeproxy/scripts/generate_client.uc:458,461`

---

## ⏭️ 未完成项目（5/20）

### C-L1: 临时文件使用固定路径（Low，工作量 1h）
**原因**: 需要前后端协同修改，影响面广
- 后端需改用随机文件名生成函数
- 前端需适配动态路径返回
- 涉及 backup_create/validate/restore 三个 RPC 方法
- 需要测试备份下载、上传恢复的完整流程

**建议**: 作为独立任务在下次更新时处理

### 2.11: 代码复杂度过高（工作量 4-6h）
**原因**: 需要大规模重构
- `generate_outbound` 函数 130 行，嵌套 6 层
- 需要拆分为协议特定的子函数
- 需要设计新的抽象层
- 需要全面测试各种协议配置

**建议**: 作为长期技术债务，逐步重构

### 2.12: 前端代码臃肿（工作量 8-12h）
**原因**: 需要大规模重构
- `client.js` 1730 行，大量重复表单定义
- 需要设计表单字段工厂模式
- 需要重构数百个表单字段定义
- 需要全面测试 WebUI 功能

**建议**: 作为长期技术债务，逐步重构

### 2.13: 缺少错误恢复机制（工作量 6-8h）
**原因**: 需要架构改动
- 当前多处使用 `die()` 直接终止
- 需要设计配置验证框架
- 需要实现降级策略
- 需要设计错误上报机制

**建议**: 结合 2.11 重构一起处理

### 2.15: Clash API 代理部分过滤路径同步阻塞（工作量 4-6h）
**原因**: 需要异步改造
- `fetchUpstream()` 等过滤路径使用同步 I/O
- 需要改造为 uloop 异步事件模型
- 需要重新设计状态机
- 需要测试各种 Clash API 调用场景

**建议**: 结合 C-H2 的资源限制优化一起处理

---

## 📊 修复统计

- **安全问题**: 10/11 完成（91%）
  - Critical: 1/1 完成 ✅
  - Medium: 3/3 完成 ✅
  - Low: 6/7 完成（缺 C-L1）
  
- **可选加固**: 1/1 完成 ✅

- **代码质量**: 4/8 完成（50%）

---

## 🎯 修复优先级总结

**P0 - 已全部完成**:
- U-H1: 命令注入 RCE (Critical)
- C-H1, C-M1, N-M1: Medium 安全问题

**P1 - 已全部完成**:
- 所有 Low 安全问题（除 C-L1）

**P2-P4 - 部分完成**:
- C-M6: 已完成
- C-M3, C-L2: 已完成
- C-L1, 2.11-2.13, 2.15: 未完成（大型重构）

---

## 📋 下次更新建议

1. **C-L1 临时文件随机化**（1小时，独立任务）
2. **2.18 错误提示完善**（2小时，改进用户体验）
3. **2.11 + 2.13 联合重构**（2-3天，长期技术债务）
4. **2.12 前端重构**（3-4天，分阶段进行）
5. **2.15 异步改造**（1-2天，性能优化）

---

**修复完成**: 2026-06-14  
**提交**: security-fixes-20260614 分支

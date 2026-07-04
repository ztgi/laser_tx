# debug_reports archive 说明

本目录保存已被当前主报告吸收的中间过程报告和废弃辅助图。

当前正式阅读入口为：

```text
docs/debug_reports/README_validation_report_reading_order.md
docs/debug_reports/00_current_validation_status.md
docs/debug_reports/01_profile0_500m_ila_validation_summary.md
docs/debug_reports/02_profile1_1000m_static_build_and_debug_fix.md
docs/debug_reports/03_profile1_1000m_static_ila_validation_summary.md
```

归档内容说明：

```text
profile0_old_reports/
  Profile0 相关旧中间报告，核心结论已合并到 01_profile0_500m_ila_validation_summary.md。

profile1_1000m_intermediate_reports/
  1000M static build、旧 ILA/debug check、AXI/FCLK bring-up ILA fix 等中间报告，
  核心结论已合并到 02_profile1_1000m_static_build_and_debug_fix.md 和
  03_profile1_1000m_static_ila_validation_summary.md。

csv_redraw_png_deprecated/
  早期从 ILA CSV 辅助重绘得到的 PNG，已废弃，不再作为正式主证据。

udp_intermediate_reports/
  UDP/lwIP/ARP 相关中间调试报告，当前不作为 Profile0/Profile1/1000M ILA 验证主入口；
  若后续恢复 UDP 控制层调试，可再从该目录追溯。
```

原始 CSV/log/timing report/implemented check report 不应删除；真实 Vivado GUI 截图保留在 `docs/images/`。

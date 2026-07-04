# 不依赖 ILA 的调试流程

最终主流程是 UART 或 UDP 状态回读，而不是每次打开 Hardware Manager。

1. 读取原 laser GPIO status：确认 cfg_valid、cfg_error、busy、done、state、pattern_valid。
2. 读取独立 GT status：确认 CPLL lock、TX reset done、gt_ready、profile 与有效 word 计数。
3. `START` 前如果 GT 未 ready，软件返回明确原因且不置 enable。
4. 仅当状态异常、GT 未 ready、word 计数不增或接收端无数据时，才使用 ILA。

现有 ILA 可继续作为备用：配置侧观察 GPIO/BRAM；TX 侧观察 cfg_update、engine_start、状态机、txdata、valid_mask 和同步输出。ILA 不替代软件状态回读，也不构成硬件功能已验证的证据。

# EOM 仅内部使用说明

当前板卡只有一路可用高速光口。因此物理输出仅为 GT 的 `gtx_txp_out/gtx_txn_out`，承载 `laser_tx_core.txdata[63:0]`。

`eom_out` 不会接到第二路 GT、OSERDES 或 GPIO bit 串行口。它仅可用于：同步控制输出、内部调试、ILA 备用观察、状态辅助和判断当前 word 是否有有效发送区。

`valid_mask[63:0]` 仍是 gap/无效 bit 判定的权威信号。任何后续文档或软件不得把 EOM 描述成独立物理光输出。

# AFDX V3 独立端系统

V3 已从 V2 移植独立端系统数据通路，主入口 `AFDX_top`，测试入口 `tb_afdx_end_system`。A端命名为tx_a_*/rx_a_*，与B端对称，两路只共享全局reset。包含固定 A/B 冗余复制和完整 VLID/SN 消重；发送 FIFO 已替换为可推断同步实现。两路 RX 已加入超长/缺last/短帧丢弃保护，内置34项有效异常及运行统计，另有2个保留地址读零。当前主入口单 TX VL，未使用的四 VL 扩展已删除；SNMP、615A、RTC 和 eLinx 最终验收仍待完成。

实际工程：[AFDX_v3.xpr](C:/Users/Admin/Documents/AFDX_PRJ/AFDX_v3/AFDX_v3/AFDX_v3.xpr)。在本 README 所在目录执行 `python tools/run_regression.py`；Vivado 项目已登记 22 个 RTL 和 10 个自检 testbench。

|文档|内容|
|---|---|
|[技术说明书](C:/Users/Admin/Documents/AFDX_PRJ/AFDX_v3/AFDX_v3/docs/技术说明书.md)|赛题边界、详细结构、接口、时序、配置和工具函数|
|[函数与变量明细](C:/Users/Admin/Documents/AFDX_PRJ/AFDX_v3/AFDX_v3/docs/函数与变量明细.md)|全部 HDL function/task 输入输出、每项变量作用、赋值和源码证据|
|[拓扑与端口连接](C:/Users/Admin/Documents/AFDX_PRJ/AFDX_v3/AFDX_v3/docs/拓扑与端口连接.md)|全部实例和逐端口表达式及传递原因|
|[统计寄存器说明](C:/Users/Admin/Documents/AFDX_PRJ/AFDX_v3/AFDX_v3/docs/统计寄存器说明.md)|34项有效计数及2个保留地址、事件及清零规则|
|[进度说明](C:/Users/Admin/Documents/AFDX_PRJ/AFDX_v3/AFDX_v3/docs/进度说明.md)|已移植、已验证、未完成及需求状态|
|[下一步目标与未完成清单](C:/Users/Admin/Documents/AFDX_PRJ/AFDX_v3/AFDX_v3/docs/下一步目标与未完成清单.md)|按优先级给出具体工作与验收判据|
|[测试报告](C:/Users/Admin/Documents/AFDX_PRJ/AFDX_v3/AFDX_v3/docs/测试报告.md)|最终版本实际回归、XSim 和综合证据与限制|

开发继续使用Vivado；V3-P0-1（eLinx）和V3-P0-2（题目MAC模板对照）按用户安排暂缓，eLinx最终移植。完整执行命令见技术说明书。`tools/rtl_sources.f`、`tools/testbench_sources.f`、`constraints/mac_stream_80ns.sdc` 是其他工具移植的起点；提供文件清单不代表已经在 eLinx 通过。

换算关系：1 us = 1000 ns， 即报告中的 20 us 对应20,000ns

文件打开地址：中科亿海微elinx平台 ~\AFDX_ES_eLinx\AFDX_ES_eLinx.epr，也可复制AFDX_ES_eLinx\AFDX_ES_eLinx.srcs内的v文件到Vivado等软件中运行。

文档说明地址：\AFDX_ES_eLinx\docs\competition_draft，使用LaTex/xetex打开。

本项目为AFDX端系统全流程设计，含SNMP,615A,TFTP等协议，供参考。

联系方式：zhou_zheng@mail.ustc.edu.cn，禁止商用，仅供学习交流。版权所有。
## 工程内容

- `AFDX_ES_eLinx.epr`：eLinx 工程入口；`AFDX_ES_eLinx.srcs`：设计、仿真源码和约束。
- `files`：仿真输入文件；`docs/competition_draft/main.tex` 和 `main.pdf`：分章报告及阅读版。
- `.qsf` 使用项目内相对路径；打开后按实际工具安装位置配置仿真器。综合和仿真生成的缓存未上传。

`timescale 1ns/1ps
// 完整端系统验证协商块长的整块终止和跨块一字节；复用公开IO文件检查。
module tb_tftp_exact;
 afdx_single_file_case #(.CAPACITY(2048),.FILE_NAME("tftp_exact.bin")) test();
endmodule
module tb_tftp_above;
 afdx_single_file_case #(.CAPACITY(2048),.FILE_NAME("tftp_above.bin")) test();
endmodule

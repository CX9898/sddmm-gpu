#!/bin/bash

# 设置变量
results_path="results_dataset_of_1/"
dataset_path="./dataset_of_suiteSparse/"

# 创建结果目录
mkdir -p ${results_path}

# 生成矩阵文件列表
bash make_matrices_list.sh ${dataset_path}
matrix_list_file="${dataset_path}matrix_file_list.txt"

# 编译程序
bash build_program.sh
program_zcx="./build_zcx/sddmm-gpu"
program_cuSDDMM="./build_cuSDDMM/cuSDDMM-sddmm"
program_ASpT_32="./build_ASpT/ASpT-sddmm-32"
program_ASpT_128="./build_ASpT/ASpT-sddmm-32"
program_BSA="./build_BSA/BSA-spmm"

# 运行测试程序
#bash test_script.sh -f ${matrix_list_file} -p ${program_zcx} -n "${results_path}zcx_32_a_0.3_b_4" -k 32 -a 0.3 -b 4 # hybrid method
#bash test_script.sh -f ${matrix_list_file} -p ${program_zcx} -n "${results_path}zcx_32_a_0.3_b_1" -k 32 -a 0.3 -b 1 # only Tensor Core
#bash test_script.sh -f ${matrix_list_file} -p ${program_zcx} -n "${results_path}zcx_32_a_0.3_b_17" -k 32 -a 0.3 -b 17 # only CUDA Core
#
#bash test_script.sh -f ${matrix_list_file} -p ${program_zcx} -n "${results_path}zcx_128_a_0.3_b_4" -k 128 -a 0.3 -b 4 # hybrid method
#bash test_script.sh -f ${matrix_list_file} -p ${program_zcx} -n "${results_path}zcx_128_a_0.3_b_1" -k 128 -a 0.3 -b 1 # only Tensor Core
#bash test_script.sh -f ${matrix_list_file} -p ${program_zcx} -n "${results_path}zcx_128_a_0.3_b_17" -k 128 -a 0.3 -b 17 # only CUDA Core
#
#bash test_script.sh -f ${matrix_list_file} -p ${program_cuSDDMM} -n "${results_path}cuSDDMM_32" -k 32
#bash test_script.sh -f ${matrix_list_file} -p ${program_cuSDDMM} -n "${results_path}cuSDDMM_128" -k 128
#bash test_script.sh -f ${matrix_list_file} -p ${program_ASpT_32} -n "${results_path}ASpT_32" -k 32
#bash test_script.sh -f ${matrix_list_file} -p ${program_ASpT_128} -n "${results_path}ASpT_128" -k 128
#bash test_script.sh -f ${matrix_list_file} -p ${program_BSA} -n "${results_path}BSA_32" -k 32

g++ analyze_results.cpp -o analyze_results

./analyze_results "${results_path}zcx_32_a_0.3_b_4.log" \
                      "${results_path}cuSDDMM_32.log" \
                      "${results_path}ASpT_32.log" \
                      > ${results_path}analysis_results_32_a_0.3_b_4.log
echo "Results analysis completed: ${results_path}analysis_results_32_a_0.3_b_4.log"

./analyze_results "${results_path}zcx_32_a_0.3_b_1.log" \
                      "${results_path}cuSDDMM_32.log" \
                      "${results_path}ASpT_32.log" \
                      > ${results_path}analysis_results_32_a_0.3_b_1.log
echo "Results analysis completed: ${results_path}analysis_results_32_a_0.3_b_1.log"

./analyze_results "${results_path}zcx_32_a_0.3_b_16.log" \
                      "${results_path}cuSDDMM_32.log" \
                      "${results_path}ASpT_32.log" \
                      > ${results_path}analysis_results_32_a_0.3_b_16.log
echo "Results analysis completed: ${results_path}analysis_results_32_a_0.3_b_16.log"

./analyze_results "${results_path}zcx_128_a_0.3_b_4.log" \
                      "${results_path}cuSDDMM_128.log" \
                      "${results_path}ASpT_128.log" \
                      > ${results_path}analysis_results_128_a_0.3_b_4.log
echo "Results analysis completed: ${results_path}analysis_results_128_a_0.3_b_4.log"

./analyze_results "${results_path}zcx_128_a_0.3_b_1.log" \
                      "${results_path}cuSDDMM_128.log" \
                      "${results_path}ASpT_128.log" \
                      > ${results_path}analysis_results_128_a_0.3_b_1.log
echo "Results analysis completed: ${results_path}analysis_results_128_a_0.3_b_1.log"

./analyze_results "${results_path}zcx_128_a_0.3_b_16.log" \
                      "${results_path}cuSDDMM_128.log" \
                      "${results_path}ASpT_128.log" \
                      > ${results_path}analysis_results_128_a_0.3_b_16.log
echo "Results analysis completed: ${results_path}analysis_results_128_a_0.3_b_16.log"



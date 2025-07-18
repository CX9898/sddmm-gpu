#!/bin/bash

# 设置变量
results_path="results_suiteSparse_dataset/"
k32_results_path="${results_path}k32/"
k128_results_path="${results_path}k128/"

# 创建结果目录
mkdir -p ${k32_results_path}
mkdir -p ${k128_results_path}

dataset_path="suiteSparse_dataset/"

bash make_matrices_list.sh ${dataset_path}
matrix_list_file="${dataset_path}matrix_file_list_mtx.txt"

program_cuSDDMM="./build_cuSDDMM/cuSDDMM-sddmm"
program_ASpT_32="./build_ASpT/ASpT-sddmm-32"
program_ASpT_128="./build_ASpT/ASpT-sddmm-32"
program_BSA="./build_BSA/BSA-spmm"
program_RoDe="./build_RoDe/RoDe-sddmm"

bash test_script.sh -f ${matrix_list_file} -p ${program_cuSDDMM} -n "${k32_results_path}cuSDDMM_32" -k 32
bash test_script.sh -f ${matrix_list_file} -p ${program_cuSDDMM} -n "${k128_results_path}cuSDDMM_128" -k 128
bash test_script.sh -f ${matrix_list_file} -p ${program_ASpT_32} -n "${k32_results_path}ASpT_32" -k 32
bash test_script.sh -f ${matrix_list_file} -p ${program_ASpT_128} -n "${k128_results_path}ASpT_128" -k 128
bash test_script.sh -f ${matrix_list_file} -p ${program_RoDe} -n "${k32_results_path}RoDe_32" -k 32
bash test_script.sh -f ${matrix_list_file} -p ${program_RoDe} -n "${k128_results_path}RoDe_128" -k 128

source ~/miniconda3/etc/profile.d/conda.sh
conda activate TCGNN
python test_TCGNN.py --matrix_list ${matrix_list_file} -K 128 --log_fil ${k128_results_path}TCG11_32

ALPHA=( 0.1 0.3 0.5 0.7 0.9 )
DELTA=( 0.1 0.3 0.5 0.7 0.9 )
for A in "${ALPHA[@]}"; do
  for D in "${DELTA[@]}"; do
    bash test_script.sh -f ${matrix_list_file} -p ${program_BSA} -n "${k32_results_path}BSA_32_a_${A}_d_${D}" -k 32 -a ${A} -d ${D}
  done
done


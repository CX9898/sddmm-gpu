#pragma once

#include <cuda_fp16.h>

#include "devVector.cuh"
#include "Matrix.hpp"
#include "TensorCoreConfig.cuh"
#include "BSMR.hpp"
#include "Logger.hpp"

constexpr int each_thread_block_counts_the_number_Of_dense_blocks = 4;
constexpr int each_thread_block_counts_the_number_Of_cols =
        BLOCK_COL_SIZE * each_thread_block_counts_the_number_Of_dense_blocks;
constexpr int sddmm_dense_block_number_of_warps_per_thread_block = each_thread_block_counts_the_number_Of_dense_blocks;
constexpr int sddmm_sparse_block_number_of_thread_per_thread_block = 256;
constexpr int sddmm_sparse_block_each_thread_block_counts_the_number_Of_data =
        sddmm_sparse_block_number_of_thread_per_thread_block / 2;

void sddmm_gpu(const Matrix<float> &matrixA,
               const Matrix<float> &matrixB,
               const RPHM &rphm,
               sparseMatrix::CSR<float> &matrixP,
               Logger &logger);

void sddmm_gpu(UIN M, UIN N, UIN K,
               const float *matrixA,
               const float *matrixB,
               const RPHM &rphm,
               float *matrixP,
               Logger &logger);

void sddmm_gpu_k32(UIN M,
                   UIN N,
                   UIN K,
                   const float* matrixA,
                   const float* matrixB,
                   const RPHM& rphm,
                   float* matrixP,
                   Logger& logger);

void sddmm_gpu_batch(const UIN numBatch,
                     const UIN M, const UIN N, const UIN K, const UIN nnz,
                     const float *matrixA,
                     const float *matrixB,
                     const RPHM &rphm,
                     float *matrixP,
                     float &time);

void batchedMatrixTranspose(const UIN width, const UIN height, const UIN numBatches,
                            const float *d_input,
                            float *d_output);

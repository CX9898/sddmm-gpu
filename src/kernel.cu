#include <cstdio>

#include <mma.h>

#include "kernel.cuh"
#include "TensorCoreConfig.cuh"
#include "Matrix.hpp"

template<typename T>
__global__ void printData(UIN n, T *a) {
    for (UIN i = 0; i < n; ++i) {
        printf("%f ", static_cast<float>(a[i]));
    }
}

template __global__ void printData<float>(UIN n, float *a);

template __global__ void printData<half>(UIN n, half *a);

__global__ void convertFp32ToFp16(const UIN n, const float *in, half *out) {
    UIN idx = static_cast<UIN> (blockDim.x * blockIdx.x + threadIdx.x);
    if (idx < n) {
        out[idx] = in[idx];
    }
}

template<typename T>
__global__ void convertDataType(const UIN n, const float *in, T *out) {
    const UIN idx = blockDim.x * blockIdx.x + threadIdx.x;
    if (idx < n) {
        out[idx] = static_cast<T>(in[idx]);
    }
}

template __global__ void convertDataType<int>(const UIN n, const float *in, int *out);
template __global__ void convertDataType<float>(const UIN n, const float *in, float *out);
template __global__ void convertDataType<double>(const UIN n, const float *in, double *out);
template __global__ void convertDataType<half>(const UIN n, const float *in, half *out);

const float SPARSITY_BOUND = 1.0f;

template<typename T>
__device__ float calculateMatrixTileSparsity(const int tileM,
                                             const int tileN,
                                             const UIN ld,
                                             const MatrixStorageOrder storageOrder,
                                             const T *matrixPtr) {
    UIN nnzCount = 0;
#pragma unroll
    for (UIN rowIter = 0; rowIter < tileM; ++rowIter) {
#pragma unroll
        for (UIN colIter = 0; colIter < tileN; ++colIter) {
            if (storageOrder == MatrixStorageOrder::row_major) {
                nnzCount += *(matrixPtr + rowIter * ld + colIter) == 0 ? 0 : 1;
            } else {
                nnzCount += *(matrixPtr + colIter * ld + rowIter) == 0 ? 0 : 1;
            }
        }
    }
    const int numValues = tileM * tileN;
    return static_cast<float>(numValues - nnzCount) / static_cast<float>(numValues);
}

__device__ void matrixTileMultiplicationUseCudaCode(int pRowId, int pColId,
                                                    const UIN M, const UIN N, const UIN K,
                                                    const half *matrixA,
                                                    const half *matrixB,
                                                    const float *matrixS,
                                                    float *matrixP) {

}

__device__ void matrixTileMultiplicationUseTensorCore(int pRowId, int pColId,
                                                      const UIN M, const UIN N, const UIN K,
                                                      const half *matrixA,
                                                      const half *matrixB,
                                                      const float *matrixS,
                                                      float *matrixP) {

    // Leading dimensions. Packed with no transpositions.
    const int lda = K;
    const int ldb = N;
    const int ldp = N;
    const auto pOffsetPtr = matrixP + pRowId * ldp + pColId;

    nvcuda::wmma::fragment<nvcuda::wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE, nvcuda::wmma::row_major>
        aFrag;
    nvcuda::wmma::fragment<nvcuda::wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE, nvcuda::wmma::row_major>
        bFrag;

    nvcuda::wmma::fragment<nvcuda::wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;
    fill_fragment(cFrag, 0.0f);

    // Loop over k
    for (int kIter = 0; kIter < K; kIter += WMMA_K) {
        const int aRowId = pRowId;
        const int aColId = kIter;

        const int bRowId = kIter;
        const int bColId = pColId;

        // Bounds checking
        if (aRowId < M && aColId < K && bRowId < K && bColId < N) {
            const auto aOffsetPtr = matrixA + aRowId * lda + aColId;
            const auto bOffsetPtr = matrixB + bRowId * ldb + bColId;

            nvcuda::wmma::load_matrix_sync(aFrag, aOffsetPtr, lda);
            nvcuda::wmma::load_matrix_sync(bFrag, bOffsetPtr, ldb);

            nvcuda::wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
        }
    }

//#pragma unroll
//    for (int idx = 0; idx < cFrag.num_elements; ++idx) {
//        const int sIdx = pRowId * ldc + pColId + idx;
//
//        cFrag.x[idx] *= matrixS[sIdx];
//    }

    nvcuda::wmma::store_matrix_sync(pOffsetPtr, cFrag, ldp, nvcuda::wmma::mem_row_major);
}

__device__ void matrixTileMultiplicationUseTensorCore_coo(TensorCoreConfig tensorCoreConfig,
                                                          const UIN pRowId,
                                                          const UIN pColId,
                                                          const UIN M,
                                                          const UIN N,
                                                          const UIN K,
                                                          const UIN nnz,
                                                          const half *matrixA,
                                                          const half *matrixB,
                                                          const UIN *matrixSRowIndex,
                                                          const UIN *matrixSColIndex,
                                                          const UIN *matrixTileIndex,
                                                          const float *matrixS,
                                                          float *matrixP) {

    // Leading dimensions. Packed with no transpositions.
    const UIN lda = K;
    const UIN ldb = N;

    nvcuda::wmma::fragment<nvcuda::wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE, nvcuda::wmma::row_major>
        aFrag;
    nvcuda::wmma::fragment<nvcuda::wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE, nvcuda::wmma::row_major>
        bFrag;

    nvcuda::wmma::fragment<nvcuda::wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    // Loop over k
    for (int kIter = 0; kIter < K; kIter += WMMA_K) {
        const int aRowId = pRowId;
        const int aColId = kIter;

        const int bRowId = kIter;
        const int bColId = pColId;

        // Bounds checking
        if (aRowId < M && aColId < K && bRowId < K && bColId < N) {
            const auto aOffsetPtr = matrixA + aRowId * lda + aColId;
            const auto bOffsetPtr = matrixB + bRowId * ldb + bColId;

            nvcuda::wmma::load_matrix_sync(aFrag, aOffsetPtr, lda);
            nvcuda::wmma::load_matrix_sync(bFrag, bOffsetPtr, ldb);

            nvcuda::wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
        }
    }

    const int warpId = tensorCoreConfig.globalWarpId();
    const int laneId = tensorCoreConfig.laneId();

    for (int matrixPIdx = matrixTileIndex[warpId];
         matrixPIdx < matrixTileIndex[warpId + 1]; ++matrixPIdx) {
        const UIN curRow = matrixSRowIndex[matrixPIdx];
        const UIN curCol = matrixSColIndex[matrixPIdx];

        FragmentInformation fragmentInformation;
        tensorCoreConfig.positionCalculator(pRowId, pColId, curRow, curCol, fragmentInformation);

//        if (matrixPIdx == 8410 && warpId == 780 && laneId_ == 0) {
//            printf(" warpId = %d\n"
//                   " pRowId = %d, pColId = %d, curRow = %d, curCol = %d, curValue = %f"
//                   " laneId_ = %d findLaneId = %d, findIdx = %d, cFrag.x[%d] = %f\n",
//                   warpId,
//                   static_cast<int>(pRowId),
//                   static_cast<int>(pColId),
//                   static_cast<int>(curRow),
//                   static_cast<int>(curCol),
//                   static_cast<float>(matrixS[matrixPIdx]),
//                   laneId_,
//                   findLaneId,
//                   findIdx,
//                   findIdx,
//                   static_cast<float>(cFrag.x[findIdx]));
//            printf("frag : ");
//            for (int idx = 0; idx < 8; ++idx) {
//                printf("%f ", static_cast<float>(cFrag.x[idx]));
//            }
//            printf("\n");
//        }
        if (laneId == fragmentInformation.laneId_) {
            matrixP[matrixPIdx] = cFrag.x[fragmentInformation.index_];
//            printf(
//                " pRowId = %d, pColId = %d, curRow = %d, curCol = %d, findLaneId = %d, findIdx = %d, cFrag.x[%d] = %f\n",
//                static_cast<int>(pRowId),
//                static_cast<int>(pColId),
//                static_cast<int>(curRow),
//                static_cast<int>(curCol),
//                findLaneId,
//                findIdx,
//                findIdx,
//                static_cast<float>(cFrag.x[findIdx]));
        }
    }
}

__global__ void sddmm_gpu(const UIN M, const UIN N, const UIN K,
                          const half *matrixA, const half *matrixB,
                          const float *matrixS,
                          float *matrixP) {
    const UIN tidX = (blockDim.x * blockIdx.x + threadIdx.x);
    const UIN tidY = (blockDim.y * blockIdx.y + threadIdx.y);

    const UIN warpM = tidX / WARP_SIZE;
    const UIN warpN = tidY;

//    const int landIdM = tidX % WARP_SIZE;
//    const int landIdN = tidY % WARP_SIZE;

    // Compute dense matrix multiplication using Tensor core

    const UIN pRowId = warpM * WMMA_M;
    const UIN pColId = warpN * WMMA_N;
//    const UIN pRowId = warpN * WMMA_N;
//    const UIN pColId = warpM * WMMA_M;

    if (pRowId >= M || pColId >= N) {
        return;
    }
    matrixTileMultiplicationUseTensorCore(pRowId, pColId, M, N, K, matrixA, matrixB, matrixS, matrixP);
//    const int ldp = N;
//    const auto pOffsetPtr = matrixP + pRowId * ldp + pColId;
//    const float sparsity = calculateMatrixTileSparsity(WMMA_M, WMMA_N, ldp, MatrixStorageOrder::row_major, pOffsetPtr);
//    if (sparsity < 0) {
//        matrixTileMultiplicationUseCudaCode(pRowId, pColId, M, N, K, matrixA, matrixB, matrixS, matrixP);
//    } else {
//        matrixTileMultiplicationUseTensorCore(pRowId, pColId, M, N, K, matrixA, matrixB, matrixS, matrixP);
//    }

}

__global__ void sddmm_gpu_coo_1(TensorCoreConfig tensorCoreConfig,
                                const UIN M, const UIN N, const UIN K, const UIN nnz,
                                const half *matrixA, const half *matrixB,
                                const UIN *matrixSRowIndex,
                                const UIN *matrixSColIndex,
                                const UIN *matrixTileIndex,
                                const float *matrixS,
                                float *matrixP) {
    tensorCoreConfig.initByKernel(blockIdx, blockDim, threadIdx);

    const UIN pRowId = tensorCoreConfig.rowBeginOfTile();
    const UIN pColId = tensorCoreConfig.colBeginOfTile();

    if (pRowId >= M || pColId >= N) {
        return;
    }

    const int warpId = tensorCoreConfig.globalWarpId();
    const int numData = matrixTileIndex[warpId + 1] - matrixTileIndex[warpId];
    if (numData <= 0) {
        return;
    }

    // Compute dense matrix multiplication using Tensor core
    matrixTileMultiplicationUseTensorCore_coo(tensorCoreConfig,
                                              pRowId,
                                              pColId,
                                              M,
                                              N,
                                              K,
                                              nnz,
                                              matrixA,
                                              matrixB,
                                              matrixSRowIndex,
                                              matrixSColIndex,
                                              matrixTileIndex,
                                              matrixS,
                                              matrixP);
//    const int ldp = N;
//    const auto pOffsetPtr = matrixP + pRowId * ldp + pColId;
//    const float sparsity = (WMMA_M * WMMA_N - numData) / WMMA_M * WMMA_N;
//    if (sparsity < 0) {
//        matrixTileMultiplicationUseCudaCode(pRowId, pColId, M, N, K, matrixA, matrixB, matrixS, matrixP);
//    } else {
//        matrixTileMultiplicationUseTensorCore_coo(tensorCoreConfig,
//                                                  pRowId,
//                                                  pColId,
//                                                  M,
//                                                  N,
//                                                  K,
//                                                  nnz,
//                                                  matrixA,
//                                                  matrixB,
//                                                  matrixSRowIndex,
//                                                  matrixSColIndex,
//                                                  matrixTileMappedToWarpIndex,
//                                                  matrixS,
//                                                  matrixP);
//    }

}

__global__ void sddmm_gpu_coo_2(TensorCoreConfig tensorCoreConfig,
                                const UIN M, const UIN N, const UIN K, const UIN nnz,
                                const half *matrixA, const half *matrixB,
                                const UIN *matrixSRowIndex,
                                const UIN *matrixSColIndex,
                                const float *matrixS,
                                const UIN *matrixSTileMappedToWarpIndex,
                                const UIN *matrixSTileMappedToWarpIndexData,
                                float *matrixP) {
    tensorCoreConfig.initByKernel(blockIdx, blockDim, threadIdx);

    const UIN pRowId = tensorCoreConfig.rowBeginOfTile();
    const UIN pColId = tensorCoreConfig.colBeginOfTile();

    if (pRowId >= M || pColId >= N) {
        return;
    }

    const int globalWarpId = tensorCoreConfig.globalWarpId();

    const int tileIndexBegin = matrixSTileMappedToWarpIndex[globalWarpId];
    const int tileIndexEnd = matrixSTileMappedToWarpIndex[globalWarpId + 1];
    const int numData = tileIndexEnd - tileIndexBegin;
    if (numData <= 0) {
        return;
    }

    // Leading dimensions. Packed with no transpositions.
    const UIN lda = K;
    const UIN ldb = N;

    nvcuda::wmma::fragment<nvcuda::wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE, nvcuda::wmma::row_major>
        aFrag;
    nvcuda::wmma::fragment<nvcuda::wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE, nvcuda::wmma::row_major>
        bFrag;

    nvcuda::wmma::fragment<nvcuda::wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    // Loop over k
    for (int kIter = 0; kIter < K; kIter += WMMA_K) {
        const int aRowId = pRowId;
        const int aColId = kIter;

        const int bRowId = kIter;
        const int bColId = pColId;

        // Bounds checking
        if (aRowId < M && aColId < K && bRowId < K && bColId < N) {
            const auto aOffsetPtr = matrixA + aRowId * lda + aColId;
            const auto bOffsetPtr = matrixB + bRowId * ldb + bColId;

            nvcuda::wmma::load_matrix_sync(aFrag, aOffsetPtr, lda);
            nvcuda::wmma::load_matrix_sync(bFrag, bOffsetPtr, ldb);

            nvcuda::wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
        }
    }

    const int laneId = tensorCoreConfig.laneId();

    for (int tileIndexDataIdx = tileIndexBegin; tileIndexDataIdx < tileIndexEnd; ++tileIndexDataIdx) {
        const UIN matrixPIdx = matrixSTileMappedToWarpIndexData[tileIndexDataIdx];
        const UIN curRow = matrixSRowIndex[matrixPIdx];
        const UIN curCol = matrixSColIndex[matrixPIdx];

        FragmentInformation fragmentInformation;
        tensorCoreConfig.positionCalculator(pRowId, pColId, curRow, curCol, fragmentInformation);

//        if (matrixPIdx == 160 && globalWarpId == 0 && laneId == 0) {
//            printf(" globalWarpId = %d "
//                   " pRowId = %d, pColId = %d, curRow = %d, curCol = %d, curValue = %f"
//                   " laneId = %d findLaneId = %d, findIdx = %d, cFrag.x[%d] = %f\n",
//                   globalWarpId,
//                   static_cast<int>(pRowId),
//                   static_cast<int>(pColId),
//                   static_cast<int>(curRow),
//                   static_cast<int>(curCol),
//                   static_cast<float>(matrixS[matrixPIdx]),
//                   laneId,
//                   fragmentInformation.laneId_,
//                   fragmentInformation.index_,
//                   fragmentInformation.index_,
//                   static_cast<float>(cFrag.x[fragmentInformation.laneId_]));
//        }
        if (laneId == fragmentInformation.laneId_) {
            matrixP[matrixPIdx] = cFrag.x[fragmentInformation.index_];
//            printf(
//                " pRowId = %d, pColId = %d, curRow = %d, curCol = %d, findLaneId = %d, findIdx = %d, cFrag.x[%d] = %f\n",
//                static_cast<int>(pRowId),
//                static_cast<int>(pColId),
//                static_cast<int>(curRow),
//                static_cast<int>(curCol),
//                findLaneId,
//                findIdx,
//                findIdx,
//                static_cast<float>(cFrag.x[findIdx]));
        }
    }

}

__global__ void sddmm_gpu_coo_3(TensorCoreConfig tensorCoreConfig,
                                const UIN M, const UIN N, const UIN K, const UIN nnz,
                                const half *matrixA, const half *matrixB,
                                const UIN *matrixSRowIndex,
                                const UIN *matrixSColIndex,
                                const float *matrixS,
                                const UIN *matrixSTileMappedToWarpIndex,
                                float *matrixP) {
    tensorCoreConfig.initByKernel(blockIdx, blockDim, threadIdx);

    const UIN pRowId = tensorCoreConfig.rowBeginOfTile();
    const UIN pColId = tensorCoreConfig.colBeginOfTile();

    if (pRowId >= M || pColId >= N) {
        return;
    }

    const int globalWarpId = tensorCoreConfig.globalWarpId();

    const int tileIndexBegin = matrixSTileMappedToWarpIndex[globalWarpId];
    const int tileIndexEnd = matrixSTileMappedToWarpIndex[globalWarpId + 1];
    const int numData = tileIndexEnd - tileIndexBegin;
    if (numData <= 0) {
        return;
    }

    // Leading dimensions. Packed with no transpositions.
    const UIN lda = K;
    const UIN ldb = N;

    nvcuda::wmma::fragment<nvcuda::wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE, nvcuda::wmma::row_major>
        aFrag;
    nvcuda::wmma::fragment<nvcuda::wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE, nvcuda::wmma::row_major>
        bFrag;

    nvcuda::wmma::fragment<nvcuda::wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    // Loop over k
    for (int kIter = 0; kIter < K; kIter += WMMA_K) {
        const int aRowId = pRowId;
        const int aColId = kIter;

        const int bRowId = kIter;
        const int bColId = pColId;

        // Bounds checking
        if (aRowId < M && aColId < K && bRowId < K && bColId < N) {
            const auto aOffsetPtr = matrixA + aRowId * lda + aColId;
            const auto bOffsetPtr = matrixB + bRowId * ldb + bColId;

            nvcuda::wmma::load_matrix_sync(aFrag, aOffsetPtr, lda);
            nvcuda::wmma::load_matrix_sync(bFrag, bOffsetPtr, ldb);

            nvcuda::wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
        }
    }

    const int laneId = tensorCoreConfig.laneId();

    for (int tileIndexDataIdx = tileIndexBegin; tileIndexDataIdx < tileIndexEnd; ++tileIndexDataIdx) {
        const UIN matrixPIdx = tileIndexDataIdx;
        const UIN curRow = matrixSRowIndex[matrixPIdx];
        const UIN curCol = matrixSColIndex[matrixPIdx];

        FragmentInformation fragmentInformation;
        tensorCoreConfig.positionCalculator(pRowId, pColId, curRow, curCol, fragmentInformation);

        if (laneId == fragmentInformation.laneId_) {
            matrixP[matrixPIdx] = cFrag.x[fragmentInformation.index_];
        }
    }

}
#include <cstdio>

#include <mma.h>

#include "sddmmKernel.cuh"
#include "TensorCoreConfig.cuh"
#include "ReBELL.hpp"
#include "CudaTimeCalculator.cuh"

namespace kernel {

using namespace nvcuda;

__global__ void checkFragmentData() {
    constexpr UIN wmmaM = 16;
    constexpr UIN wmmaN = 16;
    constexpr UIN wmmaK = 8;
    using matrixAType = float;
    using matrixBType = float;
    using matrixATypeFragment = wmma::precision::tf32;
    using matrixBTypeFragment = wmma::precision::tf32;

    constexpr UIN aTileSize = wmmaM * wmmaK;
    constexpr UIN bTileSize = wmmaK * wmmaN;

    constexpr UIN bRow = wmmaN;
    constexpr UIN bCol = wmmaK;

    constexpr UIN ldATile = wmmaK;
    constexpr UIN ldBTile = wmmaK;

    __shared__ matrixAType aTileSMEM[aTileSize];
    __shared__ matrixBType bTileSMEM[bTileSize];

    const UIN warpId = threadIdx.x / WARP_SIZE;
    const UIN laneId = threadIdx.x % WARP_SIZE;

    if (warpId == 0 && laneId == 0) {
        for (int i = 0; i < aTileSize; ++i) {
            aTileSMEM[i] = static_cast<matrixAType>(i);

        }

//        int row = 0;
//        int col = 0;
//        for (int i = 0; i < bTileSize; ++i) {
//            row %= wmmaK;
//            bTileSMEM[i] = static_cast<matrixBType>(row * wmmaK + col);
//            ++row;
//            if (i % ldBTile == 0) {
//                ++col;
//            }
//        }
        if (bRow == wmmaK) {
            for (int i = 0; i < bTileSize; ++i) {
                bTileSMEM[i] = static_cast<matrixBType>(i);
            }
        } else {
            for (int row = 0; row < wmmaK; ++row) {
                for (int col = 0; col < wmmaN; ++col) {
                    bTileSMEM[row + col * ldBTile] = static_cast<matrixBType>(row * wmmaN + col);
                }
            }
        }
    }

    if (warpId == 0 && laneId == 0) {
        printf("\nmatrix A data : \n");
        printf("| |");
        for (int col = 0; col < wmmaK; ++col) {
            printf("%d|", col);
        }
        printf("\n");

        printf("|");
        for (int i = 0; i < wmmaK + 1; ++i) {
            printf("-|");
        }
        printf("\n");

        for (int row = 0; row < wmmaM; ++row) {
            printf("|%d|", row);
            for (int col = 0; col < wmmaK; ++col) {
                printf("%.0f|", static_cast<float>(aTileSMEM[row * wmmaK + col]));
            }
            printf("\n");
        }

        printf("\nmatrix B data : ");
        if (ldBTile == wmmaN) { printf("(rwo major)\n"); } else { printf("(column major)\n"); }
        printf("| |");
        for (int col = 0; col < bCol; ++col) {
            printf("%d|", col);
        }
        printf("\n");

        printf("|");
        for (int i = 0; i < bCol + 1; ++i) {
            printf("-|");
        }
        printf("\n");

        for (int row = 0; row < bRow; ++row) {
            printf("|%d|", row);
            for (int col = 0; col < bCol; ++col) {
                printf("%.0f|", static_cast<float>(bTileSMEM[row * ldBTile + col]));
            }
            printf("\n");
        }
        printf("\n");

        printf("\nmatrix C data : \n");
        printf("| |");
        for (int col = 0; col < wmmaN; ++col) {
            printf("%d|", col);
        }
        printf("\n");

        printf("|");
        for (int i = 0; i < wmmaN + 1; ++i) {
            printf("-|");
        }
        printf("\n");

        for (int row = 0; row < wmmaM; ++row) {
            printf("|%d|", row);
            for (int col = 0; col < wmmaN; ++col) {
                float c = 0.0f;
                for (int k = 0; k < wmmaK; ++k) {
                    const float a = aTileSMEM[row * ldATile + k];
                    const float b = bTileSMEM[k + col * ldBTile];
                    c += a * b;
                }
                printf("%.0f|", static_cast<float>(c));
            }
            printf("\n");
        }
        printf("\n");
    }

    if (warpId == 0) {
        wmma::fragment<wmma::matrix_a, wmmaM, wmmaN, wmmaK, matrixATypeFragment, wmma::row_major> aFrag;
        wmma::fragment<wmma::matrix_b, wmmaM, wmmaN, wmmaK, matrixBTypeFragment, wmma::col_major> bFrag;

        wmma::fragment<wmma::accumulator, wmmaM, wmmaN, wmmaK, float> cFrag;

        fill_fragment(cFrag, 0.0f);

        wmma::load_matrix_sync(aFrag, aTileSMEM, ldATile);
        wmma::load_matrix_sync(bFrag, bTileSMEM, ldBTile);

        wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);

        if (laneId == 0) {
            printf("\nFragment A tiled data : \n");
        }
        for (int laneIdx = 0; laneIdx < WARP_SIZE; ++laneIdx) {
            if (warpId == 0 && laneId == laneIdx) {
                printf("|T%d|", laneId);
                for (int idxOfFragment = 0; idxOfFragment < aFrag.num_elements; ++idxOfFragment) {
                    printf("%.0f|", static_cast<float>(aFrag.x[idxOfFragment]));
                }
                printf("\n");
            }
        }

        if (laneId == 0) {
            printf("\nFragment B tiled data : \n");
        }
        for (int laneIdx = 0; laneIdx < WARP_SIZE; ++laneIdx) {
            if (warpId == 0 && laneId == laneIdx) {
                printf("|T%d|", laneId);
                for (int idxOfFragment = 0; idxOfFragment < bFrag.num_elements; ++idxOfFragment) {
                    printf("%.0f|", static_cast<float>(bFrag.x[idxOfFragment]));
                }
                printf("\n");
            }
        }

        if (laneId == 0) {
            printf("\nFragment C tiled data : \n");
        }
        for (int laneIdx = 0; laneIdx < WARP_SIZE; ++laneIdx) {
            if (warpId == 0 && laneId == laneIdx) {
                printf("|T%d|", laneId);
                for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
                    printf("%.0f|", static_cast<float>(cFrag.x[idxOfFragment]));
                }
                printf("\n");
            }
        }
    }
}

template<typename T>
__global__ void convertDataType(const UIN n, const float *in, T *out) {
    const UIN idx = blockDim.x * blockIdx.x + threadIdx.x;
    if (idx < n) {
        out[idx] = static_cast<T>(in[idx]);
//        printf("in[%d] = %f, static_cast<float>out[%d] = %f\n", idx, in[idx], idx, static_cast<float>(out[idx]));
    }
}

template __global__ void convertDataType<int>(const UIN n, const float *in, int *out);
template __global__ void convertDataType<float>(const UIN n, const float *in, float *out);
template __global__ void convertDataType<double>(const UIN n, const float *in, double *out);
template __global__ void convertDataType<half>(const UIN n, const float *in, half *out);

// m16n16k16
// blockDim: [64, 1, 1]
__global__ void sddmm_gpu_rebell_m16n16k16_block64_rowPanel_matrixA_rowMaj_matrixB_rowMaj(const UIN M,
                                                                                          const UIN N,
                                                                                          const UIN K,
                                                                                          const MATRIX_A_TYPE *matrixA,
                                                                                          const MATRIX_B_TYPE *matrixB,
                                                                                          const UIN numNonZeroRow,
                                                                                          const UIN *reorderedRows,
                                                                                          const UIN *reorderedCols,
                                                                                          const UIN *reorderedColOffset,
                                                                                          const UIN *blockRowOffsets,
                                                                                          const UIN *blockValues,
                                                                                          MATRIX_C_TYPE *matrixP) {
    constexpr int aTileSMEMSize = WMMA_M * WMMA_N;
    constexpr int bTileSMEMSize = WMMA_K * WMMA_N * 2;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::row_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    const UIN laneId = threadIdx.x % WARP_SIZE;
    const UIN warpId = threadIdx.x / WARP_SIZE;

    const UIN rowPanelId = blockIdx.x;

    const UIN lda = K;
    const UIN ldb = N;

    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];
    for (int colBlockIter = 0; colBlockIter < numColBlocksCurrentRowPanel; colBlockIter += 2) {

        // Data needs to be reset to zero before calculating the next column block
        fill_fragment(cFrag, 0.0f);

        const UIN colBlockId = colBlockIter + warpId;
        const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

        const UIN startIndexOfReorderedColsCurrentIter =
            reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockIter;
        const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

        // Loop over K
        for (int kIter = 0; kIter < K; kIter += WMMA_K) {
            // Load matrix A into shared memory, each thread loads 4 elements, conflict-free access
#pragma unroll
            for (int iter = 0; iter < 4; ++iter) {
                const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 8) + (laneId / 16) + (iter * 2);
                const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
                const UIN aColId = kIter + laneId % 16;

                aTileSMEM[warpId * 128 + iter * 32 + laneId] =
                    (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
            }

            // Load matrix B data into shared memory, each thread loads 8 elements, conflict-free access
            const UIN reorderedColIndex = startIndexOfReorderedColsCurrentIter + laneId;
#pragma unroll
            for (int iter = 0; iter < 8; ++iter) {
                const UIN bRowId = kIter + warpId * 8 + iter;
                const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                    reorderedCols[reorderedColIndex] : N;

                bTileSMEM[warpId * 256 + iter * 32 + laneId] =
                    (bRowId < K && bColId < N) ? matrixB[bRowId * ldb + bColId] : static_cast<MATRIX_B_TYPE>(0);
            }
            __syncthreads();

            // Compute the matrix multiplication
            if (colBlockId < numColBlocksCurrentRowPanel) {
                wmma::load_matrix_sync(aFrag, aTileSMEM, WMMA_N);
                wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * WMMA_N, WMMA_N * 2);
                wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
            }

            __syncthreads();
        }

        // Store the result
        if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
            for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
                UIN localRow, localCol;
                calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

                const UIN idxOfMatrixP =
                    blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

                // Saved when the value is not 0
                if (idxOfMatrixP != NULL_VALUE) {
                    matrixP[idxOfMatrixP] = cFrag.x[idxOfFragment];
                }
            }
        }
        __syncthreads();
    }
}

// m16n16k16
// blockDim: [64, 1, 1]
// 一个thread block负责一个row panel
__global__ void sddmm_gpu_rebell_m16n16k16_block64_rowPanel_matrixA_rowMaj_matrixB_colMaj(const UIN M,
                                                                                          const UIN N,
                                                                                          const UIN K,
                                                                                          const MATRIX_A_TYPE *matrixA,
                                                                                          const MATRIX_B_TYPE *matrixB,
                                                                                          const UIN numNonZeroRow,
                                                                                          const UIN *reorderedRows,
                                                                                          const UIN *reorderedCols,
                                                                                          const UIN *reorderedColOffset,
                                                                                          const UIN *blockRowOffsets,
                                                                                          const UIN *blockValues,
                                                                                          MATRIX_C_TYPE *matrixP) {
    constexpr int aTileSMEMSize = WMMA_M * WMMA_N;
    constexpr int bTileSMEMSize = WMMA_K * WMMA_N * 2;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::row_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    const UIN laneId = threadIdx.x % WARP_SIZE;
    const UIN warpId = threadIdx.x / WARP_SIZE;

    const UIN rowPanelId = blockIdx.x;

    const UIN lda = K;
    const UIN ldb = K;

    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];
    for (int colBlockIter = 0; colBlockIter < numColBlocksCurrentRowPanel; colBlockIter += 2) {

        // Data needs to be reset to zero before calculating the next column block
        fill_fragment(cFrag, 0.0f);

        const UIN colBlockId = colBlockIter + warpId;
        const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

        const UIN startIndexOfReorderedColsCurrentIter =
            reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockIter;
        const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

        const UIN reorderedColIndex = startIndexOfReorderedColsCurrentIter + laneId;

        // Loop over K
        for (int kIter = 0; kIter < K; kIter += WMMA_K) {
            // Load matrix A into shared memory, each thread loads 4 elements, conflict-free access
#pragma unroll
            for (int iter = 0; iter < 4; ++iter) {
                const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 8) + (laneId / 16) + (iter * 2);
                const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
                const UIN aColId = kIter + laneId % 16;

                aTileSMEM[warpId * 128 + iter * 32 + laneId] =
                    (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
            }

            // Load matrix B data into shared memory, each thread loads 8 elements, conflict-free access
#pragma unroll
            for (int iter = 0; iter < 8; ++iter) {
                const UIN bRowId = kIter + warpId * 8 + iter;
                const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                    reorderedCols[reorderedColIndex] : N;

                bTileSMEM[warpId * 256 + iter * 32 + laneId] =
                    (bRowId < K && bColId < N) ? matrixB[bRowId + bColId * ldb] : static_cast<MATRIX_B_TYPE>(0);
            }
            __syncthreads();

            // Compute the matrix multiplication
            if (colBlockId < numColBlocksCurrentRowPanel) {
                wmma::load_matrix_sync(aFrag, aTileSMEM, WMMA_K);
                wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * WMMA_N, WMMA_N * 2);
                wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
            }

            __syncthreads();
        }

        // Store the result
        if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
            for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
                UIN localRow, localCol;
                calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

                const UIN idxOfMatrixP =
                    blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

                // Saved when the value is not 0
                if (idxOfMatrixP != NULL_VALUE) {
                    matrixP[idxOfMatrixP] = cFrag.x[idxOfFragment];
                }
            }
        }
        __syncthreads();
    }
}

// m16n16k16
// blockDim: [64, 1, 1]
// 一个thread block负责一个row panel中的2个col block
__global__ void sddmm_gpu_rebell_m16n16k16_block64_matrixA_rowMaj_matrixB_rowMaj(const UIN M,
                                                                                 const UIN N,
                                                                                 const UIN K,
                                                                                 const MATRIX_A_TYPE *matrixA,
                                                                                 const MATRIX_B_TYPE *matrixB,
                                                                                 const UIN numNonZeroRow,
                                                                                 const UIN *reorderedRows,
                                                                                 const UIN *reorderedCols,
                                                                                 const UIN *reorderedColOffset,
                                                                                 const UIN *blockRowOffsets,
                                                                                 const UIN *blockValues,
                                                                                 MATRIX_C_TYPE *matrixP) {
    constexpr int aTileSMEMSize = WMMA_M * WMMA_N;
    constexpr int bTileSMEMSize = WMMA_K * WMMA_N * 2;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::row_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    const UIN laneId = threadIdx.x % WARP_SIZE;
    const UIN warpId = threadIdx.x / WARP_SIZE;

    const UIN rowPanelId = blockIdx.x;
    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];

    const UIN colBlockIter = blockIdx.y;
    if (colBlockIter >= numColBlocksCurrentRowPanel) {
        return;
    }

    const UIN colBlockId = colBlockIter + warpId;
    const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

    const UIN startIndexOfReorderedColsCurrentIter = reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockIter;
    const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

    const UIN reorderedColIndex = startIndexOfReorderedColsCurrentIter + laneId;

    const UIN lda = K;
    const UIN ldb = N;

    // Loop over K
    for (int kIter = 0; kIter < K; kIter += WMMA_K) {
        // Load matrix A into shared memory, each thread loads 4 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 4; ++iter) {
            const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 8) + (laneId / 16) + (iter * 2);
            const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
            const UIN aColId = kIter + laneId % 16;

            aTileSMEM[warpId * 128 + iter * 32 + laneId] =
                (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
        }

        // Load matrix B data into shared memory, each thread loads 8 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 8; ++iter) {
            const UIN bRowId = kIter + warpId * 8 + iter;
            const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                reorderedCols[reorderedColIndex] : N;

            bTileSMEM[warpId * 256 + iter * 32 + laneId] =
                (bRowId < K && bColId < N) ? matrixB[bRowId * ldb + bColId] : static_cast<MATRIX_B_TYPE>(0);
        }
        __syncthreads();

        // Compute the matrix multiplication
        if (colBlockId < numColBlocksCurrentRowPanel) {
            wmma::load_matrix_sync(aFrag, aTileSMEM, WMMA_K);
            wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * WMMA_N, WMMA_N * 2);
            wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
        }

        __syncthreads();
    }

    // Store the result
    if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
        for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
            UIN localRow, localCol;
            calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

            const UIN idxOfMatrixP =
                blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

            // Saved when the value is not 0
            if (idxOfMatrixP != NULL_VALUE) {
                matrixP[idxOfMatrixP] = cFrag.x[idxOfFragment];
            }
        }
    }
}

// m16n16k16
// blockDim: [64, 1, 1]
// 一个thread block负责一个row panel中的2个col block
__global__ void sddmm_gpu_rebell_m16n16k16_block64_matrixA_rowMaj_matrixB_colMaj(const UIN M,
                                                                                 const UIN N,
                                                                                 const UIN K,
                                                                                 const MATRIX_A_TYPE *matrixA,
                                                                                 const MATRIX_B_TYPE *matrixB,
                                                                                 const UIN numNonZeroRow,
                                                                                 const UIN *reorderedRows,
                                                                                 const UIN *reorderedCols,
                                                                                 const UIN *reorderedColOffset,
                                                                                 const UIN *blockRowOffsets,
                                                                                 const UIN *blockValues,
                                                                                 MATRIX_C_TYPE *matrixP) {
    constexpr int eachThreadBlockCountsTheNumberOfColBlocks = 2;

    constexpr int aTileSMEMSize = WMMA_M * WMMA_N;
    constexpr int bTileSMEMSize = WMMA_K * WMMA_N * eachThreadBlockCountsTheNumberOfColBlocks;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::row_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    const UIN laneId = threadIdx.x % WARP_SIZE;
    const UIN warpId = threadIdx.x / WARP_SIZE;

    const UIN rowPanelId = blockIdx.x;
    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];

    const UIN colBlockIter = blockIdx.y * eachThreadBlockCountsTheNumberOfColBlocks;
    if (colBlockIter >= numColBlocksCurrentRowPanel) {
        return;
    }

    const UIN colBlockId = colBlockIter + warpId;
    const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

    const UIN startIndexOfReorderedColsCurrentIter = reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockIter;
    const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

    const UIN reorderedColIndex = startIndexOfReorderedColsCurrentIter + laneId;

    const UIN lda = K;
    const UIN ldb = K;

    // Loop over K
    for (int kIter = 0; kIter < K; kIter += WMMA_K) {
        // Load matrix A into shared memory, each thread loads 4 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 4; ++iter) {
            const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 8) + (laneId / 16) + (iter * 2);
            const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
            const UIN aColId = kIter + laneId % 16;

            aTileSMEM[warpId * 128 + iter * 32 + laneId] =
                (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
        }

        // Load matrix B data into shared memory, each thread loads 8 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 8; ++iter) {
            const UIN bRowId = kIter + warpId * 8 + iter;
            const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                reorderedCols[reorderedColIndex] : N;

            bTileSMEM[warpId * 256 + iter * 32 + laneId] =
                (bRowId < K && bColId < N) ? matrixB[bRowId + bColId * ldb] : static_cast<MATRIX_B_TYPE>(0);
        }
        __syncthreads();

        // Compute the matrix multiplication
        if (colBlockId < numColBlocksCurrentRowPanel) {
            wmma::load_matrix_sync(aFrag, aTileSMEM, WMMA_K);
            wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * WMMA_N, WMMA_N * 2);
            wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
        }

        __syncthreads();
    }

    // Store the result
    if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
        for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
            UIN localRow, localCol;
            calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

            const UIN idxOfMatrixP =
                blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

            // Saved when the value is not 0
            if (idxOfMatrixP != NULL_VALUE) {
                matrixP[idxOfMatrixP] = cFrag.x[idxOfFragment];
            }
        }
    }
}

// m16n16k16
// blockDim: [128, 1, 1]
// 一个thread block负责一个row panel中的4个col block
__global__ void sddmm_gpu_rebell_m16n16k16_block128_matrixA_rowMaj_matrixB_colMaj(const UIN M,
                                                                                  const UIN N,
                                                                                  const UIN K,
                                                                                  const MATRIX_A_TYPE *__restrict__ matrixA,
                                                                                  const MATRIX_B_TYPE *__restrict__ matrixB,
                                                                                  const float alpha, const float beta,
                                                                                  const UIN numNonZeroRow,
                                                                                  const UIN *__restrict__ reorderedRows,
                                                                                  const UIN *__restrict__ reorderedCols,
                                                                                  const UIN *__restrict__ reorderedColOffset,
                                                                                  const UIN *__restrict__ blockRowOffsets,
                                                                                  const UIN *__restrict__ blockValues,
                                                                                  MATRIX_C_TYPE *matrixP) {
    constexpr int eachThreadBlockCountsTheNumberOfColBlocks = 4;

    constexpr int aTileSMEMSize = (WMMA_M * WMMA_N) * 2;
    constexpr int bTileSMEMSize = (WMMA_K * WMMA_N * eachThreadBlockCountsTheNumberOfColBlocks) * 2;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::col_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    const UIN laneId = threadIdx.x & 31;
    const UIN warpId = threadIdx.x >> 5;

    const UIN rowPanelId = blockIdx.x;
    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];

    const UIN colBlockIter = blockIdx.y * eachThreadBlockCountsTheNumberOfColBlocks;
    if (colBlockIter >= numColBlocksCurrentRowPanel) {
        return;
    }

    const UIN colBlockId = colBlockIter + warpId;
    const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

    const UIN startIndexOfReorderedColsCurrentColBlock = reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockId;
    const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

    const UIN lda = K;
    const UIN ldb = K;

    // Loop over K
    for (int kIter = 0; kIter < K; kIter += WMMA_K * 2) {
        // Load matrix A into shared memory, each thread loads 4 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 4; ++iter) {
            const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 4) + iter;
            const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
            const UIN aColId = kIter + laneId;

            aTileSMEM[warpId * 128 + iter * 32 + laneId] =
                (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
        }

        // Load matrix B data into shared memory, each thread loads 16 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 16; ++iter) {
            const UIN bRowId = kIter + laneId;
            const UIN reorderedColIndex = startIndexOfReorderedColsCurrentColBlock + iter;
            const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                reorderedCols[reorderedColIndex] : N;

            bTileSMEM[warpId * 512 + iter * 32 + laneId] =
                (bRowId < K && bColId < N) ? matrixB[bRowId + bColId * ldb] : static_cast<MATRIX_B_TYPE>(0);
        }

        __syncthreads();

        // Compute the matrix multiplication
        for (int iter = 0; iter < 2; ++iter) {
            if (colBlockId < numColBlocksCurrentRowPanel) {
                wmma::load_matrix_sync(aFrag, aTileSMEM + iter * WMMA_K, WMMA_K * 2);
                wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * 512 + iter * WMMA_K, WMMA_K * 2);
                wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
            }
        }

        __syncthreads();
    }

    // Store the result
    if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
        for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
            const float c = alpha * cFrag.x[idxOfFragment];

            UIN localRow, localCol;
            calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

            const UIN idxOfMatrixP =
                blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

            // Saved when the value is not 0
            if (idxOfMatrixP != NULL_VALUE) {
                matrixP[idxOfMatrixP] = c + beta * matrixP[idxOfFragment];
            }
        }
    }
}

// m16n16k16
// blockDim: [256, 1, 1]
// 一个thread block负责一个row panel中的8个col block
__global__ void sddmm_gpu_rebell_m16n16k16_block256_matrixA_rowMaj_matrixB_rowMaj(const UIN M,
                                                                                  const UIN N,
                                                                                  const UIN K,
                                                                                  const MATRIX_A_TYPE *__restrict__ matrixA,
                                                                                  const MATRIX_B_TYPE *__restrict__ matrixB,
                                                                                  const float alpha, const float beta,
                                                                                  const UIN numNonZeroRow,
                                                                                  const UIN *__restrict__ reorderedRows,
                                                                                  const UIN *__restrict__ reorderedCols,
                                                                                  const UIN *__restrict__ reorderedColOffset,
                                                                                  const UIN *__restrict__ blockRowOffsets,
                                                                                  const UIN *__restrict__ blockValues,
                                                                                  MATRIX_C_TYPE *matrixP) {
    constexpr int number_of_tiles_loaded_in_one_cycle = 32 / WMMA_K;

    constexpr int aTileSMEMSize = (WMMA_M * WMMA_K) * number_of_tiles_loaded_in_one_cycle;
    constexpr int bTileSMEMSize = (WMMA_K * WMMA_N * each_thread_block_counts_the_number_Of_col_blocks)
        * number_of_tiles_loaded_in_one_cycle;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::col_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    const UIN laneId = threadIdx.x & 31;
    const UIN warpId = threadIdx.x >> 5;

    const UIN rowPanelId = blockIdx.x;
    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];

    const UIN colBlockIter = blockIdx.y * each_thread_block_counts_the_number_Of_col_blocks;
    if (colBlockIter >= numColBlocksCurrentRowPanel) {
        return;
    }

    const UIN colBlockId = colBlockIter + warpId;
    const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

    const UIN startIndexOfReorderedColsCurrentColBlock = reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockId;
    const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

    const UIN lda = K;
    const UIN ldb = N;

    // Loop over K, one iteration 32
    for (int kIter = 0; kIter < K; kIter += 32) {
        // Load matrix A into shared memory, each thread loads 2 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 2; ++iter) {
            const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 2) + iter;
            const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
            const UIN aColId = kIter + laneId;

            aTileSMEM[warpId * 64 + iter * 32 + laneId] =
                (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
        }

        // Load matrix B data into shared memory, each thread loads 16 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 16; ++iter) {
            const UIN bRowId = kIter + laneId;
            const UIN reorderedColIndex = startIndexOfReorderedColsCurrentColBlock + iter;
            const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                reorderedCols[reorderedColIndex] : N;

            bTileSMEM[warpId * 512 + iter * 32 + laneId] =
                (bRowId < K && bColId < N) ? matrixB[bRowId * ldb + bColId] : static_cast<MATRIX_B_TYPE>(0);
        }

        __syncthreads();

        // Compute the matrix multiplication
        for (int iter = 0; iter < 32; iter += WMMA_K) {
            if (colBlockId < numColBlocksCurrentRowPanel) {
                wmma::load_matrix_sync(aFrag, aTileSMEM + iter, 32);
                wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * 512 + iter, 32);
                wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
            }
        }

        __syncthreads();
    }

    // Store the result
    if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
        for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
            const float c = alpha * cFrag.x[idxOfFragment];

            UIN localRow, localCol;
            calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

            const UIN idxOfMatrixP =
                blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

            // Saved when the value is not 0
            if (idxOfMatrixP != NULL_VALUE) {
                matrixP[idxOfMatrixP] = c + beta * matrixP[idxOfFragment];
            }

        }
    }
}

// m16n16k16
// blockDim: [256, 1, 1]
// 一个thread block负责一个row panel中的8个col block
__global__ void sddmm_gpu_rebell_m16n16k16_block256_matrixA_rowMaj_matrixB_colMaj(const UIN M,
                                                                                  const UIN N,
                                                                                  const UIN K,
                                                                                  const MATRIX_A_TYPE *__restrict__ matrixA,
                                                                                  const MATRIX_B_TYPE *__restrict__ matrixB,
                                                                                  const float alpha, const float beta,
                                                                                  const UIN numNonZeroRow,
                                                                                  const UIN *__restrict__ reorderedRows,
                                                                                  const UIN *__restrict__ reorderedCols,
                                                                                  const UIN *__restrict__ reorderedColOffset,
                                                                                  const UIN *__restrict__ blockRowOffsets,
                                                                                  const UIN *__restrict__ blockValues,
                                                                                  MATRIX_C_TYPE *matrixP) {
    constexpr int number_of_tiles_loaded_in_one_cycle = 32 / WMMA_K;

    constexpr int aTileSMEMSize = (WMMA_M * WMMA_K) * number_of_tiles_loaded_in_one_cycle;
    constexpr int bTileSMEMSize = (WMMA_K * WMMA_N * each_thread_block_counts_the_number_Of_col_blocks)
        * number_of_tiles_loaded_in_one_cycle;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::col_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    const UIN laneId = threadIdx.x & 31;
    const UIN warpId = threadIdx.x >> 5;

    const UIN rowPanelId = blockIdx.x;
    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];

    const UIN colBlockIter = blockIdx.y * each_thread_block_counts_the_number_Of_col_blocks;
    if (colBlockIter >= numColBlocksCurrentRowPanel) {
        return;
    }

    const UIN colBlockId = colBlockIter + warpId;
    const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

    const UIN startIndexOfReorderedColsCurrentColBlock = reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockId;
    const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

    const UIN lda = K;
    const UIN ldb = K;

    // Loop over K, one iteration 32
    for (int kIter = 0; kIter < K; kIter += 32) {
        // Load matrix A into shared memory, each thread loads 2 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 2; ++iter) {
            const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 2) + iter;
            const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
            const UIN aColId = kIter + laneId;

            aTileSMEM[warpId * 64 + iter * 32 + laneId] =
                (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
        }

        // Load matrix B data into shared memory, each thread loads 16 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 16; ++iter) {
            const UIN bRowId = kIter + laneId;
            const UIN reorderedColIndex = startIndexOfReorderedColsCurrentColBlock + iter;
            const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                reorderedCols[reorderedColIndex] : N;

            bTileSMEM[warpId * 512 + iter * 32 + laneId] =
                (bRowId < K && bColId < N) ? matrixB[bRowId + bColId * ldb] : static_cast<MATRIX_B_TYPE>(0);
        }

        __syncthreads();

        // Compute the matrix multiplication
        for (int iter = 0; iter < 32; iter += WMMA_K) {
            if (colBlockId < numColBlocksCurrentRowPanel) {
                wmma::load_matrix_sync(aFrag, aTileSMEM + iter, 32);
                wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * 512 + iter, 32);
                wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
            }
        }

        __syncthreads();
    }

    // Store the result
    if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
        for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
            const float c = alpha * cFrag.x[idxOfFragment];

            UIN localRow, localCol;
            calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

            const UIN idxOfMatrixP =
                blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

            // Saved when the value is not 0
            if (idxOfMatrixP != NULL_VALUE) {
                matrixP[idxOfMatrixP] = c + beta * matrixP[idxOfFragment];
            }
        }
    }
}

// m16n16k16
// blockDim: [256, 1, 1]
// 一个thread block负责一个row panel中的8个col block
__global__ void sddmm_gpu_rebell_m16n16k8_block256_matrixA_rowMaj_matrixB_colMaj(const UIN M,
                                                                                 const UIN N,
                                                                                 const UIN K,
                                                                                 const MATRIX_A_TYPE *__restrict__ matrixA,
                                                                                 const MATRIX_B_TYPE *__restrict__ matrixB,
                                                                                 const float alpha, const float beta,
                                                                                 const UIN numNonZeroRow,
                                                                                 const UIN *__restrict__ reorderedRows,
                                                                                 const UIN *__restrict__ reorderedCols,
                                                                                 const UIN *__restrict__ reorderedColOffset,
                                                                                 const UIN *__restrict__ blockRowOffsets,
                                                                                 const UIN *__restrict__ blockValues,
                                                                                 MATRIX_C_TYPE *matrixP) {
    constexpr int number_of_tiles_loaded_in_one_cycle = 32 / WMMA_K;

    constexpr int aTileSMEMSize = (WMMA_M * WMMA_K) * number_of_tiles_loaded_in_one_cycle;
    constexpr int bTileSMEMSize = (WMMA_K * WMMA_N * each_thread_block_counts_the_number_Of_col_blocks)
        * number_of_tiles_loaded_in_one_cycle;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::col_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    const UIN laneId = threadIdx.x & 31;
    const UIN warpId = threadIdx.x >> 5;

    const UIN rowPanelId = blockIdx.x;
    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];

    const UIN colBlockIter = blockIdx.y * each_thread_block_counts_the_number_Of_col_blocks;
    if (colBlockIter >= numColBlocksCurrentRowPanel) {
        return;
    }

    const UIN colBlockId = colBlockIter + warpId;
    const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

    const UIN startIndexOfReorderedColsCurrentColBlock = reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockId;
    const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

    const UIN lda = K;
    const UIN ldb = K;

    // Loop over K, one iteration 32
#pragma unroll 2
    for (int kIter = 0; kIter < K; kIter += 32) {
        // Load matrix A into shared memory, each thread loads 2 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 2; ++iter) {
            const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 2) + iter;
            const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
            const UIN aColId = kIter + laneId;

            aTileSMEM[warpId * 64 + iter * 32 + laneId] =
                (aRowId < M && aColId < K) ? (matrixA[aRowId * lda + aColId]) : static_cast<MATRIX_A_TYPE>(0.0f);
        }

        __syncthreads();

        // Load matrix B into shared memory, each thread loads 16 elements, conflict-free access
#pragma unroll 4
        for (int iter = 0; iter < 16; ++iter) {
            const UIN bRowId = kIter + laneId;
            const UIN reorderedColIndex = startIndexOfReorderedColsCurrentColBlock + iter;
            const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                reorderedCols[reorderedColIndex] : N;

            bTileSMEM[warpId * 512 + iter * 32 + laneId] =
                (bRowId < K && bColId < N) ? matrixB[bRowId + bColId * ldb] : static_cast<MATRIX_B_TYPE>(0.0f);
        }

        __syncwarp();

        // Compute the matrix multiplication
#pragma unroll
        for (int iter = 0; iter < 32; iter += WMMA_K) {
            if (colBlockId < numColBlocksCurrentRowPanel) {
                wmma::load_matrix_sync(aFrag, aTileSMEM + iter, 32);
                wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * 512 + iter, 32);

                // Convert to TF32
#pragma unroll
                for (int i = 0; i < aFrag.num_elements; ++i) aFrag.x[i] = wmma::__float_to_tf32(aFrag.x[i]);
#pragma unroll
                for (int i = 0; i < bFrag.num_elements; ++i) bFrag.x[i] = wmma::__float_to_tf32(bFrag.x[i]);

                wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
            }
        }

        __syncthreads();
    }

    // Store the result
    if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
        for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
            const float c = alpha * cFrag.x[idxOfFragment];

            UIN localRow, localCol;
            calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

            const UIN idxOfMatrixP =
                blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

            // Saved when the value is not 0
            if (idxOfMatrixP != NULL_VALUE) {
                matrixP[idxOfMatrixP] = c + beta * matrixP[idxOfFragment];
            }
        }
    }
}

// m16n16k16
// blockDim: [256, 1, 1]
// 一个thread block负责一个row panel中的8个col block
__global__ void sddmm_gpu_rebell_m16n16k8_block256_noSMEM_matrixA_rowMaj_matrixB_colMaj(const UIN M,
                                                                                        const UIN N,
                                                                                        const UIN K,
                                                                                        const MATRIX_A_TYPE *__restrict__ matrixA,
                                                                                        const MATRIX_B_TYPE *__restrict__ matrixB,
                                                                                        const float alpha,
                                                                                        const float beta,
                                                                                        const UIN numNonZeroRow,
                                                                                        const UIN *__restrict__ reorderedRows,
                                                                                        const UIN *__restrict__ reorderedCols,
                                                                                        const UIN *__restrict__ reorderedColOffset,
                                                                                        const UIN *__restrict__ blockRowOffsets,
                                                                                        const UIN *__restrict__ blockValues,
                                                                                        MATRIX_C_TYPE *matrixP) {

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::col_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    const UIN laneId = threadIdx.x & 31;
    const UIN warpId = threadIdx.x >> 5;

    const UIN rowPanelId = blockIdx.x;
    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];

    const UIN colBlockId = blockIdx.y * each_thread_block_counts_the_number_Of_col_blocks + warpId;
    if (colBlockId >= numColBlocksCurrentRowPanel) {
        return;
    }

    const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

    const UIN startIndexOfReorderedColsCurrentColBlock = reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockId;
    const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

    const UIN lda = K;
    const UIN ldb = K;

    // Loop over K, one iteration 8
    for (int kIter = 0; kIter < K; kIter += 8) {

        // Load matrix A
#pragma unroll
        for (int indexOfFragment = 0; indexOfFragment < aFrag.num_elements; ++indexOfFragment) {
            UIN localRow, localCol;
            calculateMatrixAFragmentCoordinates(laneId, indexOfFragment, localRow, localCol);

            const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + localRow;
            const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
            const UIN aColId = kIter + localCol;

            aFrag.x[indexOfFragment] = (aRowId < M && aColId < K) ?
                (matrixA[aRowId * lda + aColId]) : static_cast<MATRIX_A_TYPE>(0.0f);

            if (rowPanelId == 0 && colBlockId == 0) {
                printf(
                    "colBlockId = %d, warpId = %d, laneId = %d, index = %d, localRow = %d, localCol = %d, aRowId = %d, aColId = %d, aFrag.x = %f\n",
                    colBlockId,
                    warpId,
                    laneId,
                    indexOfFragment,
                    localRow,
                    localCol,
                    aRowId,
                    aColId,
                    aFrag.x[indexOfFragment]);
            }
        }

        // Load matrix B
#pragma unroll
        for (int indexOfFragment = 0; indexOfFragment < bFrag.num_elements; ++indexOfFragment) {
            UIN localRow, localCol;
            calculateMatrixBFragmentCoordinates(laneId, indexOfFragment, localRow, localCol);

            const UIN bRowId = kIter + localRow;
            const UIN reorderedColIndex = startIndexOfReorderedColsCurrentColBlock + localCol;
            const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                reorderedCols[reorderedColIndex] : N;

            bFrag.x[indexOfFragment] = (bRowId < K && bColId < N) ?
                matrixB[bRowId + bColId * ldb] : static_cast<MATRIX_B_TYPE>(0.0f);

            if (rowPanelId == 0 && colBlockId == 0) {
                printf(
                    "colBlockId = %d, warpId = %d, laneId = %d, index = %d, localRow = %d, localCol = %d, bRowId = %d, bColId = %d, bFrag.x = %f\n",
                    colBlockId,
                    warpId,
                    laneId,
                    indexOfFragment,
                    localRow,
                    localCol,
                    bRowId,
                    bColId,
                    bFrag.x[indexOfFragment]);
            }
        }

        // Convert to TF32
#pragma unroll
        for (int i = 0; i < aFrag.num_elements; ++i)aFrag.x[i] = wmma::__float_to_tf32(aFrag.x[i]);
#pragma unroll
        for (int i = 0; i < bFrag.num_elements; ++i)bFrag.x[i] = wmma::__float_to_tf32(bFrag.x[i]);

        __syncthreads();

        // Compute the matrix multiplication
        wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);

        __syncthreads();
    }

    // Store the result
#pragma unroll
    for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
        const float c = alpha * cFrag.x[idxOfFragment];

//        if(warpId ==0 && rowPanelId == 0){
//            printf("laneId = %d, idxOfFragment = %d, c = %f\n", laneId, idxOfFragment, c);
//        }

        UIN localRow, localCol;
        calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

        const UIN idxOfMatrixP =
            blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

        // Saved when the value is not 0
        if (idxOfMatrixP != NULL_VALUE) {
            matrixP[idxOfMatrixP] = c + beta * matrixP[idxOfFragment];
        }

        if (idxOfMatrixP == 0) {
            printf("idxOfMatrixP = %d, c = %f, blockIndex = %d \n",
                   idxOfMatrixP,
                   c,
                   startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol);
        }
    }
}

// m16n16k16
// blockDim: [512, 1, 1]
// 一个thread block负责一个row panel中的16个col block
__global__ void sddmm_gpu_rebell_m16n16k16_block512_matrixA_rowMaj_matrixB_colMaj(const UIN M,
                                                                                  const UIN N,
                                                                                  const UIN K,
                                                                                  const MATRIX_A_TYPE *__restrict__ matrixA,
                                                                                  const MATRIX_B_TYPE *__restrict__ matrixB,
                                                                                  const float alpha, const float beta,
                                                                                  const UIN numNonZeroRow,
                                                                                  const UIN *__restrict__ reorderedRows,
                                                                                  const UIN *__restrict__ reorderedCols,
                                                                                  const UIN *__restrict__ reorderedColOffset,
                                                                                  const UIN *__restrict__ blockRowOffsets,
                                                                                  const UIN *__restrict__ blockValues,
                                                                                  MATRIX_C_TYPE *matrixP) {
    constexpr int eachThreadBlockCountsTheNumberOfColBlocks = 16;

    constexpr int aTileSMEMSize = (WMMA_M * WMMA_N) * 2;
    constexpr int bTileSMEMSize = (WMMA_K * WMMA_N * eachThreadBlockCountsTheNumberOfColBlocks) * 2;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::col_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    fill_fragment(cFrag, 0.0f);

    const UIN laneId = threadIdx.x & 31;
    const UIN warpId = threadIdx.x >> 5;

    const UIN rowPanelId = blockIdx.x;
    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];

    const UIN colBlockIter = blockIdx.y * eachThreadBlockCountsTheNumberOfColBlocks;
    if (colBlockIter >= numColBlocksCurrentRowPanel) {
        return;
    }

    const UIN colBlockId = colBlockIter + warpId;
    const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

    const UIN startIndexOfReorderedColsCurrentColBlock = reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockId;
    const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

    const UIN lda = K;
    const UIN ldb = K;

    // Loop over K
    for (int kIter = 0; kIter < K; kIter += WMMA_K * 2) {
        // Load matrix A into shared memory, each thread loads 1 element, conflict-free access
        const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + warpId;
        const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
        const UIN aColId = kIter + laneId;

        aTileSMEM[warpId * 32 + laneId] =
            (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);


        // Load matrix B data into shared memory, each thread loads 16 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < 16; ++iter) {
            const UIN bRowId = kIter + laneId;
            const UIN reorderedColIndex = startIndexOfReorderedColsCurrentColBlock + iter;
            const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                reorderedCols[reorderedColIndex] : N;

            bTileSMEM[warpId * 512 + iter * 32 + laneId] =
                (bRowId < K && bColId < N) ? matrixB[bRowId + bColId * ldb] : static_cast<MATRIX_B_TYPE>(0);
        }
        __syncthreads();

        // Compute the matrix multiplication
        for (int iter = 0; iter < 2; ++iter) {
            if (colBlockId < numColBlocksCurrentRowPanel) {
                wmma::load_matrix_sync(aFrag, aTileSMEM + iter * WMMA_K, WMMA_K * 2);
                wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * 512 + iter * WMMA_K, WMMA_K * 2);
                wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
            }
        }

        __syncthreads();
    }

    // Store the result
    if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
        for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
            const float c = alpha * cFrag.x[idxOfFragment];

            UIN localRow, localCol;
            calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

            const UIN idxOfMatrixP =
                blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

            // Saved when the value is not 0
            if (idxOfMatrixP != NULL_VALUE) {
                matrixP[idxOfMatrixP] = c + beta * matrixP[idxOfFragment];
            }
        }
    }
}

// m16n16k16
// blockDim: [64, 1, 1]
// 在外部进行K迭代
__global__ void sddmm_gpu_rebell_m16n16k16_outkIter_matrixA_rowMaj_matrixB_rowMaj(const UIN M,
                                                                                  const UIN N,
                                                                                  const UIN K,
                                                                                  const UIN kIter,
                                                                                  const MATRIX_A_TYPE *matrixA,
                                                                                  const MATRIX_B_TYPE *matrixB,
                                                                                  const UIN numNonZeroRow,
                                                                                  const UIN *reorderedRows,
                                                                                  const UIN *reorderedCols,
                                                                                  const UIN *reorderedColOffset,
                                                                                  const UIN *blockRowOffsets,
                                                                                  const UIN *blockValues,
                                                                                  MATRIX_C_TYPE *matrixP) {
    constexpr int aTileSMEMSize = WMMA_M * WMMA_N;
    constexpr int bTileSMEMSize = WMMA_K * WMMA_N * 2;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::row_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    const UIN laneId = threadIdx.x % WARP_SIZE;
    const UIN warpId = threadIdx.x / WARP_SIZE;

    const UIN rowPanelId = blockIdx.x;

    const UIN lda = K;
    const UIN ldb = N;

    // Load matrix A into shared memory, each thread loads 4 elements, conflict-free access
#pragma unroll
    for (int iter = 0; iter < 4; ++iter) {
        const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 8) + (laneId / 16) + (iter * 2);
        const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
        const UIN aColId = kIter + laneId % 16;

        aTileSMEM[warpId * 128 + iter * 32 + laneId] =
            (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
    }

    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];
    for (int colBlockIter = 0; colBlockIter < numColBlocksCurrentRowPanel; colBlockIter += 2) {

        // Data needs to be reset to zero before calculating the next column block
        fill_fragment(cFrag, 0.0f);

        const UIN colBlockId = colBlockIter + warpId;
        const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

        const UIN startIndexOfReorderedColsCurrentIter =
            reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockIter;
        const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

        // Load matrix B data into shared memory, each thread loads 8 elements, conflict-free access
        const UIN reorderedColIndex = startIndexOfReorderedColsCurrentIter + laneId;
#pragma unroll
        for (int iter = 0; iter < 8; ++iter) {
            const UIN bRowId = kIter + warpId * 8 + iter;
            const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                reorderedCols[reorderedColIndex] : N;

            bTileSMEM[warpId * 256 + iter * 32 + laneId] =
                (bRowId < K && bColId < N) ? matrixB[bRowId * ldb + bColId] : static_cast<MATRIX_B_TYPE>(0);
        }
        __syncthreads();

        // Compute the matrix multiplication
        if (colBlockId < numColBlocksCurrentRowPanel) {
            wmma::load_matrix_sync(aFrag, aTileSMEM, WMMA_N);
            wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * WMMA_N, WMMA_N * 2);
            wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
        }

        __syncthreads();


        // Store the result
        if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
            for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
                UIN localRow, localCol;
                calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

                const UIN idxOfMatrixP =
                    blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

                // Saved when the value is not 0
                if (idxOfMatrixP != NULL_VALUE) {
                    matrixP[idxOfMatrixP] += cFrag.x[idxOfFragment];
                }
            }
        }
        __syncthreads();
    }
}

// m16n16k16
// blockDim: [64, 1, 1]
// 在外部进行K迭代
__global__ void sddmm_gpu_rebell_m16n16k16_outkIter_matrixA_rowMaj_matrixB_colMaj(const UIN M,
                                                                                  const UIN N,
                                                                                  const UIN K,
                                                                                  const UIN kIter,
                                                                                  const MATRIX_A_TYPE *matrixA,
                                                                                  const MATRIX_B_TYPE *matrixB,
                                                                                  const UIN numNonZeroRow,
                                                                                  const UIN *reorderedRows,
                                                                                  const UIN *reorderedCols,
                                                                                  const UIN *reorderedColOffset,
                                                                                  const UIN *blockRowOffsets,
                                                                                  const UIN *blockValues,
                                                                                  MATRIX_C_TYPE *matrixP) {
    constexpr int aTileSMEMSize = WMMA_M * WMMA_N;
    constexpr int bTileSMEMSize = WMMA_K * WMMA_N * 2;

    __shared__ MATRIX_A_TYPE aTileSMEM[aTileSMEMSize];
    __shared__ MATRIX_B_TYPE bTileSMEM[bTileSMEMSize];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::row_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    const UIN laneId = threadIdx.x % WARP_SIZE;
    const UIN warpId = threadIdx.x / WARP_SIZE;

    const UIN rowPanelId = blockIdx.x;

    const UIN lda = K;
    const UIN ldb = K;

    // Load matrix A into shared memory, each thread loads 4 elements, conflict-free access
#pragma unroll
    for (int iter = 0; iter < 4; ++iter) {
        const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 8) + (laneId / 16) + (iter * 2);
        const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
        const UIN aColId = kIter + laneId % 16;

        aTileSMEM[warpId * 128 + iter * 32 + laneId] =
            (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
    }

    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];
    for (int colBlockIter = 0; colBlockIter < numColBlocksCurrentRowPanel; colBlockIter += 2) {

        // Data needs to be reset to zero before calculating the next column block
        fill_fragment(cFrag, 0.0f);

        const UIN colBlockId = colBlockIter + warpId;
        const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

        const UIN startIndexOfReorderedColsCurrentIter =
            reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockIter;
        const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

        // Load matrix B data into shared memory, each thread loads 8 elements, conflict-free access
        const UIN reorderedColIndex = startIndexOfReorderedColsCurrentIter + laneId;
#pragma unroll
        for (int iter = 0; iter < 8; ++iter) {
            const UIN bRowId = kIter + warpId * 8 + iter;
            const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                reorderedCols[reorderedColIndex] : N;

            bTileSMEM[warpId * 256 + iter * 32 + laneId] =
                (bRowId < K && bColId < N) ? matrixB[bRowId + bColId * ldb] : static_cast<MATRIX_B_TYPE>(0);
        }
        __syncthreads();

        // Compute the matrix multiplication
        if (colBlockId < numColBlocksCurrentRowPanel) {
            wmma::load_matrix_sync(aFrag, aTileSMEM, WMMA_N);
            wmma::load_matrix_sync(bFrag, bTileSMEM + warpId * WMMA_N, WMMA_N * 2);
            wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
        }

        __syncthreads();


        // Store the result
        if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
            for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
                UIN localRow, localCol;
                calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

                const UIN idxOfMatrixP =
                    blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

                // Saved when the value is not 0
                if (idxOfMatrixP != NULL_VALUE) {
                    matrixP[idxOfMatrixP] += cFrag.x[idxOfFragment];
                }
            }
        }
        __syncthreads();
    }
}

// m16n16k16
// blockDim: [64, 1, 1]
// 一次加载4*WMMA_K个元素
__global__ void sddmm_gpu_rebell_4WMMA_K_m16n16k16_matrixA_rowMaj_matrixB_rowMaj(const UIN M,
                                                                                 const UIN N,
                                                                                 const UIN K,
                                                                                 const MATRIX_A_TYPE *matrixA,
                                                                                 const MATRIX_B_TYPE *matrixB,
                                                                                 const UIN numNonZeroRow,
                                                                                 const UIN *reorderedRows,
                                                                                 const UIN *reorderedCols,
                                                                                 const UIN *reorderedColOffset,
                                                                                 const UIN *blockRowOffsets,
                                                                                 const UIN *blockValues,
                                                                                 MATRIX_C_TYPE *matrixP) {
    __shared__ MATRIX_A_TYPE aTileSMEM[(16 * 16) * 4];
    __shared__ MATRIX_B_TYPE bTileSMEM[(16 * 32) * 4];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::row_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    const UIN laneId = threadIdx.x % WARP_SIZE;
    const UIN warpId = threadIdx.x / WARP_SIZE;

    const UIN rowPanelId = blockIdx.x;

    const UIN lda = K;
    const UIN ldb = N;

    const UIN startIndexOfRowsCurrentRowPanel = rowPanelId * ROW_PANEL_SIZE;
    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];
    for (int colBlockIter = 0; colBlockIter < numColBlocksCurrentRowPanel; colBlockIter += 2) {

        // Data needs to be reset to zero before calculating the next column block
        fill_fragment(cFrag, 0.0f);

        const UIN colBlockId = colBlockIter + warpId;
        const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

        const UIN startIndexOfReorderedColsCurrentIter =
            reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockIter;
        const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

        const UIN reorderedColIndex = startIndexOfReorderedColsCurrentIter + laneId;

        // Loop over K
        for (int kIter = 0; kIter < K; kIter += WMMA_K * 4) {
            // Load matrix A into shared memory, each thread loads 16 elements, conflict-free access
#pragma unroll
            for (int iter = 0; iter < 16; ++iter) {
                const UIN reorderedRowIndex = startIndexOfRowsCurrentRowPanel + iter;
                const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
                const UIN aColId = warpId * WARP_SIZE + laneId;

                aTileSMEM[warpId * 32 + iter * 64 + laneId] =
                    (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
            }

            // Load matrix B data into shared memory, each thread loads 32 elements, conflict-free access
#pragma unroll
            for (int iter = 0; iter < 32; ++iter) {
                const UIN bRowId = kIter + warpId * 32 + iter;
                const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                    reorderedCols[reorderedColIndex] : N;

                bTileSMEM[warpId * 1024 + iter * 32 + laneId] =
                    (bRowId < K && bColId < N) ? matrixB[bRowId * ldb + bColId] : static_cast<MATRIX_B_TYPE>(0);
            }
            __syncthreads();

            // Compute the matrix multiplication
            if (colBlockId < numColBlocksCurrentRowPanel) {
                for (int iter = 0; iter < 4; ++iter) {
                    wmma::load_matrix_sync(aFrag, aTileSMEM + iter * 16, WMMA_K * 4);
                    wmma::load_matrix_sync(bFrag, (bTileSMEM + warpId * WMMA_N) + iter * 512, WMMA_N * 2);
                    wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
                }
            }

            __syncthreads();
        }

        // Store the result
        if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
            for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
                UIN localRow, localCol;
                calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

                const UIN idxOfMatrixP =
                    blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

                // Saved when the value is not 0
                if (idxOfMatrixP != NULL_VALUE) {
                    matrixP[idxOfMatrixP] = cFrag.x[idxOfFragment];
                }
            }
        }
        __syncthreads();
    }
}

// m16n16k16
// blockDim: [64, 1, 1]
// 一次加载4*WMMA_K个元素
__global__ void sddmm_gpu_rebell_4WMMA_K_m16n16k16_matrixA_rowMaj_matrixB_colMaj(const UIN M,
                                                                                 const UIN N,
                                                                                 const UIN K,
                                                                                 const MATRIX_A_TYPE *matrixA,
                                                                                 const MATRIX_B_TYPE *matrixB,
                                                                                 const UIN numNonZeroRow,
                                                                                 const UIN *reorderedRows,
                                                                                 const UIN *reorderedCols,
                                                                                 const UIN *reorderedColOffset,
                                                                                 const UIN *blockRowOffsets,
                                                                                 const UIN *blockValues,
                                                                                 MATRIX_C_TYPE *matrixP) {
    __shared__ MATRIX_A_TYPE aTileSMEM[(16 * 16) * 4];
    __shared__ MATRIX_B_TYPE bTileSMEM[(16 * 32) * 4];

    wmma::fragment<wmma::matrix_a, WMMA_M, WMMA_N, WMMA_K, MATRIX_A_TYPE_FRAGMENT, wmma::row_major> aFrag;
    wmma::fragment<wmma::matrix_b, WMMA_M, WMMA_N, WMMA_K, MATRIX_B_TYPE_FRAGMENT, wmma::row_major> bFrag;

    wmma::fragment<wmma::accumulator, WMMA_M, WMMA_N, WMMA_K, MATRIX_C_TYPE> cFrag;

    const UIN laneId = threadIdx.x % WARP_SIZE;
    const UIN warpId = threadIdx.x / WARP_SIZE;

    const UIN rowPanelId = blockIdx.x;

    const UIN lda = K;
    const UIN ldb = K;

    const UIN startIndexOfRowsCurrentRowPanel = rowPanelId * ROW_PANEL_SIZE;
    const UIN numColBlocksCurrentRowPanel = blockRowOffsets[rowPanelId + 1] - blockRowOffsets[rowPanelId];
    for (int colBlockIter = 0; colBlockIter < numColBlocksCurrentRowPanel; colBlockIter += 2) {

        // Data needs to be reset to zero before calculating the next column block
        fill_fragment(cFrag, 0.0f);

        const UIN colBlockId = colBlockIter + warpId;
        const UIN startIndexOfBlockValuesCurrentBlock = (blockRowOffsets[rowPanelId] + colBlockId) * BLOCK_SIZE;

        const UIN startIndexOfReorderedColsCurrentIter =
            reorderedColOffset[rowPanelId] + BLOCK_COL_SIZE * colBlockIter;
        const UIN endIndexOfReorderedColsCurrentPanel = reorderedColOffset[rowPanelId + 1];

        const UIN reorderedColIndex = startIndexOfReorderedColsCurrentIter + laneId;

        // Loop over K
        for (int kIter = 0; kIter < K; kIter += WMMA_K * 4) {
            // Load matrix A into shared memory, each thread loads 16 elements, conflict-free access
#pragma unroll
            for (int iter = 0; iter < 16; ++iter) {
                const UIN reorderedRowIndex = startIndexOfRowsCurrentRowPanel + iter;
                const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
                const UIN aColId = warpId * WARP_SIZE + laneId;

                aTileSMEM[warpId * 32 + iter * 64 + laneId] =
                    (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<MATRIX_A_TYPE>(0);
            }

            // Load matrix B data into shared memory, each thread loads 32 elements, conflict-free access
#pragma unroll
            for (int iter = 0; iter < 32; ++iter) {
                const UIN bRowId = kIter + warpId * 32 + iter;
                const UIN bColId = reorderedColIndex < endIndexOfReorderedColsCurrentPanel ?
                    reorderedCols[reorderedColIndex] : N;

                bTileSMEM[warpId * 1024 + iter * 32 + laneId] =
                    (bRowId < K && bColId < N) ? matrixB[bRowId + bColId * ldb] : static_cast<MATRIX_B_TYPE>(0);
            }
            __syncthreads();

            // Compute the matrix multiplication
            if (colBlockId < numColBlocksCurrentRowPanel) {
                for (int iter = 0; iter < 4; ++iter) {
                    wmma::load_matrix_sync(aFrag, aTileSMEM + iter * 16, WMMA_K * 4);
                    wmma::load_matrix_sync(bFrag, (bTileSMEM + warpId * WMMA_N) + iter * 512, WMMA_N * 2);
                    wmma::mma_sync(cFrag, aFrag, bFrag, cFrag);
                }
            }

            __syncthreads();
        }

        // Store the result
        if (colBlockId < numColBlocksCurrentRowPanel) {
#pragma unroll
            for (int idxOfFragment = 0; idxOfFragment < cFrag.num_elements; ++idxOfFragment) {
                UIN localRow, localCol;
                calculateMatrixCFragmentCoordinates(laneId, idxOfFragment, localRow, localCol);

                const UIN idxOfMatrixP =
                    blockValues[startIndexOfBlockValuesCurrentBlock + localRow * BLOCK_COL_SIZE + localCol];

                // Saved when the value is not 0
                if (idxOfMatrixP != NULL_VALUE) {
                    matrixP[idxOfMatrixP] = cFrag.x[idxOfFragment];
                }
            }
        }
        __syncthreads();
    }
}

__global__ void sddmm_gpu_sparse_residue(const UIN M, const UIN N, const UIN K,
                                         const float *__restrict__ matrixA,
                                         const float *__restrict__ matrixB,
                                         const float alpha, const float beta,
                                         const UIN numNonZeroRow,
                                         const UIN *__restrict__ reorderedRows,
                                         const UIN *__restrict__ sparseCols,
                                         const UIN *__restrict__ sparseColOffset,
                                         float *matrixP) {
    // 线程块中线程数量
    constexpr int eachThreadLoadsTheNumberOfMatrixADatas =
        (WMMA_M * WMMA_K) / (WARP_SIZE * sddmm_rebell_number_of_warps_per_thread_block);
    constexpr int eachWarpLoadsTheNumberOfMatrixADatas = WARP_SIZE * eachThreadLoadsTheNumberOfMatrixADatas;

    constexpr int aTileSMEMSize = (WMMA_M * WMMA_N) * 2;

    __shared__ float aTileSMEM[aTileSMEMSize];

    const UIN laneId = threadIdx.x & 31;
    const UIN warpId = threadIdx.x >> 5;

    const UIN rowPanelId = blockIdx.x;

    const UIN lda = K;
    const UIN ldb = K;

    // Loop over K
    for (int kIter = 0; kIter < K; kIter += WMMA_K * 2) {
        // Load matrix A into shared memory, each thread loads 2 elements, conflict-free access
#pragma unroll
        for (int iter = 0; iter < eachThreadLoadsTheNumberOfMatrixADatas; ++iter) {
            const UIN reorderedRowIndex = (rowPanelId * ROW_PANEL_SIZE) + (warpId * 2) + iter;
            const UIN aRowId = reorderedRowIndex < numNonZeroRow ? reorderedRows[reorderedRowIndex] : M;
            const UIN aColId = kIter + laneId;

            aTileSMEM[warpId * eachWarpLoadsTheNumberOfMatrixADatas + iter * WARP_SIZE + laneId] =
                (aRowId < M && aColId < K) ? matrixA[aRowId * lda + aColId] : static_cast<float>(0);
        }

        __syncthreads();

        // Load matrix B data


        // Compute the matrix multiplication

        __syncthreads();
    }
}

} // namespace kernel

void sddmm_gpu_rebell(const Matrix<float> &matrixA,
                      const Matrix<float> &matrixB,
                      const float alpha, const float beta,
                      const sparseMatrix::CSR<float> &matrixS,
                      const ReBELL &rebell,
                      sparseMatrix::CSR<float> &matrixP,
                      Logger &logger) {

    // Convert the data type of matrix A and matrix B for use tensor core
    dev::vector<MATRIX_A_TYPE> matrixA_values_convertedType_dev(matrixA.size());
    dev::vector<MATRIX_B_TYPE> matrixB_values_convertedType_dev(matrixB.size());
    {
        dev::vector<float> matrixA_values_dev(matrixA.values());
        dev::vector<float> matrixB_values_dev(matrixB.values());

        const int numThreadPerBlock = 1024;
        kernel::convertDataType<<< (matrixA.size() + numThreadPerBlock - 1) / numThreadPerBlock, numThreadPerBlock>>>(
            matrixA.size(), matrixA_values_dev.data(), matrixA_values_convertedType_dev.data());
        kernel::convertDataType<<< (matrixB.size() + numThreadPerBlock - 1) / numThreadPerBlock, numThreadPerBlock>>>(
            matrixB.size(), matrixB_values_dev.data(), matrixB_values_convertedType_dev.data());
    }

    // Copy the data from the host to the device
    dev::vector<UIN> reorderedRowIndices_dev(rebell.reorderedRows());
    dev::vector<UIN> reorderedColIndices_dev(rebell.reorderedCols());
    dev::vector<UIN> reorderedColIndicesOffset_dev(rebell.reorderedColOffsets());
    dev::vector<UIN> blockRowOffsets_dev(rebell.blockRowOffsets());
    dev::vector<UIN> blockValues_dev(rebell.blockValues());

    dev::vector<float> matrixP_dev(matrixS.values());

    dim3 grid, block;

    const UIN eachThreadBlockCountsTheNumberOfColBlocks = 8;
    block.x = WARP_SIZE * eachThreadBlockCountsTheNumberOfColBlocks;

    // Assign row panel to x-axis of grid, and assign col block to y-axis of grid
    grid.x = rebell.numRowPanels();
    grid.y = std::ceil(static_cast<float>(rebell.maxNumColBlocks()) / eachThreadBlockCountsTheNumberOfColBlocks);

    logger.gridDim_ = grid;
    logger.blockDim_ = block;

    CudaTimeCalculator timeCalculator;
    timeCalculator.startClock();

    if (matrixA.storageOrder() == MatrixStorageOrder::row_major
        && matrixB.storageOrder() == MatrixStorageOrder::row_major) {
        kernel::sddmm_gpu_rebell_m16n16k16_block256_matrixA_rowMaj_matrixB_rowMaj<<<grid, block>>>(matrixS.row(), matrixS.col(), matrixA.col(),
            matrixA_values_convertedType_dev.data(),
            matrixB_values_convertedType_dev.data(),
            alpha, beta,
            rebell.reorderedRows().size(),
            reorderedRowIndices_dev.data(),
            reorderedColIndices_dev.data(),
            reorderedColIndicesOffset_dev.data(),
            blockRowOffsets_dev.data(),
            blockValues_dev.data(),
            matrixP_dev.data());
    } else if (matrixA.storageOrder() == MatrixStorageOrder::row_major
        && matrixB.storageOrder() == MatrixStorageOrder::col_major) {
#ifdef WMMA_16_16_16
        kernel::sddmm_gpu_rebell_m16n16k16_block256_matrixA_rowMaj_matrixB_colMaj<<<grid, block>>>(matrixS.row(), matrixS.col(), matrixA.col(),
            matrixA_values_convertedType_dev.data(),
            matrixB_values_convertedType_dev.data(),
            alpha, beta,
            rebell.reorderedRows().size(),
            reorderedRowIndices_dev.data(),
            reorderedColIndices_dev.data(),
            reorderedColIndicesOffset_dev.data(),
            blockRowOffsets_dev.data(),
            blockValues_dev.data(),
            matrixP_dev.data());
#endif // WMMA_16_16_16

#ifdef WMMA_16_16_8
        kernel::sddmm_gpu_rebell_m16n16k8_block256_matrixA_rowMaj_matrixB_colMaj<<<grid, block>>>(matrixS.row(), matrixS.col(), matrixA.col(),
            matrixA_values_convertedType_dev.data(),
            matrixB_values_convertedType_dev.data(),
            alpha, beta,
            rebell.reorderedRows().size(),
            reorderedRowIndices_dev.data(),
            reorderedColIndices_dev.data(),
            reorderedColIndicesOffset_dev.data(),
            blockRowOffsets_dev.data(),
            blockValues_dev.data(),
            matrixP_dev.data());
#endif // WMMA_16_16_8
    } else {
        fprintf(stderr, "sddmm_gpu_rebell not support this matrix storage order\n");
    }

    timeCalculator.endClock();

    logger.zcx_sddmm_time_ = timeCalculator.getTime();

    // Copy the results from the device to the host
    matrixP.setValues() = d2h(matrixP_dev);
}

// 在外部进行K迭代
void sddmm_gpu_rebell_out_kIter(const Matrix<float> &matrixA,
                                const Matrix<float> &matrixB,
                                const float alpha, const float beta,
                                const sparseMatrix::CSR<float> &matrixS,
                                const ReBELL &rebell,
                                sparseMatrix::CSR<float> &matrixP,
                                float &time) {

    dev::vector<MATRIX_A_TYPE> matrixA_values_convertedType_dev(matrixA.size());
    dev::vector<MATRIX_B_TYPE> matrixB_values_convertedType_dev(matrixB.size());
    {
        dev::vector<float> matrixA_values_dev(matrixA.values());
        dev::vector<float> matrixB_values_dev(matrixB.values());

        const int numThreadPerBlock = 1024;
        kernel::convertDataType<<< (matrixA.size() + numThreadPerBlock - 1) / numThreadPerBlock, numThreadPerBlock>>>(
            matrixA.size(), matrixA_values_dev.data(), matrixA_values_convertedType_dev.data());
        kernel::convertDataType<<< (matrixB.size() + numThreadPerBlock - 1) / numThreadPerBlock, numThreadPerBlock>>>(
            matrixB.size(), matrixB_values_dev.data(), matrixB_values_convertedType_dev.data());
    }

    dev::vector<UIN> reorderedRowIndices_dev(rebell.reorderedRows());
    dev::vector<UIN> reorderedColIndices_dev(rebell.reorderedCols());
    dev::vector<UIN> reorderedColIndicesOffset_dev(rebell.reorderedColOffsets());
    dev::vector<UIN> blockRowOffsets_dev(rebell.blockRowOffsets());
    dev::vector<UIN> blockValues_dev(rebell.blockValues());
    dev::vector<float> matrixP_dev(matrixS.nnz());

    dim3 grid, block;
    block.x = 64;
    grid.x = rebell.numRowPanels();

    CudaTimeCalculator timeCalculator;
    timeCalculator.startClock();
    // Loop over K
    for (int kIter = 0; kIter < matrixA.col(); kIter += WMMA_K) {
        kernel::sddmm_gpu_rebell_m16n16k16_outkIter_matrixA_rowMaj_matrixB_rowMaj<<<grid, block>>>(matrixS.row(), matrixS.col(), matrixA.col(), kIter,
            matrixA_values_convertedType_dev.data(),
            matrixB_values_convertedType_dev.data(),
            rebell.reorderedRows().size(),
            reorderedRowIndices_dev.data(),
            reorderedColIndices_dev.data(),
            reorderedColIndicesOffset_dev.data(),
            blockRowOffsets_dev.data(),
            blockValues_dev.data(),
            matrixP_dev.data());
    }
    timeCalculator.endClock();

    time = timeCalculator.getTime();

    matrixP.setValues() = d2h(matrixP_dev);
}
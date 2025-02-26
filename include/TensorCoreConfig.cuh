#pragma once

#include <cstdint>
#include <limits>

#include <cuda_runtime.h>
#include <cuda_fp16.h>

using UIN = uint32_t;
constexpr UIN MAX_UIN = std::numeric_limits<UIN>::max();

// The dimension supported by WMMA
#define WMMA_16_16_16
//#define WMMA_32_8_16
//#define WMMA_8_32_16

#ifdef WMMA_16_16_16
constexpr int WMMA_M = 16;
constexpr int WMMA_N = 16;
constexpr int WMMA_K = 16;
#endif // WMMA_16_16_16

#ifdef WMMA_32_8_16
constexpr int  WMMA_M = 32;
constexpr int  WMMA_N = 8;
constexpr int  WMMA_K = 16;
#endif // WMMA_32_8_16

#ifdef WMMA_8_32_16
constexpr int  WMMA_M = 8;
constexpr int  WMMA_N = 32;
constexpr int  WMMA_K = 16;
#endif // WMMA_8_32_16

using MATRIX_A_TYPE = __half;
using MATRIX_B_TYPE = __half;
using MATRIX_C_TYPE = float;

constexpr int WARP_SIZE = 32;

inline __host__ __device__ void calculateFragmentLaneAndIndex_m16n16k16(const UIN tileRow, const UIN tileCol,
                                                                        const UIN row, const UIN col,
                                                                        UIN &laneId, UIN &indexOfFragment) {
    if (tileRow > row || tileCol > col || tileRow + WMMA_M <= row || tileCol + WMMA_N <= col) {
        return;
    }
    const int localRow = row - tileRow;
    const int localCol = col - tileCol;

    const int beginLane = localRow % 8 * 4;
    const int isBigRow = localRow / 8;
    const int isBigCol = localCol / 8;
    laneId = beginLane + localCol % 8 / 2;
    indexOfFragment = isBigRow * 2 + isBigCol * 4 + localCol % 2;
}
inline __host__ __device__ void calculateFragmentLaneAndIndex_m32n8k16(const UIN tileRow, const UIN tileCol,
                                                                       const UIN row, const UIN col,
                                                                       UIN &laneId, UIN &indexOfFragment) {
    if (tileRow > row || tileCol > col || tileRow + WMMA_M <= row || tileCol + WMMA_N <= col) {
        return;
    }
    const int localRow = row - tileRow;
    const int localCol = col - tileCol;

    const int beginLane = localRow % 8 * 4;
    const int groupId = localRow / 8;
    const int isColOdd = localCol % 2;
    laneId = beginLane + localCol / 2;
    indexOfFragment = groupId * 2 + isColOdd;
}
inline __host__ __device__ void calculateFragmentLaneAndIndex_m8n32k16(const UIN tileRow, const UIN tileCol,
                                                                       const UIN row, const UIN col,
                                                                       UIN &laneId, UIN &indexOfFragment) {
    if (tileRow > row || tileCol > col || tileRow + WMMA_M <= row || tileCol + WMMA_N <= col) {
        return;
    }
    const int localRow = row - tileRow;
    const int localCol = col - tileCol;

    const int beginLane = localCol % 8 * 4;
    const int groupId = localCol / 8;
    const int isColOdd = localRow % 2;
    laneId = beginLane + localRow / 2;
    indexOfFragment = groupId * 2 + isColOdd;
}

inline __host__ __device__ void calculateFragmentLaneAndIndex(const UIN tileRow, const UIN tileCol,
                                                              const UIN row, const UIN col,
                                                              UIN &laneId, UIN &indexOfFragment) {
#ifdef WMMA_16_16_16
    calculateFragmentLaneAndIndex_m16n16k16(tileRow, tileCol, row, col, laneId, indexOfFragment);
#endif //WMMA_16_16_16

#ifdef WMMA_32_16_16
    calculateFragmentLaneAndIndex_m32n8k16(tileRow, tileCol, row, col, laneId, indexOfFragment);
#endif //WMMA_32_16_16

#ifdef WMMA_8_32_16
    calculateFragmentLaneAndIndex_m8n32k16(tileRow, tileCol, row, col, laneId, indexOfFragment);
#endif //WMMA_8_32_16
}

inline __host__ __device__ void calculateFragmentCoordinates_m16n16k16(const UIN laneId, const UIN indexOfFragment,
                                                                       UIN &row, UIN &col) {
    // Divide the lanes into groups of 4
    const UIN laneGroupId = laneId / 4;
    const UIN localIdInLaneGroup = laneId % 4;

    // Divide the index into groups of 2
    const UIN indexGroupId = indexOfFragment / 2;

    const UIN isOddIndexGroupId = indexGroupId % 2;

    const UIN isOddIndex = indexOfFragment % 2;
    const UIN isBigLaneGroup = indexOfFragment / 4;

    row = laneGroupId + 8 * isOddIndexGroupId;
    col = localIdInLaneGroup * 2 + isOddIndex + 8 * isBigLaneGroup;
}

inline __host__ __device__ void calculateFragmentCoordinates_m32n8k16(const UIN laneId, const UIN indexOfFragment,
                                                                      UIN &row, UIN &col) {
    // Divide the lanes into groups of 4
    const UIN laneGroupId = laneId / 4;
    const UIN localIdInLaneGroup = laneId % 4;

    // Divide the index into groups of 2
    const UIN indexGroupId = indexOfFragment / 2;

    const UIN isOddIndex = indexOfFragment % 2;

    row = indexGroupId * 8 + laneGroupId;
    col = localIdInLaneGroup * 2 + isOddIndex;
}

inline __host__ __device__ void calculateFragmentCoordinates_m8n32k16(const UIN laneId, const UIN indexOfFragment,
                                                                      UIN &row, UIN &col) {
    // Divide the lanes into groups of 4
    const UIN laneGroupId = laneId / 4;
    const UIN localIdInLaneGroup = laneId % 4;

    // Divide the index into groups of 2
    const UIN indexGroupId = indexOfFragment / 2;

    const UIN isOddIndex = indexOfFragment % 2;

    row = localIdInLaneGroup * 2 + isOddIndex;
    col = indexGroupId * 8 + laneGroupId;
}

inline __host__ __device__ void calculateFragmentCoordinates(const UIN laneId, const UIN indexOfFragment,
                                                             UIN &row, UIN &col) {
#ifdef WMMA_16_16_16
    calculateFragmentCoordinates_m16n16k16(laneId, indexOfFragment, row, col);
#endif //WMMA_16_16_16

#ifdef WMMA_32_16_16
    calculateFragmentCoordinates_m32n8k16(laneId, index, row, col);
#endif //WMMA_32_16_16

#ifdef WMMA_8_32_16
    calculateFragmentCoordinates_m8n32k16(laneId, index, row, col);
#endif //WMMA_8_32_16
}

constexpr int NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD = 4;
constexpr int NUM_OF_Y_PER_BLOCK_OLD_METHOD = 4;

constexpr int ITERATION_STEP_OF_K = NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD * WMMA_K;

constexpr int NUMBER_OF_MATRIX_TILE_K_IN_SHARED_MEMORY = NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;

constexpr int MATRIX_TILE_A_SIZE = WMMA_M * WMMA_K;
constexpr int MATRIX_TILE_B_SIZE = WMMA_K * WMMA_N;

constexpr int BLOCK_COUNTS_NUMBER_OF_MATRIX_C_ROWS = WMMA_M * NUM_OF_Y_PER_BLOCK_OLD_METHOD;
constexpr int BLOCK_COUNTS_NUMBER_OF_MATRIX_C_COLS = WMMA_N * NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;

constexpr int
    MATRIX_TILE_A_SIZE_PER_BLOCK = WMMA_M * NUM_OF_Y_PER_BLOCK_OLD_METHOD * WMMA_K * NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;
constexpr int
    MATRIX_TILE_B_SIZE_PER_BLOCK = WMMA_K * NUM_OF_Y_PER_BLOCK_OLD_METHOD * WMMA_N * NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;

constexpr int MATRIX_TILE_A_LEADING_DIMENSION = WMMA_K * NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;
constexpr int MATRIX_TILE_B_LEADING_DIMENSION = WMMA_N * NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;

constexpr int MEMORY_ACCESS_PER_THREAD =
    MATRIX_TILE_A_SIZE_PER_BLOCK / (NUM_OF_Y_PER_BLOCK_OLD_METHOD * NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD * WARP_SIZE);

constexpr int NUMBER_OF_MEMORY_ACCESSES_MATRIX_TILE_A_PER_WARP =
    MATRIX_TILE_A_SIZE_PER_BLOCK / (NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD * NUM_OF_Y_PER_BLOCK_OLD_METHOD);

constexpr int NUMBER_OF_MEMORY_ACCESSES_MATRIX_TILE_B_PER_WARP =
    MATRIX_TILE_B_SIZE_PER_BLOCK / (NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD * NUM_OF_Y_PER_BLOCK_OLD_METHOD);

constexpr int NUMBER_OF_MATRIX_TILE_A_MEMORY_ACCESSES_ROWS_PER_WARP =
    BLOCK_COUNTS_NUMBER_OF_MATRIX_C_ROWS / (NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD * NUM_OF_Y_PER_BLOCK_OLD_METHOD);

constexpr int NUMBER_OF_MATRIX_TILE_B_MEMORY_ACCESSES_ROWS_PER_WARP =
    BLOCK_COUNTS_NUMBER_OF_MATRIX_C_ROWS / (NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD * NUM_OF_Y_PER_BLOCK_OLD_METHOD);

enum WarpOrder {
  x_major,
  y_major
};

/**
 * Configuration class for matrix multiplication using Tensor core
 **/
// TODO: Adjust according to WarpOrder
class TensorCoreConfig {
 public:
  TensorCoreConfig() = delete;

  TensorCoreConfig(UIN M, UIN N, WarpOrder warpOrder = WarpOrder::y_major) {
      blockDim_.x = NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD * WARP_SIZE;
      blockDim_.y = NUM_OF_Y_PER_BLOCK_OLD_METHOD;

      const int numCountColOfOutputMatrixPerBlock = WMMA_N * blockDim_.x / WARP_SIZE;
      const int numCountRowOfOutputMatrixPerBlock = WMMA_M * blockDim_.y;
      gridDim_.x = (NForTensorCore(N) + numCountColOfOutputMatrixPerBlock - 1) / numCountColOfOutputMatrixPerBlock;
      gridDim_.y = (MForTensorCore(M) + numCountRowOfOutputMatrixPerBlock - 1) / numCountRowOfOutputMatrixPerBlock;

      warpOrder_ = warpOrder;

      numWarpX_ = gridDim_.x * blockDim_.x / WARP_SIZE;
      numWarpY_ = gridDim_.y * blockDim_.y;;
  }

  inline __host__ __device__ UIN MForTensorCore(UIN M) const {
      const UIN numMInOneIteration = WMMA_M * NUM_OF_Y_PER_BLOCK_OLD_METHOD;
      const UIN MComplement = M % numMInOneIteration == 0 ? 0 : numMInOneIteration - M % numMInOneIteration;
      return M + MComplement;
  }

  inline __host__ __device__ UIN NForTensorCore(UIN N) const {
      const UIN numNInOneIteration = WMMA_N * NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;
      const UIN NComplement = N % numNInOneIteration == 0 ? 0 : numNInOneIteration - N % numNInOneIteration;
      return N + NComplement;
  }

  inline __host__ __device__ UIN KForTensorCore(UIN K) const {
      const UIN numKInOneIteration = WMMA_K * NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;
      const UIN KComplement = K % numKInOneIteration == 0 ? 0 : numKInOneIteration - K % numKInOneIteration;
      return K + KComplement;
  }

  inline __host__ __device__ dim3 gridDim() const {
      return gridDim_;
  }

  inline __host__ __device__ dim3 blockDim() const {
      return blockDim_;
  }

  inline __host__ __device__ UIN numWarpX() const {
      return numWarpX_;
  }

  inline __host__ __device__ UIN numWarpY() const {
      return numWarpY_;
  }

  inline UIN calculateWarpId(UIN row, UIN col) const {
      return row / WMMA_M * numWarpX_ + col / WMMA_N;
  }

  inline __device__ void initByKernel(dim3 _blockIdx, dim3 _blockDim, dim3 _threadIdx) {
      globalThreadIdxX_ = _blockIdx.x * _blockDim.x + _threadIdx.x;
      globalThreadIdxY_ = _blockIdx.y * _blockDim.y + _threadIdx.y;

      globalWarpId_ = (globalThreadIdxX_ / WARP_SIZE) + globalThreadIdxY_ * (gridDim_.x * blockDim_.x / WARP_SIZE);
      localWarpId_ = _threadIdx.x / WARP_SIZE + _threadIdx.y * NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;
      laneId_ = _threadIdx.x % WARP_SIZE;

      blockStarRow_ = _blockIdx.y * BLOCK_COUNTS_NUMBER_OF_MATRIX_C_ROWS;
      blockStarCol_ = _blockIdx.x * BLOCK_COUNTS_NUMBER_OF_MATRIX_C_COLS;
  }

  inline __device__ UIN globalThreadIdxX() const {
      return globalThreadIdxX_;
  }
  inline __device__ UIN globalThreadIdxY() const {
      return globalThreadIdxY_;
  }
  inline __device__ UIN globalWarpId() const {
      return globalWarpId_;
  }
  inline __device__ UIN localWarpId() const {
      return localWarpId_;
  }
  inline __device__ UIN localWarpX() const {
      return localWarpId_ % NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;
  }
  inline __device__ UIN localWarpY() const {
      return localWarpId_ / NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;
  }
  inline __device__ UIN laneId() const {
      return laneId_;
  }
  inline __device__ UIN blockStarRow() const {
      return blockStarRow_;
  }
  inline __device__ UIN blockStarCol() const {
      return blockStarCol_;
  }
  inline __device__ UIN blockEndRow() const {
      return blockStarRow_ + BLOCK_COUNTS_NUMBER_OF_MATRIX_C_ROWS;
  }
  inline __device__ UIN blockEndCol() const {
      return blockStarCol_ + BLOCK_COUNTS_NUMBER_OF_MATRIX_C_COLS;
  }
  inline __device__ UIN warpStarRow() const {
      return globalThreadIdxY_ * WMMA_M;
  }
  inline __device__ UIN warpStarCol() const {
      return globalThreadIdxX_ / WARP_SIZE * WMMA_N;
  }
  inline __device__ UIN warpEndRow() const {
      return globalThreadIdxY_ * WMMA_M + WMMA_M;
  }
  inline __device__ UIN warpEndCol() const {
      return globalThreadIdxX_ / WARP_SIZE * WMMA_N + WMMA_N;
  }
  inline __device__ UIN aOffsetIndex() const {
      return localWarpId_ / NUM_OF_WARP_X_PER_BLOCK_OLD_METHOD;
  }

 private:
  WarpOrder warpOrder_;

  dim3 gridDim_;
  dim3 blockDim_;

  UIN numWarpX_;
  UIN numWarpY_;

  // kernel
  UIN globalThreadIdxX_;
  UIN globalThreadIdxY_;
  UIN globalWarpId_;
  UIN localWarpId_;
  UIN laneId_;
  UIN blockStarRow_;
  UIN blockStarCol_;
};
#pragma once

#include "TensorCoreConfig.cuh"

const int NUMBER_OF_OPERATIONS_ON_SHARED_MEMORY_BY_ONE_THREAD = 8;
const int NUMBER_OF_THREADS_PER_BLOCK = 512;
const int SHARED_MEMORY_SIZE = NUMBER_OF_OPERATIONS_ON_SHARED_MEMORY_BY_ONE_THREAD * NUMBER_OF_THREADS_PER_BLOCK;

const int NUMBER_OF_CALCULATED_BY_ONE_BLOCK = NUMBER_OF_THREADS_PER_BLOCK / WARP_SIZE;

class updateNumOfIndexOperator_1 {
 public:
  updateNumOfIndexOperator_1(UIN *nums) : nums_(nums) {}

  inline __device__ void init(dim3 _gridDim, dim3 _blockIdx, dim3 _blockDim, dim3 _threadIdx) {
      idx_ = _blockIdx.x * _blockDim.x + _threadIdx.x;
  }
  inline __device__ void cycle(UIN mtxIdx) {
      ++num_;
  }
  inline __device__ void done() {
      nums_[idx_] = num_;
  }

 private:
  UIN num_ = 0;
  UIN idx_;

  UIN *nums_;
};

class updateIndexDataPerWarpOperator_1 {
 public:
  updateIndexDataPerWarpOperator_1(const UIN *indexForNumOfIndex, UIN *indexData) :
      indexForNumOfIndex_(indexForNumOfIndex), indexData_(indexData) {}

  inline __device__ void init(dim3 _gridDim, dim3 _blockIdx, dim3 _blockDim, dim3 _threadIdx) {
      UIN idxInThisThread = _blockIdx.x * _blockDim.x + _threadIdx.x;
      indexOfStartStoringInThisThread_ = indexForNumOfIndex_[idxInThisThread];
  }
  inline __device__ void cycle(UIN mtxIdx) {
      indexData_[indexOfStartStoringInThisThread_ + count_] = mtxIdx;
      ++count_;
  }
  inline __device__ void done() {}

 private:
  UIN count_ = 0;
  UIN indexOfStartStoringInThisThread_;

  const UIN *indexForNumOfIndex_;
  UIN *indexData_;
};

template<typename OP>
__global__ void getIndexPerWarp_1(const UIN numWarpsInSDDMM, const UIN numWarpXInSDDMM,
                                  const UIN numTileM, const UIN numTileN,
                                  const UIN nnz,
                                  const UIN *rowIndex,
                                  const UIN *colIndex,
                                  OP op);

class updateNumOfIndexOperator_2 {
 public:
  updateNumOfIndexOperator_2(UIN *nums) : nums_(nums) {}

  inline __device__ void init(dim3 _gridDim, dim3 _blockIdx, dim3 _blockDim, dim3 _threadIdx) {
      idx_ = _blockIdx.x * _blockDim.x + _threadIdx.x;
  }
  inline __device__ void cycle(UIN mtxIdx) {
      ++num_;
  }
  inline __device__ void done() {
      nums_[idx_] = num_;
  }

 private:
  UIN num_ = 0;
  UIN idx_;

  UIN *nums_;
};

class updateIndexDataPerWarpOperator_2 {
 public:
  updateIndexDataPerWarpOperator_2(const UIN *indexForNumOfIndex, UIN *indexData) :
      indexForNumOfIndex_(indexForNumOfIndex), indexData_(indexData) {}

  inline __device__ void init(dim3 _gridDim, dim3 _blockIdx, dim3 _blockDim, dim3 _threadIdx) {
      UIN idxInThisThread = _blockIdx.x * _blockDim.x + _threadIdx.x;
      indexOfStartStoringInThisThread_ = indexForNumOfIndex_[idxInThisThread];
  }
  inline __device__ void cycle(UIN mtxIdx) {
      indexData_[indexOfStartStoringInThisThread_ + count_] = mtxIdx;
      ++count_;
  }
  inline __device__ void done() {}

 private:
  UIN count_ = 0;
  UIN indexOfStartStoringInThisThread_;

  const UIN *indexForNumOfIndex_;
  UIN *indexData_;
};

template<typename OP>
__global__ void getIndexPerWarp_2(const UIN numWarpX,
                                  const UIN nnz,
                                  const UIN *rowIndex,
                                  const UIN *colIndex,
                                  OP op);

class updateScatteredNumOfIndexOperator_3 {
 public:
  updateScatteredNumOfIndexOperator_3(UIN *nums) : nums_(nums) {}

  inline __device__ void init(dim3 _gridDim, dim3 _blockIdx, dim3 _blockDim, dim3 _threadIdx) {
      const UIN numberOfDataStoredPerOneBlock = _blockDim.x;
      const UIN numberOfDataStoredPerYGrid = _gridDim.y * numberOfDataStoredPerOneBlock;
      idx_ = numberOfDataStoredPerYGrid * _blockIdx.x + _blockIdx.y * numberOfDataStoredPerOneBlock + _threadIdx.x;
  }
  inline __device__ void cycle(UIN mtxIdx) {
      ++num_;
  }
  inline __device__ void done() {
      nums_[idx_] = num_;
  }

 private:
  UIN num_ = 0;
  UIN idx_;

  UIN *nums_;
};

class updateScatteredIndexDataPerWarpOperator_3 {
 public:
  updateScatteredIndexDataPerWarpOperator_3(const UIN *indexForScatteredNumOfIndex, UIN *scatteredIndexData) :
      indexForScatteredNumOfIndex_(indexForScatteredNumOfIndex), scatteredIndexData_(scatteredIndexData) {}

  inline __device__ void init(dim3 _gridDim, dim3 _blockIdx, dim3 _blockDim, dim3 _threadIdx) {
      const UIN numberOfDataStoredPerOneBlock = _blockDim.x;
      const UIN numberOfDataStoredPerYGrid = _gridDim.y * numberOfDataStoredPerOneBlock;
      const UIN idxInThisThread =
          numberOfDataStoredPerYGrid * _blockIdx.x + _blockIdx.y * numberOfDataStoredPerOneBlock + _threadIdx.x;
      indexOfStartStoringInThisThread_ = indexForScatteredNumOfIndex_[idxInThisThread];
  }
  inline __device__ void cycle(UIN mtxIdx) {
      scatteredIndexData_[indexOfStartStoringInThisThread_ + count_] = mtxIdx;
      ++count_;
  }
  inline __device__ void done() {}

 private:
  UIN count_ = 0;
  UIN indexOfStartStoringInThisThread_;

  const UIN *indexForScatteredNumOfIndex_;
  UIN *scatteredIndexData_;
};

/**
 * grid uses two dimensions :
 *  The grid X-axis is used to iteratively compute the 'warp',
 *  The grid Y-axis is used to iteratively compute 'nnz'
 * block uses one dimensions : NUMBER_OF_THREADS_PER_BLOCK
 **/
template<typename OP>
__global__ void getIndexPerWarp_3(const UIN numWarpX,
                                  const UIN nnz,
                                  const UIN *rowIndex,
                                  const UIN *colIndex,
                                  OP op);

__global__ void mergeScatteredNumOfIndex_3(const UIN numWarpsInSDDMM,
                                           const UIN numNNZBlocks,
                                           const UIN *scatteredNumOfIndex,
                                           UIN *mergedNumOfIndex);

__global__ void sortScatteredIndexData_3(const UIN numWarpsInSDDMM,
                                         const UIN numNNZBlocks,
                                         const UIN *indexForNumOfIndex,
                                         const UIN *indexForScatteredNumOfIndex,
                                         const UIN *ScatteredIndexData,
                                         UIN *sortedIndexData);

__inline__ __device__ int warpReduce(int localSum) {
    int mask = 0xffffffff;

    localSum += __shfl_xor_sync(mask, localSum, 16);
    localSum += __shfl_xor_sync(mask, localSum, 8);
    localSum += __shfl_xor_sync(mask, localSum, 4);
    localSum += __shfl_xor_sync(mask, localSum, 2);
    localSum += __shfl_xor_sync(mask, localSum, 1);

    return localSum;
}

class updateScatteredNumOfIndexOperator_4 {
 public:
  updateScatteredNumOfIndexOperator_4(UIN *nums) : nums_(nums) {}

  inline __device__ void init(dim3 _gridDim, dim3 _blockIdx, dim3 _blockDim, dim3 _threadIdx) {
      localWarpId_ = _threadIdx.x / WARP_SIZE;
      laneId_ = _threadIdx.x % WARP_SIZE;
      const UIN numberOfDataStoredPerOneBlock = NUMBER_OF_CALCULATED_BY_ONE_BLOCK;
      const UIN numberOfDataStoredPerYGrid = _gridDim.y * numberOfDataStoredPerOneBlock;
      idx_ = numberOfDataStoredPerYGrid * _blockIdx.x + _blockIdx.y * numberOfDataStoredPerOneBlock + localWarpId_;
  }
  inline __device__ void cycle(UIN mtxIdx) {
      ++num_;
  }
  inline __device__ void done() {
      int sumNum = warpReduce(num_);
      if (laneId_ == 0) {
          nums_[idx_] = sumNum;
      }
  }

 private:
  int num_ = 0;
  UIN localWarpId_;
  UIN laneId_;
  UIN idx_;

  UIN *nums_;
};

class updateScatteredIndexDataPerWarpOperator_4 {
 public:
  updateScatteredIndexDataPerWarpOperator_4(const UIN *indexForScatteredNumOfIndex, UIN *scatteredIndexData) :
      indexForScatteredNumOfIndex_(indexForScatteredNumOfIndex), scatteredIndexData_(scatteredIndexData) {}

  inline __device__ void init(dim3 _gridDim, dim3 _blockIdx, dim3 _blockDim, dim3 _threadIdx) {
      UIN idxInThisThread = _gridDim.y * _blockDim.x * _blockIdx.x + _blockIdx.y * _blockDim.x + _threadIdx.x;
      indexOfStartStoringInThisThread_ = indexForScatteredNumOfIndex_[idxInThisThread];
  }
  inline __device__ void cycle(UIN mtxIdx) {
      scatteredIndexData_[indexOfStartStoringInThisThread_ + count_] = mtxIdx;
      ++count_;
  }
  inline __device__ void done() {}

 private:
  UIN count_ = 0;
  UIN indexOfStartStoringInThisThread_;

  const UIN *indexForScatteredNumOfIndex_;
  UIN *scatteredIndexData_;
};

template<typename OP>
__global__ void getIndexPerWarp_4(TensorCoreConfig tensorCoreConfig,
                                  const UIN numWarpX,
                                  const UIN nnz,
                                  const UIN *rowIndex,
                                  const UIN *colIndex,
                                  OP op);

__global__ void mergeScatteredNumOfIndex_4(const UIN numWarpsInSDDMM,
                                           const UIN numNNZBlocks,
                                           const UIN *scatteredNumOfIndex,
                                           UIN *mergedNumOfIndex);

#include <cuda_runtime.h>

#include "devMatrix.cuh"
#include "devMatrixKernel.cuh"
#include "parallelAlgorithm.cuh"

namespace dev {
template<typename T>
size_t Matrix<T>::rowOfValueIndex(size_t idx) const {
    if (idx == 0) {
        return 0;
    }
    if (storageOrder_ == MatrixStorageOrder::row_major) {
        return idx / leadingDimension_;
    } else {
        return idx % leadingDimension_;
    }
}

template<typename T>
size_t Matrix<T>::colOfValueIndex(size_t idx) const {
    if (idx == 0) {
        return 0;
    }
    if (storageOrder_ == MatrixStorageOrder::row_major) {
        return idx % leadingDimension_;
    } else {
        return idx / leadingDimension_;
    }
}

template<typename T>
void Matrix<T>::openTensorCoreMode(MatrixMultiplicationOrder multiplicationOrder) {
    if (tensorCoreMode_) {
        return;
    }
    tensorCoreMode_ = true;
    rowBeforeChange_ = row_;
    colBeforeChange_ = col_;

    size_t rowComplement = 0;
    size_t colComplement = 0;
    if (multiplicationOrder == MatrixMultiplicationOrder::left_multiplication) {
        rowComplement = rowBeforeChange_ % WMMA_M == 0 ? 0 : WMMA_M - rowBeforeChange_ % WMMA_M;
        colComplement = colBeforeChange_ % WMMA_K == 0 ? 0 : WMMA_K - colBeforeChange_ % WMMA_K;
    } else {
        rowComplement = rowBeforeChange_ % WMMA_K == 0 ? 0 : WMMA_K - rowBeforeChange_ % WMMA_K;
        colComplement = colBeforeChange_ % WMMA_N == 0 ? 0 : WMMA_N - colBeforeChange_ % WMMA_N;
    }

    row_ = rowBeforeChange_ + rowComplement;
    col_ = colBeforeChange_ + colComplement;
    if (storageOrder_ == MatrixStorageOrder::row_major) {
        leadingDimension_ = col_;
    } else {
        leadingDimension_ = row_;
    }

    if (storageOrder_ == MatrixStorageOrder::row_major) {
        for (size_t rowIter = 0; rowIter < rowBeforeChange_; ++rowIter) {
//            values_.insert(values_.begin() + rowIter * leadingDimension_ + colBeforeChange_, colComplement, 0);
        }
//        values_.insert(values_.end(), rowComplement * col_, 0);
    } else {
        for (size_t colIter = 0; colIter < colBeforeChange_; ++colIter) {
//            values_.insert(values_.begin() + colIter * leadingDimension_ + rowBeforeChange_, rowComplement, 0);
        }
//        values_.insert(values_.end(), colComplement * row_, 0);
    }
}

template<typename T>
void Matrix<T>::closeTensorCoreMode() {
    if (!tensorCoreMode_) {
        return;
    }
    tensorCoreMode_ = false;

    const size_t rowComplement = row_ < rowBeforeChange_ ? rowBeforeChange_ - row_ : row_ - rowBeforeChange_;
    const size_t colComplement = col_ < colBeforeChange_ ? colBeforeChange_ - col_ : col_ - colBeforeChange_;

    row_ = rowBeforeChange_;
    col_ = colBeforeChange_;
    if (storageOrder_ == MatrixStorageOrder::row_major) {
        leadingDimension_ = col_;
    } else {
        leadingDimension_ = row_;
    }
    if (storageOrder_ == MatrixStorageOrder::row_major) {
        for (size_t rowIter = 0; rowIter < rowBeforeChange_; ++rowIter) {
            const auto curRowBeginIter = values_.begin() + rowIter * leadingDimension_ + colBeforeChange_;
//            values_.erase(curRowBeginIter, curRowBeginIter + colComplement);
        }
    } else {
        for (size_t colIter = 0; colIter < colBeforeChange_; ++colIter) {
            const auto curColBeginIter = values_.begin() + colIter * leadingDimension_ + rowBeforeChange_;
//            values_.erase(curColBeginIter, curColBeginIter + rowComplement);
        }
    }
    values_.resize(row_ * col_);
}

template<typename T>
void SparseMatrix<T>::openTensorCoreMode(MatrixMultiplicationOrder multiplicationOrder) {
    if (tensorCoreMode_) {
        return;
    }
    tensorCoreMode_ = true;
    rowBeforeChange_ = row_;
    colBeforeChange_ = col_;

    size_t rowComplement;
    size_t colComplement;
    if (multiplicationOrder == MatrixMultiplicationOrder::left_multiplication) {
        rowComplement = rowBeforeChange_ % WMMA_M == 0 ? 0 : WMMA_M - rowBeforeChange_ % WMMA_M;
        colComplement = colBeforeChange_ % WMMA_K == 0 ? 0 : WMMA_K - colBeforeChange_ % WMMA_K;
    } else {
        rowComplement = rowBeforeChange_ % WMMA_K == 0 ? 0 : WMMA_K - rowBeforeChange_ % WMMA_K;
        colComplement = colBeforeChange_ % WMMA_N == 0 ? 0 : WMMA_N - colBeforeChange_ % WMMA_N;
    }
    row_ = rowBeforeChange_ + rowComplement;
    col_ = colBeforeChange_ + colComplement;
}

template<typename T>
void SparseMatrix<T>::openTensorCoreModeForSampled(TensorCoreConfig tensorCoreConfig) {
    if (tensorCoreMode_) {
        return;
    }
    tensorCoreMode_ = true;
    rowBeforeChange_ = row_;
    colBeforeChange_ = col_;

    const int rowComplement = rowBeforeChange_ % WMMA_M == 0 ? 0 : WMMA_M - rowBeforeChange_ % WMMA_M;
    const int colComplement = colBeforeChange_ % WMMA_N == 0 ? 0 : WMMA_N - colBeforeChange_ % WMMA_N;
    row_ = rowBeforeChange_ + rowComplement;
    col_ = colBeforeChange_ + colComplement;

    const size_t numTileM = row_ / WMMA_M;
    const size_t numTileN = col_ / WMMA_N;

    const size_t numWarpX = tensorCoreConfig.numWarpX();
    const size_t numWarpY = tensorCoreConfig.numWarpY();
    const size_t numWarps = numWarpX * numWarpY;

    dev::vector<UIN> numIndexPerWarp(numWarps);
    const int numThreadsPerBlock = 1024;
    const int numBlocks = (numWarps + numThreadsPerBlock - 1) / numThreadsPerBlock;
    getNumIndexPerWarp<<<numBlocks, numThreadsPerBlock>>>(numWarps,
                                                          numWarpX,
                                                          numTileM,
                                                          numTileN,
                                                          nnz_,
                                                          rowIndex_.data(),
                                                          colIndex_.data(),
                                                          numIndexPerWarp.data());
    matrixTileIndex_.resize(numWarps + 1);
    dev::fill_n(matrixTileIndex_.data(), 1, 0);
    dev::inclusive_scan(numIndexPerWarp.data(),
                        numIndexPerWarp.data() + numIndexPerWarp.size(),
                        matrixTileIndex_.data() + 1);
    const UIN numIndex = matrixTileIndex_.back();
    tileIndexPerWarp_.resize(numIndex);
    getTileIndexPerWarp<<<numBlocks, numThreadsPerBlock>>>(numWarps,
                                                           numWarpX,
                                                           numTileM,
                                                           numTileN,
                                                           nnz_,
                                                           rowIndex_.data(),
                                                           colIndex_.data(),
                                                           matrixTileIndex_.data(),
                                                           tileIndexPerWarp_.data());

//    std::set<std::pair<size_t, size_t>> rowColSet;
//    for (int idx = 0; idx < nnz_; ++idx) { // 检查是否有相同行列值
//        std::pair<size_t, size_t> rowColPair(rowIndexBeforeChange_[idx], colIndexBeforeChange_[idx]);
//        if (rowColSet.find(rowColPair) != rowColSet.end()) {
//            std::cout << " 有相同行列值1111???!!!!???!!! " << rowIndexBeforeChange_[idx] << " "
//                      << colIndexBeforeChange_[idx]
//                      << std::endl;
//            exit(1);
//        }
//        rowColSet.insert(rowColPair);
//    }
//
//    for (int idx = 0; idx < nnz_; ++idx) { // 检查是否出现不一样的值
//        std::pair<size_t, size_t> rowColPair(rowIndex_[idx], colIndex_[idx]);
//        if (rowColSet.find(rowColPair) == rowColSet.end()) {
//            std::cout << " 出现不一样的值333???!!!!???!!! " << rowIndex_[idx] << " " << rowIndex_[idx]
//                      << std::endl;
//            exit(1);
//        }
//    }

}

template<typename T>
void SparseMatrix<T>::closeTensorCoreMode() {
    if (!tensorCoreMode_) {
        return;
    }
    tensorCoreMode_ = false;
    row_ = rowBeforeChange_;
    col_ = colBeforeChange_;


    matrixTileIndex_.clear();
    tileIndexPerWarp_.clear();
}

template
class Matrix<int>;
template
class Matrix<float>;
template
class Matrix<double>;
template
class SparseMatrix<int>;
template
class SparseMatrix<float>;
template
class SparseMatrix<double>;
} // namespace dev
#include <iostream>
#include <fstream>
#include <string>
#include <random>
#include <set>
#include <unordered_map>

#include <omp.h>

#include "Matrix.hpp"
#include "util.hpp"
#include "parallelAlgorithm.cuh"

template<typename T>
Matrix<T>::Matrix(const SparseMatrix<T> &matrixS) {
    row_ = matrixS.row();
    col_ = matrixS.col();
    const UIN size = matrixS.row() * matrixS.col();
    storageOrder_ = MatrixStorageOrder::row_major;
    const UIN ld = matrixS.col();
    leadingDimension_ = ld;

    values_.clear();
    values_.resize(size);
#pragma omp parallel for
    for (int idx = 0; idx < matrixS.nnz(); ++idx) {
        const UIN curRow = matrixS.rowIndex()[idx];
        const UIN curCol = matrixS.colIndex()[idx];
        const auto curVal = matrixS.values()[idx];

        values_[curRow * ld + curCol] = curVal;
    }

    rowBeforeChange_ = row_;
    colBeforeChange_ = col_;
}

template<typename T>
UIN Matrix<T>::rowOfValueIndex(UIN idx) const {
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
UIN Matrix<T>::colOfValueIndex(UIN idx) const {
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
bool Matrix<T>::initializeValue(const std::vector<T> &src) {
    if (src.size() != row_ * col_) {
        std::cout << "Warning! Matrix value size mismatch" << std::endl;
        return false;
    }
    values_ = src;
    return true;
}

template<typename T>
void Matrix<T>::changeStorageOrder() {
    const auto oldMajorOrder = storageOrder_;
    const auto oldLd = leadingDimension_;
    const auto &oldValues = values_;

    MatrixStorageOrder newMatrixOrder;
    UIN newLd;
    std::vector<T> newValues(values_.size());
    if (oldMajorOrder == MatrixStorageOrder::row_major) {
        newMatrixOrder = MatrixStorageOrder::col_major;
        newLd = row_;

#pragma omp parallel for
        for (int idx = 0; idx < oldValues.size(); ++idx) {
            const UIN row = idx / oldLd;
            const UIN col = idx % oldLd;
            const auto val = oldValues[idx];

            newValues[col * newLd + row] = val;
        }
    } else {
        newMatrixOrder = MatrixStorageOrder::row_major;
        newLd = col_;

#pragma omp parallel for
        for (int idx = 0; idx < values_.size(); ++idx) {
            const UIN col = idx / oldLd;
            const UIN row = idx % oldLd;
            const auto val = values_[idx];

            newValues[row * newLd + col] = val;
        }
    }

    storageOrder_ = newMatrixOrder;
    leadingDimension_ = newLd;
    values_ = newValues;
}

template<typename T>
void Matrix<T>::makeData(UIN numRow, UIN numCol, MatrixStorageOrder storageOrder) {
    row_ = numRow;
    col_ = numCol;
    storageOrder_ = storageOrder;
    if (storageOrder == MatrixStorageOrder::row_major) {
        leadingDimension_ = numCol;
    } else {
        leadingDimension_ = numRow;
    }
    values_.resize(numRow * numCol);

//    for (UIN idx = 0; idx < values_.size(); ++idx) {
//        values_[idx] = idx;
//    }
    std::mt19937 generator;
    auto distribution = util::createRandomUniformDistribution(static_cast<T>(0), static_cast<T>(2));

#pragma omp parallel for
    for (int idx = 0; idx < values_.size(); ++idx) {
        values_[idx] = distribution(generator);
    }
}

template<typename T>
void Matrix<T>::print() const {
    for (auto iter : values_) {
        std::cout << iter << " ";
    }
    std::cout << std::endl;
}

template<typename T>
void Matrix<T>::printToMarkdownTable() const {
    std::cout << "| |";
    for (int colIdx = 0; colIdx < col_; ++colIdx) {
        std::cout << colIdx << "|";
    }
    std::cout << std::endl;

    std::cout << "|-|";
    for (int colIdx = 0; colIdx < col_; ++colIdx) {
        std::cout << "-|";
    }
    std::cout << std::endl;

    for (int rowIdx = 0; rowIdx < row_; ++rowIdx) {
        std::cout << "|" << rowIdx << "|";
        for (int colIdx = 0; colIdx < col_; ++colIdx) {
            std::cout << getOneValue(rowIdx, colIdx) << "|";
        }
        std::cout << std::endl;
    }
}

template<typename T>
T Matrix<T>::getOneValueForMultiplication(MatrixMultiplicationOrder multiplicationOrder,
                                          UIN rowMtxC,
                                          UIN colMtxC,
                                          UIN positionOfKIter) const {
    if (multiplicationOrder == MatrixMultiplicationOrder::left_multiplication) {
        if (rowMtxC > row_) {
            std::cout << "Warning! The input rows exceed the matrix" << std::endl;
        }
        if (storageOrder_ == MatrixStorageOrder::row_major) {
            return values_[rowMtxC * leadingDimension_ + positionOfKIter];
        } else {
            return values_[positionOfKIter * leadingDimension_ + rowMtxC];
        }
    } else {
        if (colMtxC > col_) {
            std::cout << "Warning! The input columns exceed the matrix" << std::endl;
        }
        if (storageOrder_ == MatrixStorageOrder::row_major) {
            return values_[positionOfKIter * leadingDimension_ + colMtxC];
        } else {
            return values_[colMtxC * leadingDimension_ + positionOfKIter];
        }
    }
}

template<typename T>
T Matrix<T>::getOneValue(UIN row, UIN col) const {
    if (row > row_ || col > col_) {
        std::cout << "Warning! The input rows or columns exceed the matrix" << std::endl;
    }
    if (storageOrder_ == MatrixStorageOrder::row_major) {
        return values_[row * leadingDimension_ + col];
    } else {
        return values_[col * leadingDimension_ + row];
    }
}

template<typename T>
void Matrix<T>::openTensorCoreMode(const TensorCoreConfig tensorCoreConfig,
                                   MatrixMultiplicationOrder multiplicationOrder) {
    if (tensorCoreMode_) {
        return;
    }
    tensorCoreMode_ = true;
    rowBeforeChange_ = row_;
    colBeforeChange_ = col_;

    if (multiplicationOrder == MatrixMultiplicationOrder::left_multiplication) {
        row_ = tensorCoreConfig.MForTensorCore(rowBeforeChange_);
        col_ = tensorCoreConfig.KForTensorCore(colBeforeChange_);
    } else {
        row_ = tensorCoreConfig.KForTensorCore(rowBeforeChange_);
        col_ = tensorCoreConfig.NForTensorCore(colBeforeChange_);
    }

    if (storageOrder_ == MatrixStorageOrder::row_major) {
        leadingDimension_ = col_;
    } else {
        leadingDimension_ = row_;
    }

    const UIN rowComplement = row_ - rowBeforeChange_;
    const UIN colComplement = col_ - colBeforeChange_;

    if (storageOrder_ == MatrixStorageOrder::row_major) {
        for (UIN rowIter = 0; rowIter < rowBeforeChange_; ++rowIter) {
            values_.insert(values_.begin() + rowIter * leadingDimension_ + colBeforeChange_, colComplement, 0);
        }
        values_.insert(values_.end(), rowComplement * col_, 0);
    } else {
        for (UIN colIter = 0; colIter < colBeforeChange_; ++colIter) {
            values_.insert(values_.begin() + colIter * leadingDimension_ + rowBeforeChange_, rowComplement, 0);
        }
        values_.insert(values_.end(), colComplement * row_, 0);
    }
}

template<typename T>
void Matrix<T>::closeTensorCoreMode() {
    if (!tensorCoreMode_) {
        return;
    }
    tensorCoreMode_ = false;

    const UIN rowComplement = row_ < rowBeforeChange_ ? rowBeforeChange_ - row_ : row_ - rowBeforeChange_;
    const UIN colComplement = col_ < colBeforeChange_ ? colBeforeChange_ - col_ : col_ - colBeforeChange_;

    row_ = rowBeforeChange_;
    col_ = colBeforeChange_;
    if (storageOrder_ == MatrixStorageOrder::row_major) {
        leadingDimension_ = col_;
    } else {
        leadingDimension_ = row_;
    }
    if (storageOrder_ == MatrixStorageOrder::row_major) {
        for (UIN rowIter = 0; rowIter < rowBeforeChange_; ++rowIter) {
            const auto curRowBeginIter = values_.begin() + rowIter * leadingDimension_ + colBeforeChange_;
            values_.erase(curRowBeginIter, curRowBeginIter + colComplement);
        }
    } else {
        for (UIN colIter = 0; colIter < colBeforeChange_; ++colIter) {
            const auto curColBeginIter = values_.begin() + colIter * leadingDimension_ + rowBeforeChange_;
            values_.erase(curColBeginIter, curColBeginIter + rowComplement);
        }
    }
    values_.resize(row_ * col_);
}

template<typename T>
void SparseMatrix<T>::print() const {
    std::cout << "SparseMatrix : [row,col,value]" << std::endl;
    for (UIN idx = 0; idx < nnz_; ++idx) {
        std::cout << "[" << rowIndex_[idx] << ","
                  << colIndex_[idx] << ","
                  << values_[idx] << "] ";
    }
    std::cout << std::endl;
}

template<typename T>
bool SparseMatrix<T>::setValuesFromMatrix(const Matrix<T> &inputMatrix) {
    if (inputMatrix.row() < row_ || inputMatrix.col() < col_) {
        std::cout << "Warning! The input matrix size is too small." << std::endl;
    }
    values_.clear();
    values_.resize(nnz_);

#pragma omp parallel for
    for (int idx = 0; idx < nnz_; ++idx) {
        const UIN row = rowIndex_[idx];
        const UIN col = colIndex_[idx];

        values_[idx] = inputMatrix.getOneValue(row, col);
    }

    return true;
}

template<typename T>
bool SparseMatrix<T>::initializeFromMatrixMarketFile(const std::string &filePath) {
    std::ifstream inFile;
    inFile.open(filePath, std::ios::in); // open file
    if (!inFile.is_open()) {
        std::cerr << "Error, MatrixMarket file cannot be opened : " << filePath << std::endl;
        return false;
    }

    std::cout << "SparseMatrix initialize From MatrixMarket file : " << filePath << std::endl;

    std::string line; // Store the data for each line
    getline(inFile, line); // First line does not operate

    getline(inFile, line);
    int wordIter = 0;
    row_ = std::stoi(util::iterateOneWordFromLine(line, wordIter));
    col_ = std::stoi(util::iterateOneWordFromLine(line, wordIter));
    nnz_ = std::stoi(util::iterateOneWordFromLine(line, wordIter));

    if (wordIter < line.size()) {
        std::cerr << "Error, Matrix Market file " << line << " line format is incorrect!" << std::endl;
    }

    rowIndex_.resize(nnz_);
    colIndex_.resize(nnz_);
    values_.resize(nnz_);

    UIN idx = 0;
    while (getline(inFile, line)) {
        wordIter = 0;
        const UIN row = std::stoi(util::iterateOneWordFromLine(line, wordIter)) - 1;
        const UIN col = std::stoi(util::iterateOneWordFromLine(line, wordIter)) - 1;
        const T val = static_cast<T>(std::stod(util::iterateOneWordFromLine(line, wordIter)));

        if (wordIter < line.size()) {
            std::cerr << "Error, Matrix Market file " << line << " line format is incorrect!" << std::endl;
        }

        rowIndex_[idx] = row;
        colIndex_[idx] = col;
        values_[idx] = val;

        ++idx;
    }

    inFile.close();

    rowBeforeChange_ = row_;
    colBeforeChange_ = col_;

    return true;
}

template<typename T>
void SparseMatrix<T>::getSpareMatrixOneDataByCOO(const UIN idx, UIN &row, UIN &col, T &value) const {
    row = rowIndex_[idx];
    col = colIndex_[idx];
    value = values_[idx];
}

template<typename T>
bool SparseMatrix<T>::outputToMarketMatrixFile() const {
    std::string first("matrix_");
    return outputToMarketMatrixFile(
        first + std::to_string(row_) + "_" + std::to_string(col_) + "_" + std::to_string(nnz_));
}

template<typename T>
bool SparseMatrix<T>::outputToMarketMatrixFile(const std::string &fileName) const {
    const std::string fileFormat(".mtx");

    std::string fileString(fileName + fileFormat);

    // check fileExists
    if (util::io::fileExists(fileString)) {
        std::cout << fileName + fileFormat << " file already exists" << std::endl;
        int fileId = 1;
        while (util::io::fileExists(fileName + "_" + std::to_string(fileId) + fileFormat)) {
            ++fileId;
        }
        fileString = fileName + "_" + std::to_string(fileId) + fileFormat;

        std::cout << "Change file name form \"" << fileName + fileFormat
                  << "\" to \""
                  << fileString << "\"" << std::endl;
    }

    // creat file
    std::ofstream outfile(fileString);
    if (outfile.is_open()) {
        std::cout << "File created successfully: " << fileString << std::endl;
    } else {
        std::cerr << "Unable to create file: " << fileString << std::endl;
        return false;
    }

    std::string firstLine("%%MatrixMarket matrix coordinate real general\n");
    outfile << firstLine;

    std::string secondLine(std::to_string(row_) + " " + std::to_string(col_) + " " + std::to_string(nnz_) + "\n");
    outfile << secondLine;

    for (UIN idx = 0; idx < nnz_; ++idx) {
        outfile << std::to_string(rowIndex_[idx] + 1) << " ";
        outfile << std::to_string(colIndex_[idx] + 1) << " ";
        outfile << std::to_string(values_[idx]);

        if (idx < nnz_ - 1) {
            outfile << "\n";
        }
    }

    outfile.close();
    return true;
}

template<typename T>
void SparseMatrix<T>::makeData(const UIN numRow, const UIN numCol, const UIN nnz) {
    if (numRow * numCol < nnz) {
        std::cerr << "nnz is too big" << std::endl;
        return;
    }
    row_ = numRow;
    col_ = numCol;
    nnz_ = nnz;

    rowIndex_.resize(nnz);
    colIndex_.resize(nnz);
    values_.resize(nnz);

    // make data
    std::mt19937 generator;
    auto distributionRow =
        util::createRandomUniformDistribution(static_cast<UIN>(0), static_cast<UIN>(numRow - 1));
    auto distributionCol =
        util::createRandomUniformDistribution(static_cast<UIN>(0), static_cast<UIN>(numCol - 1));
    auto distributionValue = util::createRandomUniformDistribution(static_cast<T>(1), static_cast<T>(10));
    std::set<std::pair<UIN, UIN>> rowColSet;
    for (UIN idx = 0; idx < nnz; ++idx) {
        UIN row = distributionRow(generator);
        UIN col = distributionCol(generator);
        std::pair<UIN, UIN> rowColPair(row, col);
        auto findSet = rowColSet.find(rowColPair);
        while (findSet != rowColSet.end()) {
            row = distributionRow(generator);
            col = distributionCol(generator);
            rowColPair.first = row;
            rowColPair.second = col;
            findSet = rowColSet.find(rowColPair);
        }

        rowColSet.insert(rowColPair);

        rowIndex_[idx] = row;
        colIndex_[idx] = col;
        values_[idx] = distributionValue(generator);
    }

    // sort rowIndex and colIndex
    host::sort_by_key(rowIndex_.data(), rowIndex_.data() + rowIndex_.size(), colIndex_.data());
    UIN lastRowNumber = rowIndex_[0];
    UIN lastBegin = 0;
    for (UIN idx = 0; idx < nnz_; ++idx) {
        const UIN curRowNumber = rowIndex_[idx];
        if (curRowNumber != lastRowNumber) { // new row
            host::sort(colIndex_.data() + lastBegin, colIndex_.data() + idx);

            lastBegin = idx + 1;
            lastRowNumber = curRowNumber;
        }

        if (idx == nnz_ - 1) {
            host::sort(colIndex_.data() + lastBegin, colIndex_.data() + colIndex_.size());
        }
    }
}

template<typename T>
void SparseMatrix<T>::openTensorCoreMode(const TensorCoreConfig tensorCoreConfig,
                                         MatrixMultiplicationOrder multiplicationOrder) {
    if (tensorCoreMode_) {
        return;
    }
    tensorCoreMode_ = true;
    rowBeforeChange_ = row_;
    colBeforeChange_ = col_;

    if (multiplicationOrder == MatrixMultiplicationOrder::left_multiplication) {
        row_ = tensorCoreConfig.MForTensorCore(rowBeforeChange_);
        col_ = tensorCoreConfig.KForTensorCore(colBeforeChange_);
    } else {
        row_ = tensorCoreConfig.KForTensorCore(rowBeforeChange_);
        col_ = tensorCoreConfig.NForTensorCore(colBeforeChange_);
    }
}

template<typename T>
void SparseMatrix<T>::openTensorCoreModeForSampled(TensorCoreConfig tensorCoreConfig) {
    if (tensorCoreMode_) {
        return;
    }
    tensorCoreMode_ = true;
    rowBeforeChange_ = row_;
    colBeforeChange_ = col_;
    rowIndexBeforeChange_ = rowIndex_;
    colIndexBeforeChange_ = colIndex_;
    valuesBeforeChange_ = values_;

    row_ = tensorCoreConfig.MForTensorCore(rowBeforeChange_);
    col_ = tensorCoreConfig.NForTensorCore(colBeforeChange_);

    const UIN numTileM = row_ / WMMA_M;
    const UIN numTileN = col_ / WMMA_N;

    const UIN numWarpX = tensorCoreConfig.numWarpX();
    const UIN numWarpY = tensorCoreConfig.numWarpY();
    const UIN numWarps = numWarpX * numWarpY;

    std::vector<std::vector<UIN>> indexVectorsPerWarp(numWarps);
    std::vector<UIN> numIndexPerTile(numWarps);
#pragma omp parallel for
    for (int warpId = 0; warpId < numWarps; ++warpId) { // Matrix tiles id: row-order
        const int curWarpX = warpId % numWarpX;
        const int curWarpY = warpId / numWarpX;
        if (curWarpX > numTileN || curWarpY > numTileM) {
            continue;
        }
        const UIN rowBeginOfTile = (warpId / numWarpX) * WMMA_M;
        const UIN rowEndOfTile = (warpId / numWarpX + 1) * WMMA_M;
        const UIN colBeginOfTile = (warpId % numWarpX) * WMMA_N;
        const UIN colEndOfTile = (warpId % numWarpX + 1) * WMMA_N;
        for (int idx = 0; idx < nnz_; ++idx) {
            const UIN curRow = rowIndexBeforeChange_[idx];
            const UIN curCol = colIndexBeforeChange_[idx];
            if (curRow >= rowBeginOfTile && curRow < rowEndOfTile &&
                curCol >= colBeginOfTile && curCol < colEndOfTile) {
                indexVectorsPerWarp[warpId].push_back(idx);
            }
        }
        numIndexPerTile[warpId] = indexVectorsPerWarp[warpId].size();
    }

    matrixTileIndexForTensorCore_.resize(numWarps + 1);
    matrixTileIndexForTensorCore_[0] = 0;
    host::inclusive_scan(numIndexPerTile.data(),
                         numIndexPerTile.data() + numIndexPerTile.size(),
                         matrixTileIndexForTensorCore_.data() + 1);

#pragma omp parallel for
    for (int warpId = 0; warpId < numWarps; ++warpId) {
        const auto &curIndexVector = indexVectorsPerWarp[warpId];
        for (int idx = 0; idx < curIndexVector.size(); ++idx) {
            const int newIdx = matrixTileIndexForTensorCore_[warpId] + idx;
            rowIndex_[newIdx] = rowIndexBeforeChange_[curIndexVector[idx]];
            colIndex_[newIdx] = colIndexBeforeChange_[curIndexVector[idx]];
            values_[newIdx] = valuesBeforeChange_[curIndexVector[idx]];
        }
    }

//    std::set<std::pair<UIN, UIN>> rowColSet;
//    for (int idx = 0; idx < nnz_; ++idx) { // 检查是否有相同行列值
//        std::pair<UIN, UIN> rowColPair(rowIndexBeforeChange_[idx], colIndexBeforeChange_[idx]);
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
//        std::pair<UIN, UIN> rowColPair(rowIndex_[idx], colIndex_[idx]);
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
    rowIndex_ = rowIndexBeforeChange_;
    colIndex_ = colIndexBeforeChange_;
    values_ = valuesBeforeChange_;

    rowIndexBeforeChange_.clear();
    colIndexBeforeChange_.clear();
    valuesBeforeChange_.clear();
    matrixTileIndexForTensorCore_.clear();
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
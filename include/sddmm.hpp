#pragma once

#include "Matrix.hpp"
#include "Logger.hpp"
#include "Options.hpp"

// Reordering method
void sddmm(const Matrix<float> &matrixA,
           const Matrix<float> &matrixB,
           const float alpha, const float beta,
           const sparseMatrix::CSR<float> &matrixS,
           sparseMatrix::CSR<float> &matrixP,
           Logger &logger);

// Error check
bool check_sddmm(const Matrix<float> &matrixA,
                 const Matrix<float> &matrixB,
                 const float alpha, const float beta,
                 const sparseMatrix::CSR<float> &matrixS,
                 const sparseMatrix::CSR<float> &matrixP);
#include "sddmm.hpp"
#include "sddmmKernel.cuh"
#include "CudaTimeCalculator.cuh"
#include "host.hpp"
#include "checkData.hpp"
#include "ReBELL.hpp"

// The old method, directly uses TensorCore calculation
void sddmm(Matrix<float> &matrixA,
           Matrix<float> &matrixB,
           sparseMatrix::COO<float> &matrixS,
           sparseMatrix::COO<float> &matrixP) {

    TensorCoreConfig tensorCoreConfig(matrixS.row(), matrixS.col());

    printf("Kernel gridDim : [%d,%d,%d], blockDim : [%d,%d,%d]\n",
           tensorCoreConfig.gridDim().x, tensorCoreConfig.gridDim().y, tensorCoreConfig.gridDim().z,
           tensorCoreConfig.blockDim().x, tensorCoreConfig.blockDim().y, tensorCoreConfig.blockDim().z);
    printf("[WMMA_M : %d], [WMMA_N : %d], [WMMA_K : %d]\n", WMMA_M, WMMA_N, WMMA_K);

    matrixA.openTensorCoreMode(tensorCoreConfig, MatrixMultiplicationOrder::left_multiplication);
    printf("openTensorCoreMode matrixA : row = %d, col = %d\n", matrixA.row(), matrixA.col());
    matrixB.openTensorCoreMode(tensorCoreConfig, MatrixMultiplicationOrder::right_multiplication);
    printf("openTensorCoreMode matrixB : row = %d, col = %d\n", matrixB.row(), matrixB.col());

    //
    dev::vector<MATRIX_A_TYPE> matrixA_values_convertedType(matrixA.size());
    dev::vector<MATRIX_B_TYPE> matrixB_values_convertedType(matrixB.size());
    {
        dev::vector<float> matrixA_values_dev(matrixA.values());
        dev::vector<float> matrixB_values_dev(matrixB.values());

        const int numThreadPerBlock = 1024;
        kernel::convertDataType<<< (matrixA.size() + numThreadPerBlock - 1) / numThreadPerBlock, numThreadPerBlock>>>(
            matrixA.size(), matrixA_values_dev.data(), matrixA_values_convertedType.data());
        kernel::convertDataType<<< (matrixB.size() + numThreadPerBlock - 1) / numThreadPerBlock, numThreadPerBlock>>>(
            matrixB.size(), matrixB_values_dev.data(), matrixB_values_convertedType.data());
    }

    CudaTimeCalculator timeCalculator;

    timeCalculator.startClock();
    matrixS.openTensorCoreModeForSampled(tensorCoreConfig);
    timeCalculator.endClock();
    const float openTensorCoreModeForSampled_time = timeCalculator.getTime();
    printf("openTensorCoreModeForSampled matrixS : row = %d, col = %d\n", matrixS.row(), matrixS.col());

    dev::vector<UIN> matrixS_rowIndex_coo(matrixS.rowIndices());
    dev::vector<UIN> matrixS_colIndex_coo(matrixS.colIndices());
    dev::vector<UIN> matrixS_matrixTileMappedToWarpIndex_coo(matrixS.matrixTileMappedToWarpIndex());
    dev::vector<float> matrixS_value_coo(matrixS.values());
    dev::vector<float> matrixP_value_coo3(matrixS.values());
    timeCalculator.startClock();
    sddmm_gpu_coo_3(tensorCoreConfig,
                    matrixS.row(),
                    matrixS.col(),
                    matrixA.col(),
                    matrixA_values_convertedType.data(),
                    matrixA.storageOrder(),
                    matrixB_values_convertedType.data(),
                    matrixB.storageOrder(),
                    matrixS_rowIndex_coo.data(),
                    matrixS_colIndex_coo.data(),
                    matrixS_value_coo.data(),
                    matrixS_matrixTileMappedToWarpIndex_coo.data(),
                    matrixP_value_coo3.data());
    timeCalculator.endClock();
    const float time_sddmm_gpu_coo3 = timeCalculator.getTime();
    std::cout << "Func time_sddmm_gpu_coo3 time : " << time_sddmm_gpu_coo3 << " ms" << std::endl;

    matrixP.setValues() = d2h(matrixP_value_coo3);

    std::cout << "check matrixP_cpu_res and sddmm_gpu_coo_3 : " << std::endl;

    sparseMatrix::COO<float> matrixP_cpu_res(matrixS);

    timeCalculator.startClock();
    // comp by cpu
    sddmm_cpu(matrixA, matrixB, matrixS, matrixP_cpu_res);
    timeCalculator.endClock();
    std::cout << "Func sddmm_cpu time : " << timeCalculator.getTime() << " ms" << std::endl;

    size_t numError_3 = 0;
    if (!checkData(matrixP_cpu_res.values(), matrixP_value_coo3, numError_3)) {
        printf("[checkData : NO PASS Error rate : %2.2f%%]\n",
               static_cast<float>(numError_3) / static_cast<float>(matrixP_cpu_res.values().size()) * 100);
    }

    std::cout << "closeTensorCoreMode" << std::endl;
    matrixA.closeTensorCoreMode();
    matrixB.closeTensorCoreMode();
    matrixS.closeTensorCoreMode();

    const float time_sddmm_zcx = openTensorCoreModeForSampled_time + time_sddmm_gpu_coo3;
    std::cout << "sddmm_zcx time : " << time_sddmm_zcx << " ms" << std::endl;

    printf("[zcx_sddmm_oldMethod : %.2f]\n", time_sddmm_gpu_coo3);
    printf("[zcx_other_oldMethod : %.2f]\n", openTensorCoreModeForSampled_time);
    printf("[zcx_oldMethod : %.2f]\n", time_sddmm_zcx);
}

// Reordering method
void sddmm(const Matrix<float> &matrixA,
           const Matrix<float> &matrixB,
           const float alpha, const float beta,
           const sparseMatrix::CSR<float> &matrixS,
           sparseMatrix::CSR<float> &matrixP,
           Logger &logger) {

    // Reordering
    float rebell_time;
    ReBELL rebell(matrixS, rebell_time);

    const auto [maxDensity, minDensity] = rebell.calculateMaxMinDensity();
    printf("rebell : numBlock = %d, average density = %f, max average = %f, min average = %f\n",
           rebell.getNumBlocks(),
           rebell.calculateAverageDensity(),
           maxDensity,
           minDensity);

    const auto [modeDensity, frequency] = rebell.calculateDensityMode();
    printf("rebell : mode density = %f, frequency = %d\n", modeDensity, frequency);

    const auto [numTiles, averageDensity] = calculateNumTilesAndAverageDensityInOriginalMatrix(matrixS);
    printf("Number of tiles before reordering: %d, average density : %f\n",
           numTiles, averageDensity);

    logger.zcx_other_time_ = rebell_time;

    // Error check
//    check_rebell(matrixS, rebell);

    // sddmm comp by gpu
    sddmm_gpu_rebell(matrixA, matrixB, alpha, beta, matrixS, rebell, matrixP, logger);

    // Error check
//    check_sddmm(matrixA, matrixB, matrixS, matrixP);
}

bool check_sddmm(const Matrix<float> &matrixA,
                 const Matrix<float> &matrixB,
                 const sparseMatrix::CSR<float> &matrixS,
                 const sparseMatrix::CSR<float> &matrixP) {

    // sddmm comp by cpu
    sparseMatrix::CSR<float> matrixP_cpu_res(matrixS);
    sddmm_cpu(matrixA, matrixB, matrixS, matrixP_cpu_res);

    // Error check
    printf("check rebell sddmm : \n");
    size_t numError = 0;
    if (!checkData(matrixP_cpu_res.values(), matrixP.values(), numError)) {
        printf("[checkData : NO PASS Error rate : %2.2f%%]\n",
               static_cast<float>(numError) / static_cast<float>(matrixP.values().size()) * 100);
        return false;
    }

    return true;
}
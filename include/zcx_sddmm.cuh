#pragma once

#include "Matrix.hpp"
#include "devVector.cuh"
#include "CudaTimeCalculator.cuh"
#include "kernel.cuh"
#include "checkData.hpp"

class zcx_sddmm {
 public:
  zcx_sddmm(TensorCoreConfig tensorCoreConfig,
            const Matrix<float> &matrixA,
            const Matrix<float> &matrixB,
            const Matrix<float> &matrixS){

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

      SparseMatrix<float> matrixP_cpu_res(matrixS.row(), matrixS.col(), matrixS.nnz(),
                                          matrixS.rowIndices(), matrixS.colIndices());

      timeCalculator.startClock();
      // comp by cpu
      sddmm_cpu(matrixA, matrixB, matrixS, matrixP_cpu_res);
      timeCalculator.endClock();
      std::cout << "Func sddmm_cpu time : " << timeCalculator.getTime() << " ms" << std::endl;

      dev::vector<UIN> matrixS_rowIndex_coo(matrixS.rowIndices());
      dev::vector<UIN> matrixS_colIndex_coo(matrixS.colIndices());
      dev::vector<UIN> matrixS_matrixTileMappedToWarpIndex_coo(matrixS.matrixTileMappedToWarpIndex());
      dev::vector<float> matrixS_value_coo(matrixS.values());
      dev::vector<float> matrixP_value_coo3(matrixS.nnz());
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

      std::cout << "check matrixP_cpu_res and sddmm_gpu_coo_3 : " << std::endl;

      size_t numError_3 = 0;
      if (!checkData(matrixP_cpu_res.values(), matrixP_value_coo3, numError_3)) {
          printf("@checkData : NO PASS Error rate : %2.2f%% @\n",
                 static_cast<float>(numError_3) / static_cast<float>(matrixP_cpu_res.values().size()) * 100);
      }

      std::cout << "closeTensorCoreMode" << std::endl;
      matrixA.closeTensorCoreMode();
      matrixB.closeTensorCoreMode();
      matrixS.closeTensorCoreMode();

      const float time_sddmm_zcx = openTensorCoreModeForSampled_time + time_sddmm_gpu_coo3;
      std::cout << "sddmm_zcx time : " << time_sddmm_zcx << " ms" << std::endl;

      printf("@zcx_sddmm : %.2f @\n", time_sddmm_gpu_coo3);
      printf("@zcx_other : %.2f @\n", openTensorCoreModeForSampled_time);
      printf("@zcx : %.2f @\n", time_sddmm_zcx);
  };

  float getTime() {
      return initTime_ + sddmmTime_;
  }

 private:

  float initTime_;
  float sddmmTime_;
};
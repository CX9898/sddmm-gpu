#pragma once

#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "devVector.cuh"

inline void printCudaErrorStringSync() {
    fprintf(stderr, "CUDA Error : %s\n", cudaGetErrorString(cudaDeviceSynchronize()));
}
inline void cudaSync() {
    cudaDeviceSynchronize();
}

namespace host {
void fill_n(uint32_t *first, size_t size, uint32_t val);
void sort(uint32_t *first, uint32_t *last);
void sort(uint64_t *first, uint64_t *last);
void sort_by_key(uint32_t *key_first, uint32_t *key_last, uint32_t *value_first);
void sort_by_key(uint64_t *key_first, uint64_t *key_last, uint64_t *value_first);
void sort_by_key(uint64_t *key_first, uint64_t *key_last, float *value_first);
void inclusive_scan(size_t *first, size_t *last, size_t *result);
void inclusive_scan(uint32_t *first, uint32_t *last, uint32_t *result);
} // namespace host

namespace dev {
void fill_n(uint32_t *first, size_t size, uint32_t val);
void sort(uint32_t *first, uint32_t *last);
void sort(uint64_t *first, uint64_t *last);
void sort_by_key(uint32_t *key_first, uint32_t *key_last, uint32_t *value_first);
void sort_by_key(uint64_t *key_first, uint64_t *key_last, uint64_t *value_first);
void sort_by_key(uint64_t *key_first, uint64_t *key_last, float *value_first);
void inclusive_scan(size_t *first, size_t *last, size_t *result);
void inclusive_scan(uint32_t *first, uint32_t *last, uint32_t *result);
} // namespace dev
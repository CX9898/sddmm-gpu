#pragma once

#include <vector>

/**
 * error checking
 **/
bool checkData(const size_t num, const float *data1, const float *data2);

bool checkData(const std::vector<float> &data1, const std::vector<float> &data2);

bool checkData(const size_t num, const std::vector<float> &dataHost1, const float *dataDev2);

bool checkData(const size_t num, const float *dataDev1, const std::vector<float> &dataHost2);

bool checkDevData(const size_t num, const float *dataDev1, const float *dataDev2);
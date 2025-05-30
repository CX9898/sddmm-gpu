#include <cstdio>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <unordered_set>
#include <unordered_map>
#include <map>
#include <algorithm>
#include <utility>
#include <limits>

const std::string dataSplitSymbol("---New data---");

std::string findWord(const std::string &line, const std::string &word) {
    size_t findIdx = line.find(word);
    if (findIdx != std::string::npos) {
        const size_t beginIdx = findIdx + 1;
        size_t endIdx = beginIdx + 1;
        while (line[endIdx++] != ']') {}
        return line.substr(beginIdx, endIdx - beginIdx - 1);
    }
    return "";
}

std::string findWord(const std::vector<std::string> &multiLine, const std::string &word) {
    std::string value;
    for (const std::string &line : multiLine) {
        value = findWord(line, word);
        if (!value.empty()) {
            break;
        }
    }
    return value;
}

std::string getValue(const std::string &line, const std::string &word) {
    size_t findIdx = line.find(word);
    if (findIdx != std::string::npos) {
        const size_t beginIdx = line.find(word) + word.size();
        size_t endIdx = beginIdx;
        while (line[endIdx++] != ']') {}
        return line.substr(beginIdx, endIdx - beginIdx - 1);
    }
    return "";
}

std::string getValue(const std::vector<std::string> &multiLine, const std::string &word) {
    std::string value;
    for (const std::string &line : multiLine) {
        value = getValue(line, word);
        if (!value.empty()) {
            break;
        }
    }
    return value;
}

// Initialize variables and check if they are different
bool initOperationOrCheckIfDifferent(std::string &src, const std::string &data) {
    if (src.empty()) {
        src = data;
    } else {
        if (!data.empty() && src != data) {
            fprintf(stderr, "Error, the value is different. src : %s, data : %s\n", src.c_str(), data.c_str());
            return false;
        }
    }
    return true;
}

struct SettingInformation {
  bool initInformation(const std::vector<std::string> &oneTimeData);

  void printInformation() const;

  std::string buildType_;
  std::string device_;

  std::string wmma_m_;
  std::string wmma_n_;
  std::string wmma_k_;

  std::string blockDim_dense_;
  std::string blockDim_sparse_;

  std::string matrixA_type_;
  std::string matrixB_type_;
  std::string matrixC_type_;

  std::string matrixA_storageOrder_;
  std::string matrixB_storageOrder_;
  std::string matrixC_storageOrder_;
};

// init the setting information, if setting information is already initialized, and the new data is different, than return false
bool SettingInformation::initInformation(const std::vector<std::string> &oneTimeResults) {
    std::string buildType, device, wmma_m, wmma_n, wmma_k, blockDim_dense, blockDim_sparse, matrixA_type, matrixB_type,
        matrixC_type, matrixA_storageOrder, matrixB_storageOrder, matrixC_storageOrder;

    for (const std::string &line : oneTimeResults) {
        buildType = buildType.empty() ? findWord(line, "[Build type : ") : buildType;
        device = device.empty() ? findWord(line, "[Device : ") : device;
        wmma_m = wmma_m.empty() ? findWord(line, "[WMMA_M : ") : wmma_m;
        wmma_n = wmma_n.empty() ? findWord(line, "[WMMA_N : ") : wmma_n;
        wmma_k = wmma_k.empty() ? findWord(line, "[WMMA_K : ") : wmma_k;
        blockDim_dense = blockDim_dense.empty() ? findWord(line, "[blockDim_dense : ") : blockDim_dense;
        blockDim_sparse = blockDim_sparse.empty() ? findWord(line, "[blockDim_sparse : ") : blockDim_sparse;
        matrixA_type = matrixA_type.empty() ? findWord(line, "[matrixA type : ") : matrixA_type;
        matrixB_type = matrixB_type.empty() ? findWord(line, "[matrixB type : ") : matrixB_type;
        matrixC_type = matrixC_type.empty() ? findWord(line, "[matrixC type : ") : matrixC_type;
        matrixA_storageOrder = matrixA_storageOrder.empty() ? findWord(line,
                                                                       "[matrixA storageOrder : ")
                                                            : matrixA_storageOrder;
        matrixB_storageOrder = matrixB_storageOrder.empty() ? findWord(line,
                                                                       "[matrixB storageOrder : ")
                                                            : matrixB_storageOrder;
        matrixC_storageOrder = matrixC_storageOrder.empty() ? findWord(line,
                                                                       "[matrixC storageOrder : ")
                                                            : matrixC_storageOrder;
    }

    if (!initOperationOrCheckIfDifferent(buildType_, buildType)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(device_, device)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(wmma_m_, wmma_m)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(wmma_n_, wmma_n)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(wmma_k_, wmma_k)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(blockDim_dense_, blockDim_dense)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(blockDim_sparse_, blockDim_sparse)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(matrixA_type_, matrixA_type)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(matrixB_type_, matrixB_type)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(matrixC_type_, matrixC_type)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(matrixA_storageOrder_, matrixA_storageOrder)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(matrixB_storageOrder_, matrixB_storageOrder)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(matrixC_storageOrder_, matrixC_storageOrder)) {
        return false;
    }

    return true;
}

void SettingInformation::printInformation() const {
    auto printOneInformation = [](const std::string &information) -> void {
      if (!information.empty()) {
          printf("- %s\n", information.c_str());
      }
    };

    printf("\n");

    printOneInformation(device_);
    printOneInformation(buildType_);
    printOneInformation(wmma_m_);
    printOneInformation(wmma_n_);
    printOneInformation(wmma_k_);
    printOneInformation(blockDim_dense_);
    printOneInformation(blockDim_sparse_);
    printOneInformation(matrixA_type_);
    printOneInformation(matrixB_type_);
    printOneInformation(matrixC_type_);
    printOneInformation(matrixA_storageOrder_);
    printOneInformation(matrixB_storageOrder_);
    printOneInformation(matrixC_storageOrder_);

    printf("\n");
}

struct OneTimeData {
  void initInformation(const std::vector<std::string> &oneTimeResults);

  std::string zcx_gflops_;
  std::string cuSDDMM_gflops_;
  std::string cuSparse_gflops_;
  std::string RoDe_gflops_;
  std::string ASpT_gflops_;

  std::string checkResults_;
};

void OneTimeData::initInformation(const std::vector<std::string> &oneTimeResults) {
    for (const std::string &line : oneTimeResults) {
        zcx_gflops_ = zcx_gflops_.empty() ? getValue(line, "[zcx_gflops : ") : zcx_gflops_;
        cuSDDMM_gflops_ = cuSDDMM_gflops_.empty() ? getValue(line, "[cuSDDMM_gflops : ") : cuSDDMM_gflops_;
        cuSparse_gflops_ = cuSparse_gflops_.empty() ? getValue(line, "[cuSparse_gflops : ") : cuSparse_gflops_;
        RoDe_gflops_ = RoDe_gflops_.empty() ? getValue(line, "[RoDe_gflops : ") : RoDe_gflops_;
        ASpT_gflops_ = ASpT_gflops_.empty() ? getValue(line, "[ASpT_gflops : ") : ASpT_gflops_;

        checkResults_ = checkResults_.empty() ? getValue(line, "[checkResults : ") : checkResults_;
    }
}

struct ResultsInformation {
  bool initInformation(const std::vector<std::string> &oneTimeResults);

  void printInformation() const;

  bool empty() const {
      return kToOneTimeData_.empty();
  }

  std::string file_;
  std::string M_;
  std::string N_;
  std::string NNZ_;
  std::string sparsity_;

  std::map<int, OneTimeData> kToOneTimeData_;
};

bool ResultsInformation::initInformation(const std::vector<std::string> &oneTimeResults) {
    std::string file, M, N, NNZ, sparsity, K_str;
    for (const std::string &line : oneTimeResults) {
        file = file.empty() ? getValue(line, "[File : ") : file;
        M = M.empty() ? getValue(line, "[M : ") : M;
        N = N.empty() ? getValue(line, "[N : ") : N;
        NNZ = NNZ.empty() ? getValue(line, "[NNZ : ") : NNZ;
        sparsity = sparsity.empty() ? getValue(line, "[sparsity : ") : sparsity;
        K_str = K_str.empty() ? getValue(line, "[K : ") : K_str;
    }

    if (!initOperationOrCheckIfDifferent(file_, file)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(M_, M)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(N_, N)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(NNZ_, NNZ)) {
        return false;
    }
    if (!initOperationOrCheckIfDifferent(sparsity_, sparsity)) {
        return false;
    }

    int k = std::stoi(K_str);
    if (kToOneTimeData_.find(k) == kToOneTimeData_.end()) {
        kToOneTimeData_[k] = OneTimeData();
    }
    kToOneTimeData_[k].initInformation(oneTimeResults);

    return true;
}

std::string getFileName(const std::string &path) {
    if (path.empty()) return "";

    const size_t pos = path.find_last_of("/\\");
    if (pos == std::string::npos) {
        std::cerr << "Warning. The input path has no parent folder" << std::endl;
    }
    const std::string filename = (pos == std::string::npos) ? path : path.substr(pos + 1);
    return filename;
}

void ResultsInformation::printInformation() const {

    printf("## M : %s, N: %s, sparsity: %s, file: %s\n",
           M_.c_str(), N_.c_str(), sparsity_.c_str(), file_.c_str());

    const int numColAttributes = 10;

    // print the head of the list
    printf("\n");
    printf("|");
    printf(" M |");
    printf(" N |");
    printf(" NNZ |");
    printf(" sparsity |");
    printf(" K |");
    printf(" zcx_gflops |");
    printf(" cuSDDMM_gflops |");
    printf(" cuSparse_gflops |");
    printf(" RoDe_gflops |");
    printf(" ASpT_gflops |");

    printf("\n");

    // print the split line
    const int numColData = numColAttributes;
    printf("|");
    for (int i = 0; i < numColData; ++i) {
        printf("-|");
    }
    printf("\n");

    auto printOneLineInformation = [](const std::string &information) -> void {
      std::cout << information << "|";
    };

    // Print data line by line
    for (const auto &iter : kToOneTimeData_) {
        printf("|");
        printOneLineInformation(M_);
        printOneLineInformation(N_);
        printOneLineInformation(NNZ_);
        printOneLineInformation(sparsity_);
        std::cout << iter.first << "|"; // K value
        printOneLineInformation(iter.second.zcx_gflops_);
        printOneLineInformation(iter.second.cuSDDMM_gflops_);
        printOneLineInformation(iter.second.cuSparse_gflops_);
        printOneLineInformation(iter.second.RoDe_gflops_);
        printOneLineInformation(iter.second.ASpT_gflops_);

        std::cout << iter.second.checkResults_;
        printf("\n");
    }

    printf("\n");
}

// return the data in the file
std::vector<std::vector<std::string>> readResultsFile(const std::string &resultsFile) {
    std::vector<std::vector<std::string>> allData;

    std::ifstream inFile;
    inFile.open(resultsFile, std::ios::in); // open file
    if (!inFile.is_open()) {
        std::cerr << "Error, Results file cannot be opened : " << resultsFile << std::endl;
    }

    std::vector<std::string> oneTimeData;
    std::string line; // Store the data for each line
    while (getline(inFile, line)) {
        if (line == dataSplitSymbol) {
            allData.push_back(oneTimeData);
            oneTimeData.clear();
            continue;
        }
        oneTimeData.push_back(line);
    }
    if (!oneTimeData.empty()) {
        allData.push_back(oneTimeData);
    }

    return allData;
}

int getIntValue(const std::string &value) {
    return value.empty() ? 0 : std::stoi(value);
}

float getFloatValue(const std::string &value) {
    return value.empty() ? 0.0f : std::stof(value);
}

std::unordered_map<std::string, ResultsInformation> pickTheBadResults(
    const std::unordered_map<std::string, ResultsInformation> &matrixFileToResultsInformationMap) {
    std::unordered_map<std::string, ResultsInformation> bad;

    for (const auto &iter : matrixFileToResultsInformationMap) {
        const std::string file = iter.first;
        const ResultsInformation &resultesInformation = iter.second;

        ResultsInformation badResultsInformation(resultesInformation);
        badResultsInformation.kToOneTimeData_.clear();
        for (const auto &kToOneTimeData : resultesInformation.kToOneTimeData_) {
            const int k = kToOneTimeData.first;
            const float zcx_gflops = getFloatValue(kToOneTimeData.second.zcx_gflops_);
            const float cuSDDMM_gflops = getFloatValue(kToOneTimeData.second.cuSDDMM_gflops_);
            const float cuSparse_gflops = getFloatValue(kToOneTimeData.second.cuSparse_gflops_);
            if (zcx_gflops > 1e-6) {
                if (zcx_gflops < cuSDDMM_gflops || zcx_gflops < cuSparse_gflops) {
                    OneTimeData oneTimeData = kToOneTimeData.second;
                    badResultsInformation.kToOneTimeData_[k] = oneTimeData;
                }
            }

            const float RoDe_gflops = getFloatValue(kToOneTimeData.second.RoDe_gflops_);
            const float ASpT_gflops = getFloatValue(kToOneTimeData.second.ASpT_gflops_);
            if (zcx_gflops > 1e-6) {
                if (zcx_gflops < RoDe_gflops || zcx_gflops < ASpT_gflops) {
                    OneTimeData oneTimeData = kToOneTimeData.second;
                    badResultsInformation.kToOneTimeData_[k] = oneTimeData;
                }
            }
        }
        if (!badResultsInformation.empty()) {
            bad[file] = badResultsInformation;
        }
    }

    return bad;
}

int getNumResults(const std::unordered_map<std::string, ResultsInformation> &matrixFileToResultsInformationMap) {
    int numResults = 0;
    for (const auto &iter : matrixFileToResultsInformationMap) {
        numResults += iter.second.kToOneTimeData_.size();

        for (const auto &kToOneTimeData : iter.second.kToOneTimeData_) {
            const float zcx_sddmm = getFloatValue(kToOneTimeData.second.zcx_gflops_);

            if (zcx_sddmm <= 1e-6) {
                --numResults;
            }
        }
    }

    return numResults;
}

bool checkIsCorrect(const std::string &checkResults) {
    std::string str = checkResults;
    std::transform(str.begin(), str.end(), str.begin(), ::tolower);

    bool isNoPass = checkResults.find("no pass");

    if (isNoPass) {
        float errorRate = 0.0f;
        const size_t beginIdx = str.find("error rate : ");
        const size_t endIdx = str.find("%");
        if (beginIdx != std::string::npos && endIdx != std::string::npos) {
            errorRate = std::stof(str.substr(beginIdx + 13, endIdx - beginIdx - 13));
        }

        if (errorRate > 1e-6) {
            return false;
        }
    }

    return true;
}

float calculateAccuracy(const std::unordered_map<std::string,
                                                 ResultsInformation> &matrixFileToResultsInformationMap) {
    const int numResults = getNumResults(matrixFileToResultsInformationMap);
    int numErrors = 0;
    for (const auto &iter : matrixFileToResultsInformationMap) {
        for (const auto &kToOneTimeData : iter.second.kToOneTimeData_) {
            bool isCorrect = checkIsCorrect(kToOneTimeData.second.checkResults_);

            if (!isCorrect) {
                ++numErrors;
            }
        }
    }

    return 1.0f - static_cast<float>(numErrors) / numResults;
}

// return the average speedup adn the maximum speedup
std::pair<float, float> calculateAverageAndMaxSpeedupWithCuSDDMM(
    std::unordered_map<std::string, ResultsInformation> &matrixFileToResultsInformationMap) {
    float sumSpeedup = 0.0f;
    float maxSpeedup = 0.0f;

    const int numResults = getNumResults(matrixFileToResultsInformationMap);
    for (const auto &iter : matrixFileToResultsInformationMap) {
        for (const auto &kToOneTimeData : iter.second.kToOneTimeData_) {
            const float zcx_gflops = getFloatValue(kToOneTimeData.second.zcx_gflops_);
            const float cuSDDMM_gflops = getFloatValue(kToOneTimeData.second.cuSDDMM_gflops_);

            if (zcx_gflops <= 1e-6 || cuSDDMM_gflops <= 1e-6) {
                continue;
            }

            float speedup = zcx_gflops / cuSDDMM_gflops;
            maxSpeedup = std::max(speedup, maxSpeedup);
            sumSpeedup += speedup;
        }
    }

    float averageSpeedup = sumSpeedup / numResults;

    return std::make_pair(averageSpeedup, maxSpeedup);
}

// return the average speedup adn the maximum speedup
std::pair<float, float> calculateAverageAndMaxSpeedupWithCuSparse(
    std::unordered_map<std::string, ResultsInformation> &matrixFileToResultsInformationMap) {
    float sumSpeedup = 0.0f;
    float maxSpeedup = 0.0f;

    const int numResults = getNumResults(matrixFileToResultsInformationMap);
    for (const auto &iter : matrixFileToResultsInformationMap) {
        for (const auto &kToOneTimeData : iter.second.kToOneTimeData_) {
            const float zcx_sddmm = getFloatValue(kToOneTimeData.second.zcx_gflops_);
            const float cuSparse_sddmm = getFloatValue(kToOneTimeData.second.cuSparse_gflops_);

            if (zcx_sddmm <= 1e-6 || cuSparse_sddmm <= 1e-6) {
                continue;
            }

            float speedup = zcx_sddmm / cuSparse_sddmm;
            maxSpeedup = std::max(speedup, maxSpeedup);
            sumSpeedup += speedup;
        }
    }

    float averageSpeedup = sumSpeedup / numResults;

    return std::make_pair(averageSpeedup, maxSpeedup);
}

// return the average speedup adn the maximum speedup
std::pair<float, float> calculateAverageAndMaxSpeedupWithRoDe(
    std::unordered_map<std::string, ResultsInformation> &matrixFileToResultsInformationMap) {
    float sumSpeedup = 0.0f;
    float maxSpeedup = 0.0f;

    const int numResults = getNumResults(matrixFileToResultsInformationMap);
    for (const auto &iter : matrixFileToResultsInformationMap) {
        for (const auto &kToOneTimeData : iter.second.kToOneTimeData_) {
            const float zcx_sddmm = getFloatValue(kToOneTimeData.second.zcx_gflops_);
            const float RoDe_sddmm = getFloatValue(kToOneTimeData.second.RoDe_gflops_);

            if (zcx_sddmm <= 1e-6 || RoDe_sddmm <= 1e-6) {
                continue;
            }

            float speedup = zcx_sddmm / RoDe_sddmm;
            maxSpeedup = std::max(speedup, maxSpeedup);
            sumSpeedup += speedup;
        }
    }

    float averageSpeedup = sumSpeedup / numResults;

    return std::make_pair(averageSpeedup, maxSpeedup);
}

// return the average speedup adn the maximum speedup
std::pair<float, float> calculateAverageAndMaxSpeedupWithASpT(
    std::unordered_map<std::string, ResultsInformation> &matrixFileToResultsInformationMap) {
    float sumSpeedup = 0.0f;
    float maxSpeedup = 0.0f;

    const int numResults = getNumResults(matrixFileToResultsInformationMap);
    for (const auto &iter : matrixFileToResultsInformationMap) {
        for (const auto &kToOneTimeData : iter.second.kToOneTimeData_) {
            const float zcx_sddmm = getFloatValue(kToOneTimeData.second.zcx_gflops_);
            const float ASpT_sddmm = getFloatValue(kToOneTimeData.second.ASpT_gflops_);

            if (zcx_sddmm <= 1e-6 || ASpT_sddmm <= 1e-6) {
                continue;
            }

            float speedup = zcx_sddmm / ASpT_sddmm;
            maxSpeedup = std::max(speedup, maxSpeedup);
            sumSpeedup += speedup;
        }
    }

    float averageSpeedup = sumSpeedup / numResults;

    return std::make_pair(averageSpeedup, maxSpeedup);
}


// return the maximum sparsity and minimum sparsity
std::pair<float, float> getMaxAndMinSparsity(
    const std::unordered_map<std::string, ResultsInformation> &matrixFileToResultsInformationMap) {
    float maxSparsity = 0.0f;
    float minSparsity = 100.0f;

    for (const auto &iter : matrixFileToResultsInformationMap) {
        const float sparsity = getFloatValue(iter.second.sparsity_);

        maxSparsity = std::max(sparsity, maxSparsity);
        minSparsity = std::min(sparsity, minSparsity);
    }

    return std::make_pair(maxSparsity, minSparsity);
}

// return the maximum row and minimum row
std::pair<int, int> getMaxAndMinRow(
    const std::unordered_map<std::string, ResultsInformation> &matrixFileToResultsInformationMap) {
    int maxM = 0;
    int minM = std::numeric_limits<int>::max();;

    for (const auto &iter : matrixFileToResultsInformationMap) {
        const int M = getIntValue(iter.second.M_);

        maxM = std::max(M, maxM);
        minM = std::min(M, minM);
    }

    return std::make_pair(maxM, minM);
}

void eliminateNullValues(std::unordered_map<std::string, ResultsInformation> &matrixFileToResultsInformationMap) {
    for (auto iter = matrixFileToResultsInformationMap.begin(); iter != matrixFileToResultsInformationMap.end();) {
        if (iter->second.M_.empty() || iter->second.N_.empty() || iter->second.sparsity_.empty()) {
//            printf("[bad file] : %s\n", iter->first.c_str());
            iter = matrixFileToResultsInformationMap.erase(iter);
        } else {
            ++iter;
        }
    }
}

int main(int argc, char *argv[]) {

    // Read the results file
    SettingInformation settingInformation;
    std::unordered_map<std::string, ResultsInformation> matrixFileToResultsInformationMap;
    for (int fileIdx = 1; fileIdx < argc; ++fileIdx) {
        const std::string resultsFile = argv[fileIdx];

        const std::vector<std::vector<std::string>> allData = readResultsFile(resultsFile);

        for (const std::vector<std::string> &oneTimeResults : allData) {
            if (!settingInformation.initInformation(oneTimeResults)) {
                return -1;
            }
            const std::string matrixFile = findWord(oneTimeResults, "[File : ");
            if (matrixFile.empty()) {
                continue;
            }
            if (matrixFileToResultsInformationMap.find(matrixFile) == matrixFileToResultsInformationMap.end()) {
                matrixFileToResultsInformationMap[matrixFile] = ResultsInformation();
            }
            if (!matrixFileToResultsInformationMap[matrixFile].initInformation(oneTimeResults)) {
                return -1;
            }
        }
    }
    eliminateNullValues(matrixFileToResultsInformationMap);

    // Pick the bad results
    std::unordered_map<std::string, ResultsInformation> badResults =
        pickTheBadResults(matrixFileToResultsInformationMap);

    printf("Number of matrix files: %d\n", static_cast<int>(matrixFileToResultsInformationMap.size()));

    // Print the results Analysis information
    const int numResults = getNumResults(matrixFileToResultsInformationMap);
    printf("Number of data: %d\n", numResults);

    const auto [maxSparsity, minSparsity] = getMaxAndMinSparsity(matrixFileToResultsInformationMap);
    printf("Maximum sparsity: %.2f%%, minimum sparsity: %.2f%%\n", maxSparsity, minSparsity);

    const auto [maxRow, minRow] = getMaxAndMinRow(matrixFileToResultsInformationMap);
    printf("Maximum row: %d, minimum row: %d\n", maxRow, minRow);

    const float accuracy = calculateAccuracy(matrixFileToResultsInformationMap);
    printf("Accuracy: %.2f%%\n", accuracy * 100);

    const auto [averageSpeedupCuSDDMM, maxSpeedupCuSDDMM] = calculateAverageAndMaxSpeedupWithCuSDDMM(
        matrixFileToResultsInformationMap);
    printf("Average speedup over cuSDDMM: %.2f, maximum speedup: %.2f\n", averageSpeedupCuSDDMM, maxSpeedupCuSDDMM);

    const auto [averageSpeedupCuSparse, maxSpeedupCuSparse] = calculateAverageAndMaxSpeedupWithCuSparse(
        matrixFileToResultsInformationMap);
    printf("Average speedup over cuSparse: %.2f, maximum speedup: %.2f\n", averageSpeedupCuSparse, maxSpeedupCuSparse);

    const auto [averageSpeedupRoDe, maxSpeedupRoDe] = calculateAverageAndMaxSpeedupWithRoDe(
        matrixFileToResultsInformationMap);
    printf("Average speedup over RoDe: %.2f, maximum speedup: %.2f\n", averageSpeedupRoDe, maxSpeedupRoDe);

    const auto [averageSpeedupASpT, maxSpeedupASpT] = calculateAverageAndMaxSpeedupWithASpT(
        matrixFileToResultsInformationMap);
    printf("Average speedup over ASpT: %.2f, maximum speedup: %.2f\n", averageSpeedupASpT, maxSpeedupASpT);

    const int numBadResults = getNumResults(badResults);
    printf("Bad results: %.2f%%\n", (static_cast<float>(numBadResults) / numResults) * 100);

    // Print the program setting information to Markdown format
    settingInformation.printInformation();

    // Print the results to Markdown format
    for (const auto &iter : matrixFileToResultsInformationMap) {
        iter.second.printInformation();
    }

    // Print the bad results to Markdown format
    if (numBadResults > 0) {
        printf("Bad results: \n\n");
        for (const auto &iter : badResults) {
            iter.second.printInformation();
        }
    }

    return 0;
}
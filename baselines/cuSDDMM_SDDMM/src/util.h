#pragma once

#include <thrust/sort.h>

#include <vector>
#include <algorithm>
#include <iterator>
#include <utility>
#include <bits/stdc++.h>
#include <time.h>
#include <sys/time.h>
using namespace std;

inline double seconds() {
    struct timeval tp;
    gettimeofday(&tp, NULL);
    return ((double) tp.tv_sec + (double) tp.tv_usec * 1.e-6);
}

int actv_row_size = 180;
int SM_CAPACITY = 6144;
int BLOCKSIZE = 512;

class Matrix {
 public:
  long n_rows, n_cols;
  long nnz;

  vector<int> rows;
  vector<int> cols;
  vector<float> vals;

};

inline std::string iterateOneWordFromLine(const std::string &line, int &wordIter) {
    const int begin = wordIter;
    while (wordIter < line.size() &&
        (line[wordIter] != ' ' && line[wordIter] != '\t' && line[wordIter] != '\r')) {
        ++wordIter;
    }
    const int end = wordIter;

    // Skip the space
    while (wordIter < line.size() &&
        (line[wordIter] == ' ' || line[wordIter] == '\t' || line[wordIter] == '\r')) {
        ++wordIter;
    }

    return end - begin > 0 ? line.substr(begin, end - begin) : "";
}

bool initializeFromSmtxFile(const std::string &filePath, Matrix &S) {
    std::ifstream inFile;
    inFile.open(filePath, std::ios::in); // open file
    if (!inFile.is_open()) {
        std::cerr << "Error, smtx file cannot be opened : " << filePath << std::endl;
        return false;
    }

    std::string line; // Store the data for each line
    while (getline(inFile, line) && line[0] == '%') {} // Skip comments

    int wordIter = 0;
    S.n_rows = std::stoi(iterateOneWordFromLine(line, wordIter));
    S.n_cols = std::stoi(iterateOneWordFromLine(line, wordIter));
    S.nnz = std::stoi(iterateOneWordFromLine(line, wordIter));

    if (S.nnz == 0) {
        std::cerr << "Error, smtx file " << filePath << " nnz is 0!" << std::endl;
        return false;
    }

    std::vector<int> rowOffsets(S.n_rows + 1);
    std::vector<int> colIndices(S.nnz);

    // initialize rowOffsets
    {
        getline(inFile, line);
        wordIter = 0;
        for (int idx = 0; idx < rowOffsets.size(); ++idx) {
            const int rowOffset = std::stoi(iterateOneWordFromLine(line, wordIter));
            rowOffsets[idx] = rowOffset;
        }
    }

    // initialize colIndices and values
    {
        getline(inFile, line);
        wordIter = 0;
        for (int idx = 0; idx < colIndices.size(); ++idx) {
            const int col = std::stoi(iterateOneWordFromLine(line, wordIter));
            colIndices[idx] = col;
        }
    }

    S.rows.resize(S.nnz);
    S.cols.resize(S.nnz);
    S.vals.resize(S.nnz);

    int indexOfCoo = 0;
    for (int row = 0; row < S.n_rows; ++row) {
        for (int idx = rowOffsets[row]; idx < rowOffsets[row + 1]; ++idx) {
            S.rows[indexOfCoo] = row;
            S.cols[indexOfCoo] = colIndices[idx];
            S.vals[indexOfCoo] = 0.0f;
            ++indexOfCoo;
        }
    }

    inFile.close();

    return true;
}

void sort_by_key_for_multiple_vectors(int *key_first,
                                      int *key_last,
                                      int *value1_first,
                                      float *value2_first) {
    thrust::sort_by_key(thrust::host,
                        key_first,
                        key_last,
                        thrust::make_zip_iterator(thrust::make_tuple(value1_first, value2_first)));

}

bool initializeFromMtxFile(const std::string &filePath, Matrix &S) {
    std::ifstream inFile;
    inFile.open(filePath, std::ios::in); // open file
    if (!inFile.is_open()) {
        std::cerr << "Error, mtx file cannot be opened : " << filePath << std::endl;
        return false;
    }

    std::cout << "sparseMatrix::CSR initialize From mtx file : " << filePath << std::endl;

    std::string line; // Store the data for each line
    while (getline(inFile, line) && line[0] == '%') {} // Skip comments

    int wordIter = 0;
    S.n_rows = std::stoi(iterateOneWordFromLine(line, wordIter));
    S.n_cols = std::stoi(iterateOneWordFromLine(line, wordIter));
    S.nnz = std::stoi(iterateOneWordFromLine(line, wordIter));

    if (S.nnz == 0) {
        std::cerr << "Error, mtx file " << filePath << " nnz is 0!" << std::endl;
        return false;
    }

    if (wordIter < line.size()) {
        std::cerr << "Error, mtx file " << line << " line format is incorrect!" << std::endl;
        return false;
    }

    std::vector<int> rowIndices(S.nnz);
    std::vector<int> colIndices(S.nnz);
    std::vector<float> values(S.nnz);

    int idx = 0;
    while (getline(inFile, line)) {
        wordIter = 0;
        const int row = std::stoi(iterateOneWordFromLine(line, wordIter)) - 1;
        const int col = std::stoi(iterateOneWordFromLine(line, wordIter)) - 1;
        const std::string valueStr = iterateOneWordFromLine(line, wordIter);
        float val = 0.0f;
        try {
            val = valueStr.empty() ? static_cast<float>(0) : static_cast<float>(std::stod(valueStr));
        } catch (const std::out_of_range&) {
            std::cout << "Warning: valueStr out of range: " << valueStr << std::endl;
        }

//        if (wordIter < line.size()) {
//            std::cerr << "Error, mtx file " << line << " line format is incorrect!" << std::endl;
//        }

        rowIndices[idx] = row;
        colIndices[idx] = col;
        values[idx] = val;

        ++idx;
    }

    sort_by_key_for_multiple_vectors(rowIndices.data(),
                                     rowIndices.data() + rowIndices.size(),
                                     colIndices.data(),
                                     values.data());

    S.rows = rowIndices;
    S.cols = colIndices;
    S.vals = values;

    inFile.close();

    return true;
}

template<typename T>
void getOneLineThreeData(const std::string &line, int &first, int &second, T &third) {
    first = -1;
    second = -1;
    third = -1;

    if (line.empty()) {
        return;
    }

    int wordIter = 0;
    first = std::stoi(iterateOneWordFromLine(line, wordIter));
    second = std::stoi(iterateOneWordFromLine(line, wordIter));
    const std::string valueStr = iterateOneWordFromLine(line, wordIter);
    third = valueStr.empty() ? static_cast<T>(1) : static_cast<T>(std::stof(valueStr));

    if (wordIter < line.size()) {
        std::cerr << "Error, file \"" << line << "\" line format is incorrect!" << std::endl;
    }
}

bool initializeFromGraphDataset(const std::string &file, Matrix &S) {
    std::ifstream inFile;
    inFile.open(file, std::ios::in); // open file
    if (!inFile.is_open()) {
        std::cerr << "Error, file cannot be opened : " << file << std::endl;
        return false;
    }

    std::cout << "sparseMatrix::CSR initialize From file : " << file << std::endl;

    std::string line; // Store the data for each line
    while (getline(inFile, line) && line[0] == '#') {
        int wordIter = 0;
        const std::string nodesStr("Nodes: ");
        const std::string edgesStr("Edges: ");
        if (line.find(nodesStr) != std::string::npos) {
            wordIter = line.find(nodesStr) + 7;
            const int nodes = std::stoi(iterateOneWordFromLine(line, wordIter));
            S.n_rows = nodes;
            S.n_cols = nodes;
        }
        if (line.find(edgesStr) != std::string::npos) {
            wordIter = line.find(edgesStr) + 7;
            const int edges = std::stoi(iterateOneWordFromLine(line, wordIter));
            S.nnz = edges;
        }
    }

    if (!S.n_rows || !S.n_cols || !S.nnz) {
        std::cerr << "Error, file " << file << " row or col or nnz not initialized!" << std::endl;
    }

    std::vector<int> rowIndices(S.nnz);
    std::vector<int> colIndices(S.nnz);
    std::vector<float> values(S.nnz, 0);

    int idx = 0;
    std::unordered_map<int, int> nodeToIdMap;
    int nodeCount = 0;
    do {
        int node, node2;
        float third;
        getOneLineThreeData(line, node, node2, third);
        if (node == -1 || node2 == -1) {
            continue;
        }
        if (nodeToIdMap.find(node) == nodeToIdMap.end()) {
            nodeToIdMap[node] = nodeCount;
            ++nodeCount;
        }
        if (nodeToIdMap.find(node2) == nodeToIdMap.end()) {
            nodeToIdMap[node2] = nodeCount;
            ++nodeCount;
        }

        rowIndices[idx] = nodeToIdMap[node];
        colIndices[idx] = nodeToIdMap[node2];
        values[idx] = third;

        ++idx;
    } while (getline(inFile, line));

    // Check data
    if (idx < S.nnz) {
        std::cerr << "Error, file " << file << " nnz is not enough!" << std::endl;
    }
    std::set<std::pair<int, int>> rowColSet;
    for (int idx = 0; idx < S.nnz; ++idx) {
        const int row = rowIndices[idx];
        const int col = colIndices[idx];
        if (row >= S.n_rows || col >= S.n_cols) {
            std::cerr << "Error, file " << file << " row or col is too big!" << std::endl;
            return false;
        }
        std::pair<int, int> rowColPair(row, col);
        if (rowColSet.find(rowColPair) != rowColSet.end()) {
            fprintf(stderr, "Error, matrix has duplicate data! row:%d, col:%d\n",
                    row, col);
            return false;
        }
        rowColSet.insert(rowColPair);
    }

    S.rows = rowIndices;
    S.cols = colIndices;
    S.vals = values;

    inFile.close();

    return true;
}

std::string getFileSuffix(const std::string &filename) {
    size_t pos = filename.find_last_of("."); // 查找最后一个 '.'
    if (pos != std::string::npos) {
        return filename.substr(pos); // 截取后缀
    }
    return ""; // 如果没有找到，则返回空字符串
}

bool intialize_matrix(const std::string &file, Matrix &S) {
    const std::string fileSuffix = getFileSuffix(file);
    if (fileSuffix == ".mtx" || fileSuffix == ".mmio") {
        return initializeFromMtxFile(file, S);
    } else if (fileSuffix == ".smtx") {
        return initializeFromSmtxFile(file, S);
    } else if (fileSuffix == ".txt") {
        return initializeFromGraphDataset(file, S);
    } else {
        std::cerr << "Error, file format is not supported : " << file << std::endl;
    }

    return false;
}

class TiledMatrix {
 public:
  int ntile_c;
  int ntile_r;
  int max_active_block;
  int max_active_row;
  long nnz;

  vector<int> rows;
  vector<int> cols;
  vector<float> vals;
  vector<int> row_holder;
  vector<int> active_row;
  vector<int> lastIdx_block_tile;
  vector<int> n_actv_row;
  vector<int> lastIdx_tile;
  vector<int> tiled_ind;

  TiledMatrix(Matrix S, int tile_sizeX, int tile_sizeY) {
      ntile_c = S.n_cols / tile_sizeX + 1;
      ntile_r = S.n_rows / tile_sizeY + 1;
      max_active_block = (S.n_rows / actv_row_size + 1);
      lastIdx_block_tile.resize((ntile_c + 1) * (S.n_rows / actv_row_size + 1));
      lastIdx_tile.resize(ntile_c + 1);
      rows.resize(S.nnz + ntile_c * BLOCKSIZE - 1);
      cols.resize(S.nnz + ntile_c * BLOCKSIZE - 1);
      vals.resize(S.nnz + ntile_c * BLOCKSIZE - 1);
      tiled_ind.resize(S.nnz + ntile_c * BLOCKSIZE - 1);
      active_row.resize(S.n_rows * ntile_c);
      row_holder.resize(S.n_rows);
      n_actv_row.resize(ntile_c);
  }
};

void make_HTasH(const vector<float> H, vector<float> &H_t, int n_cols, int k) {
    for (long r = 0; r < n_cols; ++r) {
        for (long t = 0; t < k; ++t)
            H_t[t * n_cols + r] = H[r * k + t]; //-1;
    }
}

void initial(vector<float> &X, long n, int k) {
    srand48(0L);
    for (long r = 0; r < n; ++r) {
        for (long t = 0; t < k; ++t)
            X[r * k + t] = 0.1 * drand48(); //-1;
    }
}
void unsorted_make_CSR(int *rows, int *cols, float *vals, long nnz, long n_rows, long n_cols, int *row_ptr) {
    ofstream of;
    of.open("nytimes_tans.txt");

    vector<tuple<int, int, float> > items;
    std::tuple<int, int, float> ap;
    for (long idx = 0; idx < nnz; ++idx) {
        //  cout << "orig " << rows[idx] <<" " << cols[idx] <<" "<< vals[idx] << endl;
        // //transpose
        ap = std::make_tuple(cols[idx], rows[idx], vals[idx]);
        //regular
        //ap=std::make_tuple(rows[idx],cols[idx],vals[idx]);
        items.push_back(ap);
    }
    sort(items.begin(), items.end());

    //if CSR
    // int *nnz_row = new int[n_rows];
    long idx = 0, tot = 0;
    row_ptr[0] = 0;
    for (int r = 0; r < n_rows; ++r) {
        // nnz_row[r] =0;
        while (get < 0 > (items[idx]) == r && idx < nnz) {
            // nnz_row[r]++;
            rows[idx] = get < 0 > (items[idx]) + 1;
            cols[idx] = get < 1 > (items[idx]) + 1;
            vals[idx] = get < 2 > (items[idx]);
            idx++;

        }
        row_ptr[r + 1] = idx;
        // tot += nnz_row[r];
    }
    of << n_cols << " " << n_rows << " " << nnz << endl;
    for (long idx = 0; idx < nnz; ++idx)
        of << rows[idx] << " " << cols[idx] << " " << vals[idx] << endl;
    of.close();
    // cout << "tot = nnz :: " << tot << " = " << nnz << endl; 
    // for (int i = 0; i < n_rows; ++i)
    //   cout << " row "<<get<0>(items[idx]) << " " <<  row_ptr[i];
    // cout << endl;

    // for (int i = 0; i < nnz; ++i)
    //  cout << " "<< get<0>(items[i]) << " " <<  get<1>(items[i]) <<" "<< get<2>(items[i]) << endl;


}
// void make_tile(smat_t &R, mat_int &tiled_bin, const int TS)

void make_CSR(vector<int> rows, vector<int> cols, vector<float> vals, long nnz,
              long n_rows, int *row_ptr, int *row_holder) {
    //assuming sorted

    //if CSR
    long idx = 0, tot = 0;
    row_ptr[0] = 0;
    int holder = 0;
    int r = rows[idx];

    while (idx < nnz) {
        row_holder[holder] = r;
        while (rows[idx] == r && idx < nnz) {
            idx++;
        }
        // tot += nnz_row[r];
        holder++;
        row_ptr[holder] = idx;
        // cout << "rows " << r <<" "<< row_ptr[holder] << endl;
        r = rows[idx];
    }
    row_ptr[holder + 1] = idx;
}

// void make_tile(smat_t &R, mat_int &tiled_bin, const int TS)


void make_2DBlocks(int *row_ptr, int *row_ind, int *col_ind, float *val_ind, long nnz, long n_rows, long n_cols) {
    int *new_row_ind = new int[nnz];
    int *new_col_ind = new int[nnz];
    float *new_val_ind = new float[nnz];
    int block_dimX = 2;
    int block_dimY = 2;
    int n_blockY = n_cols / block_dimX + 1;
    int n_blockX = n_rows / block_dimY + 1;
    int n_block = (n_rows / block_dimY + 1) * (n_cols / block_dimX + 1);
    int nnz_row = 0;
    int *new_ind = new int[nnz];
    int *list = new int[n_block];
    long idx = 0;
    int dimx = 0, dimy = 0, block_no = 0;

    //initialization
    for (int i = 0; i < n_block; ++i)
        list[i] = 0;

    // #pragma omp parallel for 
    for (int r = 0; r < n_rows; ++r) {
        int block_noY = r / block_dimY;
        for (long idx = row_ptr[r]; idx < row_ptr[r + 1]; ++idx) {
            int block_noX = col_ind[idx] / block_dimX;// - 1;
            block_no = block_noY * n_blockX + block_noX;
            cout << "processing " << r << " " << col_ind[idx] << " ::: "
                 << block_noY << " " << block_noX << " " << block_no << endl;
            list[block_no]++;
            // new_ind[n_rows * i + count[i]++] = idx;  

            // list[bucket_no]++ = idx;                
            //while((idx-tiled_bin[tile_no-1][c]) < TS && idx < R.col_ptr[c+1]){ //CHANGED for nnz tiles
        }
    }
    for (int i = 0; i < n_block; ++i)
        cout << " adf " << i << " " << list[i] << endl;
}

void rewrite_matrix_2D(int *row_ptr, int *row_ind, int *col_ind, float *val_ind,
                       int *new_rows, int *new_cols, float *new_vals, long nnz, long n_rows, long n_cols,
                       int TS, int *tiled_ind, int *lastIdx_tile) {
    int TS_r = 2;
    long new_idx = 0, idx = 0;
    int n_tile_c = n_cols / TS + 1, n_tile_r = n_rows / TS_r + 1, tile_no = 0;
    int tot_tile = n_tile_c * n_tile_r;
    int *row_lim = new int[(n_tile_c + 1) * n_rows];
    lastIdx_tile[0] = 0;
    for (int i = 0; i < nnz; ++i)
        cout << "orig " << i << " : " << row_ind[i] << " " << col_ind[i] << endl;

    // #pragma omp parallel for 
    for (int tile_lim = TS; tile_lim <= (n_cols + TS - 1); tile_lim += TS) {
        int tile_no_c = tile_lim / TS;
        for (int tile_lim_r = 0; tile_lim_r < n_rows + TS_r - 1; tile_lim_r += TS_r) {
            tile_no = tile_no_c * n_tile_r + tile_lim_r / TS_r;
            for (int r = tile_lim_r; r < tile_lim_r + TS_r && r < n_rows; ++r) {
                if (tile_lim == TS) {
                    idx = row_ptr[r];
                    row_lim[r] = idx;
                } else
                    idx = row_lim[(tile_no - 1) * n_rows + r];
                while (col_ind[idx] < tile_lim && idx < row_ptr[r + 1]) {
                    cout << " inside " << r << ":" << new_idx << " " << idx << endl;
                    tiled_ind[new_idx] = idx;
                    // new_rows[new_idx] = row_ind[idx];
                    // new_cols[new_idx] = col_ind[idx];
                    // new_vals[new_idx] = val_ind[idx];
                    new_idx++;
                    idx++;
                }
                row_lim[tile_no_c * n_rows + r] = idx;
            }
            // lastIdx_tile[tile_no] = new_idx; 
        }
    }
    // for (int i = 0; i <10; ++i)
    //       cout  << i <<" : "<<row_ind[i] <<" " << col_ind[i] << " new: " << tiled_ind[i]
//        <<" , "<< new_rows[i] <<" "<< new_cols[i]<< endl;
    delete (row_lim);
}
void rewrite_col_sorted_matrix(int *row_ptr, int *row_ind, int *col_ind, float *val_ind,
                               int *new_rows, int *new_cols, float *new_vals, long nnz, long n_rows, long n_cols,
                               int TS, int *tiled_ind, int *lastIdx_tile, int block, long &new_nnz) {

    long new_idx = 0, idx = 0;
    int n_tile = n_cols / TS + 1, tile_no = 0;
    lastIdx_tile[0] = 0;

    // #pragma omp parallel for 
    int c = 0;
    for (int tile_lim = TS; tile_lim <= (n_cols + TS - 1); tile_lim += TS) {
        tile_no = tile_lim / TS;
        //being lazy ..can skip the part
        for (int c = 0; c < tile_lim && c < n_cols; ++c) {
            while (col_ind[idx] == c) {
                tiled_ind[new_idx] = idx;
                new_rows[new_idx] = row_ind[idx];
                new_cols[new_idx] = col_ind[idx];
                new_vals[new_idx] = val_ind[idx];
                new_idx++;
                idx++;
            }
        }
        lastIdx_tile[tile_no] = new_idx;
        if (tile_no < 5)
            cout << "lastIdx_tile " << tile_no << " " << lastIdx_tile[tile_no] << endl;
    }
    new_nnz = nnz;
}

int rewrite_matrix_1D(const Matrix S, TiledMatrix &tS, int *row_ptr, int TS, int *row_holder) {

    long new_idx = 0, idx = 0;
    int max_block_inAtile = S.n_rows / actv_row_size + 1;
    int n_tile = tS.ntile_c, tile_no = 0;
    tS.lastIdx_tile[0] = 0;
    unsigned char c[4];
    int row = 0, col = 0;
    unsigned int final_int = 0, final_row, final_col;
    long n_rows = S.n_rows;
    long n_cols = S.n_cols;
    vector<int> row_lim(n_rows);

    // #pragma omp parallel for 
    for (int tile_lim = TS; tile_lim <= (n_cols + TS - 1); tile_lim += TS) {
        int block_count = 0;
        int cur_block = 0, r = 0;
        tile_no = tile_lim / TS;
        tS.n_actv_row[tile_no - 1] = 0;

        if (tile_no == 1)
            tS.lastIdx_block_tile[tile_no * max_block_inAtile + 0] = 0;
        else
            tS.lastIdx_block_tile[tile_no * max_block_inAtile + 0] = new_idx;

        for (int holder = 0; holder < n_rows; ++holder) {
            r = row_holder[holder];
            //for(int r = 0; r <n_rows; ++r){
            if (tile_lim == TS) {
                idx = row_ptr[holder];
                row_lim[holder] = idx;
            } else idx = row_lim[holder];

            while (S.cols[idx] < tile_lim && idx < row_ptr[holder + 1]) {
                tS.tiled_ind[new_idx] = idx;
                tS.rows[new_idx] = tS.n_actv_row[tile_no - 1];//S.rows[idx];
                tS.cols[new_idx] = S.cols[idx];


                // ******* bit mask start *******
                // row = tS.n_actv_row[tile_no-1];;//S.rows[idx];
                // col = S.cols[idx]%95;
                // c[0] = (col>>0) & 0xff;
                // c[1] = (row>>16) & 0xFF;
                // c[2] = (row>>8) & 0xFF;
                // c[3] = (row>>0) & 0xff;
                // final_int = ((c[1]) << 24) | ((c[2]) << 16) | c[3] << 8 | c[0];
                // tS.rows[new_idx] = final_int;
                // // ******* bit mask finish ******

                tS.vals[new_idx] = S.vals[idx];
                new_idx++;
                idx++;
            }
            if (idx != row_lim[holder]) {
                tS.active_row[(tile_no - 1) * n_rows + tS.n_actv_row[tile_no - 1]++] = r;
                // passive_row[(tile_no-1) * n_rows + holder] = tS.n_actv_row[tile_no-1]-1;  
                cur_block++;
            }
            row_lim[holder] = idx;
            if (cur_block >= actv_row_size) {
                cur_block = 0;
                tS.lastIdx_block_tile[(tile_no - 1) * max_block_inAtile + block_count] = new_idx;
                block_count++;
            }

            if (holder == n_rows - 1 && cur_block > 0 && cur_block < actv_row_size)
                tS.lastIdx_block_tile[(tile_no - 1) * max_block_inAtile + block_count] = new_idx;
        }
        if (tS.n_actv_row[tile_no - 1] > tS.max_active_row)
            tS.max_active_row = tS.n_actv_row[tile_no - 1];
        tS.lastIdx_tile[tile_no] = new_idx;

    }
    tS.nnz = S.nnz;
    return tS.max_active_row;
}


//perfect
// void rewrite_matrix_1D(int * row_ptr, int * row_ind, int *col_ind, float * val_ind, 
//  int *new_rows, int *new_cols, float * new_vals, long nnz, long n_rows, long n_cols,
//  int TS, int *tiled_ind, int * lastIdx_tile,  int block, long &new_nnz){

//  long new_idx = 0, idx =0;
//  int n_tile = n_cols/TS + 1, tile_no=0;
//     int *row_lim = new int[ n_rows];
//     int *count = new int[ n_tile];
//     int *active_row = new int[n_tile * n_rows];
//     lastIdx_tile[0] = 0; 

//     // #pragma omp parallel for 
//     for(int tile_lim = TS; tile_lim <= (n_cols+TS-1); tile_lim+=TS){ 
//      tile_no = tile_lim/TS;  

//      for(int r = 0; r <n_rows; ++r){ 
//          if(tile_lim == TS){
//              idx = row_ptr[r]; row_lim[r] = idx;}
//          else 
//                 idx = row_lim[r];

//              while(col_ind[idx] < tile_lim && idx < row_ptr[r+1]){
//                  // if(col_ind[idx] == 1)
//           //           cout << " inside " <<col_ind[idx]<<" " << idx <<" "<< new_idx <<" "<<tile_no << endl;                        
//                 tiled_ind[new_idx] = idx;
//                 new_rows[new_idx] = row_ind[idx];
//                 new_cols[new_idx] = col_ind[idx];
//                 new_vals[new_idx] = val_ind[idx];
//                 new_idx++;
//                 idx++;
//             }   
//             if(idx != row_lim[r])  
//                 active_row[tile_no * n_rows + count[tile_no]++]=r;       
//             row_lim[r] = idx;

//         }
//         lastIdx_tile[tile_no] = new_idx; 
//         // if(tile_no < 5){
//         //     cout << tile_no << " tile : " << count[tile_no] << endl;
//         //     for (int i = 0; i < count[tile_no]; ++i)
//         //         cout << active_row[tile_no*n_rows+i] << endl;

//         // }
//     }
//     for (int i = lastIdx_tile[2]; i < lastIdx_tile[3]; ++i)
//     {
//         if(new_cols[i]<180 )
//             cout << "lastIdx_tile " <<i<< " " <<row_ind[i]<< " "<<col_ind[i]<<" " <<new_cols[i] << endl;
//     }

//     new_nnz = nnz;

//     // for (int i = 0; i < nnz; ++i)
//     //   cout << "old nnz " <<i<<": " <<row_ind[i] <<" "<<col_ind[i] <<" "<<val_ind[i]<< endl;

//     // for (int i = 0; i < nnz; ++i)
//     //   cout << "new nnz " << i<<": " << new_rows[i] <<" "<<new_cols[i] <<" "<<new_vals[i] << endl;
//     // for (int i = 0; i <10; ++i)
//     //       cout  << i <<" : "<<row_ind[i] <<" " << col_ind[i] << " new: " << tiled_ind[i] 
//     //    <<" , "<< new_rows[i] <<" "<< new_cols[i]<< endl;
//      delete(row_lim);
// }
// fixing last tile
// long rewrite_matrix_1D(int * row_ptr, int * row_ind, int *col_ind, float * val_ind, 
//  int *new_rows, int *new_cols, float * new_vals, long nnz, long n_rows, long n_cols,
//  int TS, int *tiled_ind, int * lastIdx_tile, int blocksize, long &new_nnz){

//  long new_idx = 0, idx =0;
//  int n_tile = n_cols/TS + 1, tile_no=0;
//     int *row_lim = new int[ n_rows];
//     lastIdx_tile[0] = 0; 
//     long tot =0 ;

//     // #pragma omp parallel for 
//     for(int tile_lim = TS; tile_lim <= (n_cols+TS-1); tile_lim+=TS){ 
//      tile_no = tile_lim/TS; 
//         long tile_nnz = 0; 
//      for(int r = 0; r <n_rows; ++r){ 
//          if(tile_lim == TS){
//              idx = row_ptr[r]; row_lim[r] = idx;}
//          else {idx = row_lim[r];
//              // cout << " real " << r <<" "<<idx << endl;
//          } 

//              while(col_ind[idx] < tile_lim && idx < row_ptr[r+1]){
//                  // cout << " inside " <<r<<" " << new_idx <<" "<< idx << endl;                        
//                 tiled_ind[new_idx] = idx;
//                 new_rows[new_idx] = row_ind[idx];
//                 new_cols[new_idx] = col_ind[idx];
//                 new_vals[new_idx] = val_ind[idx];
//                 new_idx++;
//                 idx++;
//                 tile_nnz++;

//             }            
//             row_lim[r] = idx;
//         }  
//         // tot += tile_nnz;
//         // cout <<tile_nnz << " "<< tot << endl;

//         //lastIdx_tile[tile_no] = new_idx; 
//         int nnz_tile = new_idx - lastIdx_tile[tile_no-1];
//         int remainder_block = blocksize - nnz_tile % blocksize;
//         if(nnz_tile % blocksize == 0)
//          remainder_block = 0;

//         while(remainder_block >0){
//          tiled_ind[new_idx] = idx-1;
//             new_rows[new_idx] = new_rows[new_idx-1];
//             new_cols[new_idx] = new_cols[new_idx-1];
//             new_vals[new_idx] = 0;
//             // cout <<"fill up " <<new_idx <<" "<< idx <<" "<< row_ind[idx] << endl;
//             new_idx++;
//             remainder_block--;
//         }
//         lastIdx_tile[tile_no] = new_idx; 
//     }
//     cout << lastIdx_tile[0] << " "<<lastIdx_tile[1] << " "<<lastIdx_tile[2] << " " << endl;
//     new_nnz = new_idx;

//   //   for (int i = 0; i < nnz; ++i)
//      // cout << "before "<<i <<": "<< row_ind[i] <<" "<< col_ind[i] << " " << val_ind[i] << endl;
//   //   for (int i = 0; i < new_nnz; ++i)
//   //         cout << "after "<<i <<": "<< new_rows[i] <<" "<< new_cols[i] << " " << new_vals[i] << endl;

//   //   //for (int i = 16000; i <1650; ++i)
//     //       cout  << i <<" : " << lastIdx_tile[i+1]-lastIdx_tile[i] << endl;
//     delete(row_lim);

// }


void make_2Dtile(int *row_ptr, int *row_ind, int *col_ind, float *val_ind, long nnz, long n_rows, long n_cols,
                 int TS, int *row_lim) {
    int *tiled_matrix = new int[TS * n_rows];
    // #pragma omp parallel for 
    for (int r = 0; r < n_rows; ++r) {
        long idx = row_ptr[r];
        row_lim[r] = idx;
        for (int tile = TS; tile <= (n_cols + TS - 1); tile += TS) {
            while (col_ind[idx] < tile && idx < row_ptr[r + 1]) {
                // cout << "processing: " << r <<" "<<col_ind[idx] << " "<<tile<<" "<<idx << endl;
                idx++;
            }
            int tile_no = tile / TS - 1;
            row_lim[tile_no * n_rows + r] = idx;
        }
    }
    // for (int ii = 0; ii < 4; ++ii)
    //  for (int i = 0; i < 4; ++i)
    //    {
    //       cout << ii << "i: "<< i<<" row lim " <<row_lim[ii * n_rows +i]<< endl;
    //    }
    //    cout << endl;


}
void comp_bin(int n_bin, int *count, int n_rows, int *row_ptr, int nnz_max) {
    int tot = 0;
    int *LB = new int[n_bin];
    int *UB = new int[n_bin];
    int *rowGroupPtr = new int[n_bin * n_rows];
    for (int i = 0; i < n_bin; i++) {
        count[i] = 0;
        UB[i] = (1 << i) * 2 + 1;
        LB[i] = UB[i] >> 1;
    }
    LB[0] = 0;
    UB[n_bin - 1] = nnz_max + 1;
    //for 6 bin 32,64, 128,256,512, more

    // LB[4] = 0; ////crucial...only last 6 bins are valid
    UB[n_bin - 1] = nnz_max + 1;
    omp_set_num_threads(n_bin);  // create as many CPU threads as there are # of bins   
#pragma omp parallel
    {
        unsigned int cpu_thread_id = omp_get_thread_num();
        int i = cpu_thread_id;
        for (int r = 0; r < n_rows; r++) {
            int nnz_row = row_ptr[r + 1] - row_ptr[r];
            if (nnz_row > LB[i] && nnz_row < UB[i])
                rowGroupPtr[n_rows * i + count[i]++] = r;
        }
    }
    for (int i = 0; i < n_bin; ++i) {
        cout << i << " bin limit: " << UB[i] << " " << count[i] << endl;
    }
    long max = 0;
    for (int r = 0; r < n_rows; r++) {
        int nnz_row = row_ptr[r + 1] - row_ptr[r];

        if (nnz_row > max)
            max = nnz_row;

    }
    cout << "max" << " " << max << endl;

}



import argparse
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path
from matplotlib.ticker import MaxNLocator
import matplotlib

matplotlib.rcParams.update({
    'figure.figsize': (14, 6),
    'axes.titlesize': 18,
    'axes.labelsize': 16,
    'xtick.labelsize': 14,
    'ytick.labelsize': 14,
    'legend.fontsize': 14,
    'lines.linewidth': 1,
    'lines.markersize': 6,
    'font.weight': 'bold',
    'axes.labelweight': 'bold',
    'axes.titleweight': 'bold'
})


def preprocess(df, k):
    df = df.sort_values(by="NNZ").reset_index(drop=True)
    df = df[(df["NNZ"] >= 100000) & (df["NNZ"] <= 2000000)]
    df = df.dropna(subset=["BSMR"])
    df = df.drop_duplicates(subset=["file"])

    window_size = 5
    if len(df) < window_size:
        print(f"Skipping K={k} due to insufficient data points (<{window_size})")
        return None

    numeric_cols = ["NNZ", "BSMR", "cuSDDMM", "cuSPARSE",
                    "RoDe", "ASpT", "TCGNN", "FlashSparse", "Sputnik"]

    avg_df = df[numeric_cols].rolling(window=window_size).mean().dropna().reset_index(drop=True)
    return avg_df


def plot_gflops_comparison(k_data_list, output_dir, output_name_suffix):
    if not k_data_list:
        print("没有有效数据用于绘图。")
        return

    num_plots = len(k_data_list)
    cols = 2  # 每行最多两个子图
    rows = (num_plots + cols - 1) // cols  # 向上取整

    fig, axes = plt.subplots(rows, cols, figsize=(8 * cols, 4 * rows))

    # 修正 axes 结构为列表
    if isinstance(axes, np.ndarray):
        axes = axes.flatten().tolist()
    else:
        axes = [axes]

    algo_columns = {
        "BSMR": "BSMR",
        "FlashSparse": "FlashSparse",
        "RoDe": "RoDe",
        "ASpT": "ASpT",
        "cuSDDMM": "cuSDDMM",
        "cuSPARSE": "cuSPARSE",
        "TCGNN": "TCGNN",
        "Sputnik": "Sputnik"
    }

    custom_colors = {
        "BSMR": "#1f77b4",
        "FlashSparse": "#d62728",
        "RoDe": "#9467bd",
        "ASpT": "#F0E442",
        "cuSDDMM": "#17becf",
        "cuSPARSE": "#2ca02c",
        "TCGNN": "#ff7f0e",
        "Sputnik": "#e377c2"
    }

    custom_markers = {
        "BSMR": "o",  # 圆圈
        "FlashSparse": "s",  # 方块
        "RoDe": "D",  # 菱形
        "ASpT": "^",  # 上三角
        "cuSDDMM": "v",  # 下三角
        "cuSPARSE": "P",  # 加粗五边形
        "TCGNN": "X",  # X 形
        "Sputnik": "*"  # 星形
    }

    handles_dict = {}
    for idx, (k, avg_df) in enumerate(k_data_list):
        ax = axes[idx]  # 正确获取当前子图
        x = avg_df["NNZ"].values

        for col, label in algo_columns.items():
            if col in avg_df.columns and not avg_df[col].isna().all():
                mask = avg_df[col] != 0
                x_filtered = x[mask]
                y_filtered = avg_df[col][mask]
                if len(x_filtered) == 0:
                    continue
                line, = ax.plot(x_filtered, y_filtered,
                                label=label,
                                color=custom_colors[label],
                                alpha=0.7,
                                marker=custom_markers[label],
                                markersize=3)  # 添加 marker
                if label not in handles_dict:
                    handles_dict[label] = line

        ax.set_title(f"K = {k}")
        # ax.set_xlabel("NNZ")
        if idx // cols == rows - 1:  # 仅最后一行的图
            ax.set_xlabel("NNZ")
        if idx % cols == 0:
            ax.set_ylabel("GFLOPS")
        ax.set_xscale('linear')
        ax.xaxis.set_major_locator(MaxNLocator(nbins=10))
        ax.set_ylim(bottom=0)

    # 隐藏多余的空子图
    for j in range(len(k_data_list), len(axes)):
        fig.delaxes(axes[j])

    fig.legend(handles_dict.values(), handles_dict.keys(),
               loc='upper center', bbox_to_anchor=(0.5, 1.02), ncol=8)
    plt.tight_layout(rect=[0, 0, 1, 0.97])
    fig_path = output_dir / f"sddmm_{output_name_suffix}.png"

    # 保存 PNG 高分辨率版本
    plt.savefig(fig_path, bbox_inches='tight', dpi=300)

    # 保存 PDF 矢量图版本
    pdf_output_path = fig_path.with_suffix('.pdf')
    plt.savefig(pdf_output_path, bbox_inches='tight')

    print(f"Saved PNG to {fig_path}")
    print(f"Saved PDF to {pdf_output_path}")


def main():
    parser = argparse.ArgumentParser(description="K=32/64/128/256 分别输入，绘制 GFLOPS 子图")
    parser.add_argument('--k32', type=str, help="CSV 文件路径(K=32)")
    parser.add_argument('--k64', type=str, help="CSV 文件路径(K=64)")
    parser.add_argument('--k128', type=str, help="CSV 文件路径(K=128)")
    parser.add_argument('--k256', type=str, help="CSV 文件路径(K=256)")
    parser.add_argument('--outdir', type=str, default='.', help="输出图像目录")
    args = parser.parse_args()

    output_dir = Path(args.outdir)
    output_dir.mkdir(parents=True, exist_ok=True)

    k_data_list = []

    if args.k32:
        df_k32 = pd.read_csv(args.k32)
        avg_k32 = preprocess(df_k32, 32)
        if avg_k32 is not None:
            k_data_list.append((32, avg_k32))

    if args.k64:
        df_k64 = pd.read_csv(args.k64)
        avg_k64 = preprocess(df_k64, 64)
        if avg_k64 is not None:
            k_data_list.append((64, avg_k64))

    if args.k128:
        df_k128 = pd.read_csv(args.k128)
        avg_k128 = preprocess(df_k128, 128)
        if avg_k128 is not None:
            k_data_list.append((128, avg_k128))

    if args.k256:
        df_k256 = pd.read_csv(args.k256)
        avg_k256 = preprocess(df_k256, 256)
        if avg_k256 is not None:
            k_data_list.append((256, avg_k256))

    # 自动生成文件名后缀
    suffix_parts = [f'k{k}' for (k, _) in k_data_list]
    output_name_suffix = "_".join(suffix_parts)

    plot_gflops_comparison(k_data_list, output_dir, output_name_suffix)


if __name__ == "__main__":
    main()

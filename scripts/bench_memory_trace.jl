# E10: bộ nhớ tidset theo tiến trình duyệt (phần của B, nhận thêm khi chia lại). Kiểm chứng giả thuyết H7 (bài báo §7, Fig. 22):
# đỉnh bộ nhớ xuất hiện lúc dựng tidset các tập 2 item ở đầu mỗi lớp của lớp gốc, sau đó giảm dần
# vì tidset ngắn lại khi đi sâu (bổ đề 6). Bài báo đo trên dữ liệu tổng hợp thưa (T20.I6.D100K), nên
# nhóm đo trên cả một bộ dày (Chess) lẫn một bộ thưa cùng họ dữ liệu tổng hợp IBM (T10I4D100K).
#
#   julia --project=. scripts/bench_memory_trace.jl [bộ dữ liệu ...]     (mặc định: chess T10I4D100K)
#
# Mỗi bộ đo tại minsup trung bình của nó (results/minsup_grid.csv). Ghi số byte tidset đang sống sau mỗi
# tập phổ biến được xuất (lấy mẫu tối đa 4.000 điểm), kèm độ sâu của tập, cho bản vector (v3) và bản
# bitset (v4). Kết quả: results/memory_trace.csv và bảng tóm tắt results/memory_trace.md.

using EclatFIM, Printf
include(joinpath(@__DIR__, "config.jl"))

const HEADER = ["dataset", "minsup", "variant", "itemset_index", "bytes_current", "depth"]

function trace(path, ds, ms)
    db = read_spmf(dataset_path(ds))
    σ = minsup_count(parse_minsup(ms), n_transactions(db))
    summary = []
    for v in ("v3", "v4")
        st = EclatStats()
        total = Ref(0)
        eclat!((i, s) -> (total[] += 1), db, σ, VARIANTS[v])                 # đếm trước số tập
        step = max(1, total[] ÷ 4000)
        rows = Tuple{Int,Int,Int}[]
        k = Ref(0)
        eclat!(db, σ, VARIANTS[v]; stats = st) do items, s
            k[] += 1
            k[] % step == 0 && push!(rows, (k[], st.bytes_current, length(items)))
        end
        for (i, b, d) in rows
            append_csv(path, HEADER, [ds, ms, v, i, b, d])
        end
        bytes = [b for (_, b, _) in rows]
        ipk = argmax(bytes)
        mean = sum(bytes) / length(bytes)
        push!(summary, (v = v, n = total[], peak = st.bytes_peak, at = rows[ipk][1], depth = rows[ipk][3],
                        mean = mean, maxlen = st.max_depth))
        println(ds, " ", ms, " ", v, ": ", total[], " tập, tidset đỉnh ", round(st.bytes_peak / 2^20; digits = 3),
                " MiB tại tập thứ ", rows[ipk][1], " (độ dài ", rows[ipk][3], ")")
    end
    return summary
end

function main(args)
    datasets = isempty(args) ? ["chess", "T10I4D100K"] : args
    grid = load_grid()
    path = joinpath(results_dir(), "memory_trace.csv")
    isfile(path) && rm(path)
    io = IOBuffer()
    println(io, "# E10: bộ nhớ tidset theo tiến trình duyệt (giả thuyết H7)\n")
    println(io, "Sinh bởi `scripts/bench_memory_trace.jl`. Đỉnh lấy từ bộ đếm nội bộ; vị trí đỉnh và trung bình ",
            "lấy trên các điểm lấy mẫu (tối đa 4.000 điểm mỗi lần chạy).\n")
    println(io, "| Bộ | minsup | Phiên bản | Số tập | Tidset đỉnh | Trung bình | Đỉnh / trung bình | Đỉnh tại tập thứ | Độ dài tập lúc đỉnh | Tập dài nhất |")
    println(io, "|---|---|---|---|---|---|---|---|---|---|")
    for ds in datasets
        ms = median_minsup(grid[ds])
        for s in trace(path, ds, ms)
            @printf(io, "| %s | %s | %s | %d | %.3f MiB | %.3f MiB | %.2f | %d | %d | %d |\n", ds, ms, s.v, s.n,
                    s.peak / 2^20, s.mean / 2^20, s.peak / s.mean, s.at, s.depth, s.maxlen)
        end
    end
    write(joinpath(results_dir(), "memory_trace.md"), String(take!(io)))
    println(read(joinpath(results_dir(), "memory_trace.md"), String))
end

let t0 = time()
    main(ARGS)
    log_run("scripts/bench_memory_trace.jl", ARGS, time() - t0)
end

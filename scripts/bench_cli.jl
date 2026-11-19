# E2b: thời gian tiến trình THẬT của giao diện dòng lệnh (demo.jl), tức thời gian người dùng chờ từ lúc gõ lệnh
# đến lúc có file kết quả: khởi động Julia, nạp gói, biên dịch JIT, đọc file, khai thác, ghi kết quả.
# So với thời gian tiến trình của SPMF ở E2 (cột t_wall_s của e2_runtime.csv). Phần của B.
#
#   julia --project=. scripts/bench_cli.jl
#
# Khác với E2 (scripts/run_one.jl có bước khởi động riêng để tách JIT khỏi thời gian thuật toán), ở đây
# demo.jl chạy đúng như người dùng chạy, không khởi động trước. Kết quả: results/e2_cli.csv

using EclatFIM
include(joinpath(@__DIR__, "config.jl"))

const JULIA_BIN = joinpath(Sys.BINDIR, Base.julia_exename())
const CASES = [("chess", "80%"), ("chess", "65%"), ("chess", "50%"),
               ("retail", "1%"), ("retail", "0.1%"), ("retail", "0.01%")]

function main()
    path = joinpath(results_dir(), "e2_cli.csv")
    isfile(path) && rm(path)
    header = ["dataset", "minsup", "impl", "repeat", "status", "t_wall_s", "commit", "machine", "date"]
    demo = rootpath("demo.jl")
    for (ds, ms) in CASES
        isfile(dataset_path(ds)) || continue
        for rep in 1:REPEATS
            out = tempname()
            r = run_with_timeout(`$(JULIA_BIN) --project=$(ROOT) $(demo) --minsup $(ms) $(dataset_path(ds)) -o $(out)`;
                                 timeout = TIMEOUT_S)
            isfile(out) && rm(out)
            p = provenance()
            append_csv(path, header, [ds, ms, "nhom-demo-" * DEFAULT_VARIANT, rep, string(r.status),
                                      round(r.wall_s; digits = 3), p.commit, p.machine, p.date])
            println("  E2b $ds $ms lần $rep: ", r.status, " ", round(r.wall_s; digits = 2), " s")
        end
    end
end

let t0 = time()
    main()
    log_run("scripts/bench_cli.jl", ARGS, time() - t0)
end

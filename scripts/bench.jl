# Hạ tầng đo đạc hiệu năng thực nghiệm cho Chương 2.
#
# Giao thức đo đạc:
#   - Mỗi lượt đo thực thi trong một tiến trình độc lập.
#   - Tiến trình Julia khởi động (warm-up) bằng CÙNG hàm `_mine_write` sẽ đo, trên pasquier99 và 2 CSDL của
#     scripts/warmup.jl, rồi mới đo bằng time_ns(). Hai CSDL này đi qua mọi nhánh code, kể cả nhánh dữ liệu thưa
#     của v6, nên t_algo_s không chứa thời gian biên dịch JIT (sửa ngày 28/11).
#   - Tắt bộ đếm nội bộ EclatStats trong quá trình đo thời gian (quyết định D20).
#   - Đo bộ nhớ đỉnh bằng `/usr/bin/time -v` (Linux/WSL2) hoặc `Sys.maxrss()` (Julia) / JVM heap (SPMF).
#   - Xuất dữ liệu CSV chuẩn 17 cột và cập nhật nhật ký `results/LOG.md`.
#
# Cú pháp thực thi:
#   julia --project=. scripts/bench.jl --dataset pasquier99 --input data/toy/pasquier99.txt --minsups 40%,60% --variants v0,v1 --repeats 3 --out results/bench_toy.csv
#   julia --project=. scripts/bench.jl --mode quick --variants v0 --repeats 1 --out results/bench_quick.csv
#   julia --project=. scripts/bench.jl --mode full --variants v0,v1 --repeats 3 --with-spmf --out results/bench_full.csv

using Dates
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "config.jl"))
include(joinpath(@__DIR__, "warmup.jl"))   # write_warmup_dbs, WARMUP_MINSUP: dữ liệu khởi động dùng chung với run_one.jl

const CSV_HEADER = "dataset,n_tx,minsup,minsup_count,impl,variant,repeat,t_read_s,t_build_s,t_mine_write_s,t_algo_s,t_wall_s,peak_rss_mb,n_itemsets,commit,machine,date"
const HAS_GNU_TIME = Sys.isunix() && isfile("/usr/bin/time")

function git_short_commit()
    try
        return strip(read(pipeline(`git -C $(ROOT) rev-parse --short HEAD`; stderr = devnull), String))
    catch
        return "unknown"
    end
end

function machine_tag()
    cpu = Sys.cpu_info()
    model = isempty(cpu) ? string(Sys.MACHINE) : strip(cpu[1].model)
    return replace(model, "," => ";")
end

"""Tách Maximum resident set size (KiB) từ output của `/usr/bin/time -v` sang MiB."""
function parse_gnu_time_rss_mb(output::AbstractString)::Float64
    m = match(r"Maximum resident set size \(kbytes\):\s*(\d+)", output)
    return m === nothing ? NaN : parse(Float64, m.captures[1]) / 1024.0
end

# ---------------------------------------------------------------------------
# Chế độ worker: chạy trong tiến trình Julia mới để đo đúng 1 lần (có warm-up)
# ---------------------------------------------------------------------------

# [VẤN ĐÁP] _mine_write — một hàm dùng chung cho pha khởi động và pha đo
# LÀM GÌ    : khai thác `db` với ngưỡng σ, ghi kết quả SPMF ra `out_path`, trả về số tập đã ghi.
# VÌ SAO    : Julia biên dịch eclat! riêng cho từng KIỂU của hàm sink, và mỗi biểu thức lambda trong mã nguồn là một
#             kiểu riêng. Bản trước 28/11 viết hai lambda giống hệt nhau ở pha khởi động và pha đo, nên eclat! bị biên
#             dịch lại ngay trong lần đo được bấm giờ. Khi dùng chung một hàm, lambda bên trong có cùng kiểu ở cả hai pha.
# BẰNG CHỨNG: máy i5-6200U, chess 95%: lần đo theo bản cũ chứa 48 ms biên dịch với v0 và 283 ms với v6. Thời gian khai thác
#             thật (đã biên dịch xong) chỉ là 1,7 ms với v0 và 0,7 ms với v6.
"""Khai thác `db` với ngưỡng `σ` (số đếm) và ghi kết quả SPMF ra `out_path`; trả về số tập đã ghi."""
function _mine_write(db, σ, cfg, out_path)
    open(out_path, "w") do io                                   # mở file kết quả
        w = SPMFWriter(io, db)                                  # bộ ghi có đệm, đổi mã nội bộ → mã gốc
        if n_transactions(db) > 0                               # CSDL rỗng: chỉ tạo file rỗng
            eclat!((items, sup) -> write_itemset!(w, items, sup), db, σ, cfg)   # ghi từng tập ngay khi tìm được
        end
        close_writer!(w)                                        # ghi phần còn lại trong đệm ra file
        return w.count                                          # số tập đã ghi
    end
end

function run_julia_worker(args::Vector{String})
    length(args) == 4 || error("Worker cần 4 tham số: <input> <minsup> <variant> <output>")
    input_path, minsup_str, variant, out_path = args

    @eval using EclatFIM

    cfg = Base.invokelatest(() -> VARIANTS[variant])
    toy_path = rootpath("data", "toy", "pasquier99.txt")

    # 1. Warm-up bằng CÙNG hàm `_mine_write` sẽ đo, trên pasquier99 và 2 CSDL của warmup.jl. Mọi nhánh code (kể cả
    #    nhánh dữ liệu thưa của v6) được biên dịch trước khi bấm giờ, nên t_algo_s không chứa thời gian JIT.
    Base.invokelatest() do
        mktempdir() do dir                                      # thư mục tạm, tự xóa khi khối do kết thúc
            out = joinpath(dir, "out.txt")                      # file kết quả tạm
            dbs = [(toy_path, 2)]                               # pasquier99 (5 giao dịch), σ = 2
            append!(dbs, [(p, WARMUP_MINSUP) for p in write_warmup_dbs(dir)])   # thêm 2 CSDL đi qua nhánh dữ liệu thưa
            for (path, σ) in dbs                                # từng CSDL khởi động
                db = read_spmf(path)                            # chạy thử bộ đọc file
                minsup_count(minsup_str, n_transactions(db))    # chạy thử phép đổi minsup → số đếm (pha đo cũng gọi)
                _mine_write(db, σ, cfg, out)                    # chạy thử khai thác + ghi bằng CÙNG hàm sẽ đo
            end
        end
    end

    # 2. Đo thật trên dữ liệu mục tiêu
    res = Base.invokelatest() do
        t0 = time_ns()
        db = read_spmf(input_path)
        t_read_s = (time_ns() - t0) / 1e9

        n_tx = n_transactions(db)
        sigma_min = minsup_count(minsup_str, n_tx)

        mkpath(dirname(out_path))
        t1 = time_ns()
        n_found = _mine_write(db, sigma_min, cfg, out_path)    # CÙNG hàm đã chạy ở pha khởi động
        t_mine_write_s = (time_ns() - t1) / 1e9
        rss_mb = Sys.maxrss() / 2^20
        return (n_tx = n_tx, sigma_min = sigma_min, n_found = n_found,
                t_read_s = t_read_s, t_mine_write_s = t_mine_write_s, rss_mb = rss_mb)
    end

    println("BENCH_RESULT|$(res.n_tx)|$(res.sigma_min)|$(res.n_found)|$(res.t_read_s)|$(res.t_mine_write_s)|$(res.rss_mb)")
    return 0
end

# ---------------------------------------------------------------------------
# Tiến trình cha: gọi worker Julia và SPMF, gom kết quả và ghi CSV
# ---------------------------------------------------------------------------

function measure_julia_once(input_path::AbstractString, minsup_str::AbstractString,
                            variant::AbstractString, out_path::AbstractString;
                            timeout::Real = BENCH_TIMEOUT_S)
    julia_exe = Base.julia_cmd()[1]
    base_cmd = `$julia_exe --project=$(ROOT) $(@__FILE__) --worker $input_path $minsup_str $variant $out_path`
    cmd = HAS_GNU_TIME ? `/usr/bin/time -v $base_cmd` : base_cmd
    r = run_with_timeout(cmd; timeout = timeout)

    if r.status == :timeout
        return (status = :timeout, n_tx = -1, sigma_min = -1, n_itemsets = -1,
                t_read_s = NaN, t_build_s = NaN, t_mine_write_s = NaN, t_algo_s = NaN,
                t_wall_s = r.wall_s, peak_rss_mb = NaN)
    elseif r.status != :ok
        error("Worker Julia lỗi (variant=$variant, minsup=$minsup_str):\n" * r.output)
    end

    m = match(r"BENCH_RESULT\|(\d+)\|(\d+)\|(\d+)\|([\d.eE+-]+)\|([\d.eE+-]+)\|([\d.eE+-]+)", r.output)
    m === nothing && error("Không đọc được dòng BENCH_RESULT:\n" * r.output)

    n_tx = parse(Int, m.captures[1])
    sigma_min = parse(Int, m.captures[2])
    n_itemsets = parse(Int, m.captures[3])
    t_read_s = parse(Float64, m.captures[4])
    t_mine_write_s = parse(Float64, m.captures[5])
    worker_rss = parse(Float64, m.captures[6])
    gnu_rss = HAS_GNU_TIME ? parse_gnu_time_rss_mb(r.output) : NaN
    peak_rss_mb = isnan(gnu_rss) ? worker_rss : gnu_rss

    return (status = :ok, n_tx = n_tx, sigma_min = sigma_min, n_itemsets = n_itemsets,
            t_read_s = t_read_s, t_build_s = 0.0, t_mine_write_s = t_mine_write_s,
            t_algo_s = t_mine_write_s, t_wall_s = r.wall_s, peak_rss_mb = peak_rss_mb)
end

function measure_spmf_once(algo::AbstractString, input_path::AbstractString,
                           minsup_str::AbstractString, out_path::AbstractString;
                           xmx::AbstractString = SPMF_XMX, timeout::Real = BENCH_TIMEOUT_S)
    base_cmd = `$(java_cmd()) -Xmx$(xmx) -jar $(spmf_jar()) run $algo $input_path $out_path $minsup_str`
    cmd = HAS_GNU_TIME ? `/usr/bin/time -v $base_cmd` : base_cmd
    r = run_with_timeout(cmd; timeout = timeout)

    if r.status == :timeout
        return (status = :timeout, n_tx = -1, sigma_min = -1, n_itemsets = -1,
                t_read_s = NaN, t_build_s = NaN, t_mine_write_s = NaN, t_algo_s = NaN,
                t_wall_s = r.wall_s, peak_rss_mb = NaN)
    elseif r.status != :ok || occursin(r"ERROR|Exception|Error\.", r.output)
        error("SPMF $algo lỗi (minsup=$minsup_str):\n" * r.output)
    end

    n_tx = _grab(r"Transactions count from database : (\d+)", r.output, Int, -1)
    n_itemsets = _grab(r"Frequent itemsets count : (\d+)", r.output, Int, -1)
    algo_ms = _grab(r"Total time ~ ([\d.]+) ms", r.output, Float64, NaN)
    heap_mb = _grab(r"Maximum memory usage : ([\d.]+) mb", r.output, Float64, NaN)
    gnu_rss = HAS_GNU_TIME ? parse_gnu_time_rss_mb(r.output) : NaN
    peak_rss_mb = isnan(gnu_rss) ? heap_mb : gnu_rss
    t_algo_s = isnan(algo_ms) ? NaN : algo_ms / 1000.0

    # Tính sigma_min theo đúng công thức SPMF
    ms_val = endswith(minsup_str, "%") ? parse(Float64, minsup_str[1:end-1]) / 100 : parse(Float64, minsup_str)
    sigma_min = n_tx >= 0 ? ceil(Int, ms_val * n_tx) : -1

    return (status = :ok, n_tx = n_tx, sigma_min = sigma_min, n_itemsets = n_itemsets,
            t_read_s = NaN, t_build_s = NaN, t_mine_write_s = t_algo_s,
            t_algo_s = t_algo_s, t_wall_s = r.wall_s, peak_rss_mb = peak_rss_mb)
end

fmt_cell(x::Float64) = isnan(x) ? "" : string(round(x; digits = 6))

function write_csv_row(io::IO, dataset, minsup_str, impl, variant, rep, m, commit, machine, date_str)
    if m.status == :timeout
        println(io, join([dataset, "", minsup_str, "", impl, variant, rep,
                          "timeout", "timeout", "timeout", "timeout", "timeout",
                          "", "", commit, machine, date_str], ','))
    else
        println(io, join([dataset, m.n_tx, minsup_str, m.sigma_min, impl, variant, rep,
                          fmt_cell(m.t_read_s), fmt_cell(m.t_build_s),
                          fmt_cell(m.t_mine_write_s), fmt_cell(m.t_algo_s),
                          fmt_cell(m.t_wall_s), fmt_cell(m.peak_rss_mb),
                          m.n_itemsets, commit, machine, date_str], ','))
    end
    flush(io)
end

function append_log(commit, cmd_str, note)
    mkpath(RESULTS_DIR)
    log_path = joinpath(RESULTS_DIR, "LOG.md")
    if !isfile(log_path)
        open(log_path, "w") do io
            println(io, "# Nhật ký chạy thực nghiệm\n")
            println(io, "| Ngày | Commit | Lệnh | Ghi chú |")
            println(io, "|---|---|---|---|")
        end
    end
    open(log_path, "a") do io
        println(io, "| ", Dates.format(now(), "yyyy-mm-dd HH:MM"), " | `", commit,
                "` | `", replace(cmd_str, "|" => "\\|"), "` | ", note, " |")
    end
end

function main(args::Vector{String})
    if !isempty(args) && args[1] == "--worker"
        return run_julia_worker(args[2:end])
    end

    mode = "custom"
    dataset = ""
    input_path = ""
    minsups = String[]
    variants = ["v0"]
    repeats = 3
    with_spmf = false
    spmf_algos = ["Eclat"]
    out_csv = joinpath(RESULTS_DIR, "bench.csv")
    timeout = BENCH_TIMEOUT_S

    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--mode" && i < length(args)
            mode = args[i + 1]; i += 2
        elseif a == "--dataset" && i < length(args)
            dataset = args[i + 1]; i += 2
        elseif a == "--input" && i < length(args)
            input_path = args[i + 1]; i += 2
        elseif a == "--minsups" && i < length(args)
            minsups = String.(split(args[i + 1], ',')); i += 2
        elseif a == "--variants" && i < length(args)
            variants = String.(split(args[i + 1], ',')); i += 2
        elseif a == "--repeats" && i < length(args)
            repeats = parse(Int, args[i + 1]); i += 2
        elseif a == "--with-spmf"
            with_spmf = true; i += 1
        elseif a == "--spmf-algos" && i < length(args)
            spmf_algos = String.(split(args[i + 1], ',')); i += 2
        elseif a == "--out" && i < length(args)
            out_csv = args[i + 1]; i += 2
        elseif a == "--timeout" && i < length(args)
            timeout = parse(Float64, args[i + 1]); i += 2
        else
            error("Tham số không hợp lệ: $a")
        end
    end

    # Xây dựng danh sách (dataset, input_path, minsup_list) cần chạy
    jobs = Tuple{String,String,Vector{String}}[]
    if mode in ("quick", "full")
        grid = load_minsup_grid()
        for ds in BENCHMARK_DATASETS
            isfile(ds.path) || continue
            ms_list = get(grid, ds.name, String[])
            isempty(ms_list) && continue
            if mode == "quick"
                # Chế độ nhanh (Colab): lấy 3 mức cao nhất để chạy gọn
                ms_list = ms_list[1:min(3, length(ms_list))]
            end
            push!(jobs, (ds.name, ds.path, ms_list))
        end
        isempty(jobs) && error("Không tìm thấy dữ liệu benchmark nào trong $BENCHMARK_DIR. Hãy chạy scripts/fetch_data.jl trước.")
    else
        isempty(input_path) && error("Cần truyền --input <file> hoặc --mode quick|full")
        isempty(minsups) && error("Cần truyền --minsups <ds_minsup>, ví dụ --minsups 40%,60%")
        isempty(dataset) && (dataset = first(splitext(basename(input_path))))
        push!(jobs, (dataset, input_path, minsups))
    end

    can_spmf = with_spmf && isfile(spmf_jar()) && java_major_version() >= 25
    if with_spmf && !can_spmf
        @warn "Bỏ qua SPMF vì chưa có spmf.jar hoặc Java < 25."
    end

    commit = git_short_commit()
    machine = machine_tag()
    date_str = Dates.format(today(), "yyyy-mm-dd")
    tmp_dir = joinpath(RESULTS_DIR, "tmp")
    mkpath(tmp_dir)
    mkpath(dirname(out_csv))

    open(out_csv, "w") do io
        println(io, CSV_HEADER)
        for (ds_name, ds_path, ms_list) in jobs
            for ms in ms_list
                for v in variants
                    for rep in 1:repeats
                        out_tmp = joinpath(tmp_dir, "julia_$(ds_name)_$(v)_r$(rep).txt")
                        println("→ Julia [$v] $ds_name minsup=$ms (lần $rep/$repeats)...")
                        m = measure_julia_once(ds_path, ms, v, out_tmp; timeout = timeout)
                        write_csv_row(io, ds_name, ms, "julia", v, rep, m, commit, machine, date_str)
                        isfile(out_tmp) && rm(out_tmp)
                    end
                end
                if can_spmf
                    for algo in spmf_algos
                        for rep in 1:repeats
                            out_tmp = joinpath(tmp_dir, "spmf_$(ds_name)_$(algo)_r$(rep).txt")
                            println("→ SPMF [$algo] $ds_name minsup=$ms (lần $rep/$repeats)...")
                            m = measure_spmf_once(algo, ds_path, ms, out_tmp; timeout = timeout)
                            write_csv_row(io, ds_name, ms, "spmf", algo, rep, m, commit, machine, date_str)
                            isfile(out_tmp) && rm(out_tmp)
                        end
                    end
                end
            end
        end
    end

    append_log(commit, "julia --project=. scripts/bench.jl " * join(args, " "),
               "Xuất $(out_csv) ($(length(jobs)) bộ, repeats=$repeats)")
    println("✓ Đã ghi kết quả đo vào ", out_csv)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end

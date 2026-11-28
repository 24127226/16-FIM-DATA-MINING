# Giao diện dòng lệnh (CLI) cho gói EclatFIM.
#
# Cú pháp:
#   julia --project=. demo.jl [tùy chọn] --minsup <ngưỡng> <file_input>
#
# Mã thoát chuẩn:
#   0  thực thi thành công
#   1  lỗi tham số dòng lệnh
#   2  lỗi đọc/định dạng dữ liệu hoặc ghi tệp đầu ra

using EclatFIM

const USAGE = """
Cách dùng:
  julia --project=. demo.jl [tùy chọn] --minsup <ngưỡng> <file_input>

Tùy chọn:
  --minsup <giá trị>     Bắt buộc; tỉ lệ trong (0, 1] (vd: 0.01) hoặc phần trăm (vd: 1%)
  -o, --output <file>    File output chuẩn SPMF (mặc định: output.txt; dùng "-" để in ra stdout)
  --variant <v0..v6>     Phiên bản Eclat (mặc định: $(DEFAULT_VARIANT))
  --stats                In thêm bộ đếm nội bộ (không bật khi đo thời gian)
  -h, --help             Hiển thị hướng dẫn này

Ví dụ:
  julia --project=. demo.jl --minsup 0.4 data/toy/pasquier99.txt
  julia --project=. demo.jl --minsup 40% -o - data/toy/pasquier99.txt
"""

"""Cấu trúc lưu toàn bộ tham số dòng lệnh sau khi phân tích hợp lệ."""
struct CLIOptions
    input_path::String
    minsup_str::String
    minsup::Float64
    output_path::String
    variant::String
    cfg::EclatConfig
    show_stats::Bool
end

"""Ngoại lệ riêng cho lỗi cú pháp tham số dòng lệnh (trả về mã thoát 1)."""
struct CLIError <: Exception
    msg::String
end

"""
    parse_cli(args::Vector{String}) -> Union{Symbol, CLIOptions}

Mục đích: Phân tích và kiểm tra hợp lệ các tham số dòng lệnh (`--minsup`, `-o/--output`,
`--variant`, `--stats`, `-h/--help` và `<file_input>`). Trả về `:help` nếu người dùng yêu cầu
xem hướng dẫn, hoặc `CLIOptions` nếu hợp lệ; ném `CLIError` nếu thiếu/sai tham số.
"""
function parse_cli(args::Vector{String})
    minsup_str = nothing
    output_path = "output.txt"
    variant = DEFAULT_VARIANT
    show_stats = false
    positionals = String[]

    i = 1
    n = length(args)
    while i <= n
        arg = args[i]
        if arg == "-h" || arg == "--help"
            return :help
        elseif arg == "--stats"
            show_stats = true
            i += 1
        elseif arg == "--minsup"
            i + 1 <= n || throw(CLIError("Thiếu giá trị cho --minsup"))
            minsup_str = args[i + 1]
            i += 2
        elseif startswith(arg, "--minsup=")
            minsup_str = arg[length("--minsup=")+1:end]
            i += 1
        elseif arg == "-o" || arg == "--output"
            i + 1 <= n || throw(CLIError("Thiếu đường dẫn cho $arg"))
            output_path = args[i + 1]
            i += 2
        elseif startswith(arg, "--output=")
            output_path = arg[length("--output=")+1:end]
            i += 1
        elseif arg == "--variant"
            i + 1 <= n || throw(CLIError("Thiếu tên phiên bản cho --variant"))
            variant = args[i + 1]
            i += 2
        elseif startswith(arg, "--variant=")
            variant = arg[length("--variant=")+1:end]
            i += 1
        elseif startswith(arg, "-") && arg != "-"
            throw(CLIError("Tùy chọn không hợp lệ: $arg"))
        else
            push!(positionals, arg)
            i += 1
        end
    end

    minsup_str === nothing && throw(CLIError("Thiếu tham số bắt buộc --minsup"))
    isempty(positionals) && throw(CLIError("Thiếu đường dẫn <file_input>"))
    length(positionals) > 1 && throw(CLIError("Chỉ nhận một <file_input>, nhận được: $(join(positionals, ", "))"))

    minsup = try
        parse_minsup(minsup_str)
    catch err
        throw(CLIError(sprint(showerror, err)))
    end

    haskey(VARIANTS, variant) || throw(CLIError(
        "Phiên bản '$variant' không hợp lệ. Chọn trong: $(join(VARIANT_NAMES, ", "))"))
    cfg = VARIANTS[variant]

    try
        EclatFIM.check_config(cfg)
    catch err
        throw(CLIError("Phiên bản '$variant' chưa được cài đặt ở bản code hiện tại: $(sprint(showerror, err))"))
    end

    return CLIOptions(positionals[1], minsup_str, minsup, output_path, variant, cfg, show_stats)
end

"""Định dạng số giây với 4 chữ số thập phân để in báo cáo gọn gàng."""
fmt_s(sec::Float64) = string(round(sec; digits = 4), " s")

"""
    run_cli(opts::CLIOptions) -> Int

Mục đích: Thực thi trọn vẹn quy trình CLI gồm 2 pha tách biệt:
1. Pha 1: Đọc tệp giao dịch chuẩn SPMF và quy đổi ngưỡng `σ_min`.
2. Pha 2: Chạy `eclat!` xuất luồng trực tiếp qua `SPMFWriter` (ra tệp hoặc `stdout`),
   rồi in bảng tóm tắt thời gian và bộ đếm `EclatStats` (nếu bật `--stats`).
"""
function run_cli(opts::CLIOptions)
    # Pha 1: Đọc dữ liệu
    t_read_0 = time_ns()
    db = try
        read_spmf(opts.input_path)
    catch err
        println(stderr, "Lỗi dữ liệu: ", sprint(showerror, err))
        return 2
    end
    t_read_s = (time_ns() - t_read_0) / 1e9

    n_tx = n_transactions(db)
    sigma_min = minsup_count(opts.minsup, n_tx)
    stats = opts.show_stats ? EclatStats() : nothing
    n_found = 0

    # Pha 2: Khai thác và ghi kết quả (dùng SPMFWriter có bộ đệm khối)
    t_mine_0 = time_ns()
    try
        if opts.output_path == "-"
            w = SPMFWriter(stdout, db)
            if n_tx > 0
                eclat!((items, supp) -> write_itemset!(w, items, supp),
                       db, sigma_min, opts.cfg; stats = stats)
            end
            close_writer!(w)
            n_found = w.count
        else
            dir = dirname(opts.output_path)
            !isempty(dir) && mkpath(dir)
            open(opts.output_path, "w") do io
                w = SPMFWriter(io, db)
                if n_tx > 0
                    eclat!((items, supp) -> write_itemset!(w, items, supp),
                           db, sigma_min, opts.cfg; stats = stats)
                end
                close_writer!(w)
                n_found = w.count
            end
        end
    catch err
        println(stderr, "Lỗi khi khai thác/ghi output: ", sprint(showerror, err))
        return 2
    end
    t_mine_write_s = (time_ns() - t_mine_0) / 1e9

    # Khi xuất kết quả ra stdout ("-"), in tóm tắt ra stderr để không lẫn vào output SPMF.
    summary_io = opts.output_path == "-" ? stderr : stdout
    println(summary_io, "=== EclatFIM ($(opts.variant)) ===")
    println(summary_io, "  Input        : ", opts.input_path)
    println(summary_io, "  Giao dịch (N): ", n_tx, " (m = ", n_items(db), " item)")
    println(summary_io, "  Minsup       : ", opts.minsup_str, " (σ_min = ", sigma_min, ")")
    println(summary_io, "  Số tập phổ biến: ", n_found)
    println(summary_io, "  Thời gian đọc: ", fmt_s(t_read_s))
    println(summary_io, "  Khai thác+ghi: ", fmt_s(t_mine_write_s))
    println(summary_io, "  Tổng thời gian: ", fmt_s(t_read_s + t_mine_write_s))
    println(summary_io, "  Output       : ", opts.output_path == "-" ? "stdout" : opts.output_path)

    if stats !== nothing
        println(summary_io, "--- Bộ đếm nội bộ (EclatStats) ---")
        println(summary_io, "  Số phép giao : ", stats.n_intersections, " (không đạt ngưỡng: ", stats.n_failed, ")")
        println(summary_io, "  Số lớp con   : ", stats.n_classes)
        println(summary_io, "  Độ sâu tối đa: ", stats.max_depth)
        println(summary_io, "  Tidset đỉnh  : ", stats.bytes_peak, " bytes")
        println(summary_io, "  Thời gian mức 2: ", fmt_s(stats.time_level2_ns / 1e9))
    end

    return 0
end

"""Điểm vào chính của chương trình dòng lệnh: bắt lỗi tham số và điều phối `run_cli`."""
function main(args::Vector{String})
    parsed = try
        parse_cli(args)
    catch err
        if err isa CLIError
            println(stderr, "Lỗi tham số: ", err.msg)
            println(stderr, "\n", USAGE)
            return 1
        end
        rethrow()
    end

    if parsed === :help
        print(stdout, USAGE)
        return 0
    end

    return run_cli(parsed)
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end

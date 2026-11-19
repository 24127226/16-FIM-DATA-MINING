# Giao diện dòng lệnh của EclatFIM.
#
#   julia --project=. demo.jl [tùy chọn] --minsup <ngưỡng> <file_input>
#
# Ví dụ (đúng lệnh mẫu trong đề):
#   julia --project=. demo.jl --minsup 0.01 data/benchmark.txt

using EclatFIM

const USAGE = """
Cách dùng:
  julia --project=. demo.jl [tùy chọn] --minsup <ngưỡng> <file_input>

Tùy chọn:
  --minsup 0.01 | 1%     bắt buộc; tỉ lệ trong (0, 1] hoặc phần trăm (cách hiểu giống SPMF)
  -o, --output FILE      file kết quả định dạng SPMF (mặc định: output.txt; "-" để in ra màn hình)
  --variant v0..v6       phiên bản thuật toán (mặc định: $(DEFAULT_VARIANT), bản lai)
  --maxlen K             chỉ tìm các tập có tối đa K item
  --stats                in thêm bộ đếm của thuật toán (chạy thêm một lần riêng, không tính giờ)
  -h, --help             in hướng dẫn này

Mã thoát: 0 thành công, 1 tham số sai, 2 lỗi dữ liệu.
"""

struct CLIError <: Exception
    msg::String
end

function parse_cli(args::Vector{String})
    minsup = nothing
    output = "output.txt"
    variant = DEFAULT_VARIANT
    maxlen = typemax(Int)
    stats = false
    inputs = String[]
    i = 1
    need_value(i) = i < length(args) ? args[i+1] : throw(CLIError("thiếu giá trị sau $(args[i])"))
    while i <= length(args)
        a = args[i]
        if a in ("-h", "--help")
            return nothing
        elseif a == "--minsup"
            minsup = need_value(i); i += 2
        elseif a in ("-o", "--output")
            output = need_value(i); i += 2
        elseif a == "--variant"
            variant = need_value(i); i += 2
            haskey(VARIANTS, variant) || throw(CLIError("phiên bản không tồn tại: $variant (chọn trong $(join(VARIANT_NAMES, ", ")))"))
        elseif a == "--maxlen"
            maxlen = tryparse(Int, need_value(i))
            (maxlen === nothing || maxlen < 1) && throw(CLIError("--maxlen phải là số nguyên ≥ 1"))
            i += 2
        elseif a == "--stats"
            stats = true; i += 1
        elseif startswith(a, "-")
            throw(CLIError("tùy chọn không hợp lệ: $a"))
        else
            push!(inputs, a); i += 1
        end
    end
    minsup === nothing && throw(CLIError("thiếu --minsup"))
    length(inputs) == 1 || throw(CLIError("cần đúng một file input (nhận được $(length(inputs)))"))
    ms = try
        parse_minsup(minsup)
    catch
        throw(CLIError("minsup không hợp lệ: $minsup (dạng 0.01 hoặc 1%)"))
    end
    return (input = inputs[1], minsup_str = minsup, minsup = ms, output = output,
            variant = variant, maxlen = maxlen, stats = stats)
end

fmt_s(ns) = string(round(ns / 1e9; digits = 3), " s")

function main(args::Vector{String})
    o = try
        parse_cli(args)
    catch err
        err isa CLIError || rethrow()
        println(stderr, "Lỗi: ", err.msg, "\n")
        print(stderr, USAGE)
        return 1
    end
    if o === nothing
        print(USAGE)
        return 0
    end
    isfile(o.input) || (println(stderr, "Lỗi: không tìm thấy file ", o.input); return 2)

    log = o.output == "-" ? stderr : stdout
    t0 = time_ns()
    db = try
        read_spmf(o.input)
    catch err
        println(stderr, "Lỗi dữ liệu: ", sprint(showerror, err))
        return 2
    end
    t1 = time_ns()
    σ = minsup_count(o.minsup, n_transactions(db))
    cfg = VARIANTS[o.variant]
    count = mine_to_file(db, σ, o.output, cfg; maxlen = o.maxlen)
    t2 = time_ns()

    println(log, "EclatFIM: Eclat (Zaki, 2000), phiên bản ", o.variant)
    println(log, "  Input     : ", o.input, " (N = ", n_transactions(db), " giao dịch, m = ", n_items(db), " item)")
    println(log, "  minsup    : ", o.minsup_str, " → σ_min = ", σ, " giao dịch")
    println(log, "  Kết quả   : ", count, " tập phổ biến → ", o.output == "-" ? "màn hình" : o.output)
    println(log, "  Thời gian : đọc ", fmt_s(t1 - t0), " | khai thác + ghi ", fmt_s(t2 - t1),
            " (lần chạy đầu gồm cả thời gian biên dịch JIT)")
    if o.stats
        st = EclatStats()
        eclat!((items, s) -> nothing, db, σ, cfg; stats = st, maxlen = o.maxlen)
        println(log, "  Bộ đếm    : ", st.n_intersections, " phép giao (", st.n_failed, " dưới ngưỡng), ",
                st.n_classes, " lớp, tập dài nhất ", st.max_depth, " item, tidset đỉnh ",
                round(st.bytes_peak / 2^20; digits = 2), " MiB")
    end
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end

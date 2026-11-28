# Hàm đo dùng chung cho thí nghiệm E8 của A (scripts/bench_ablation.jl). Mỗi lần đo chạy trong một
# tiến trình Julia mới (scripts/run_one.jl), cùng giao thức với bench.jl của B.
# Yêu cầu: script gọi file này phải đã include config_a.jl.

const JULIA_BIN = joinpath(Sys.BINDIR, Base.julia_exename())   # đúng file julia đang chạy script này
const RUN_ONE = rootpath("scripts", "run_one.jl")   # script đo một lần
const RES = results_dir()   # thư mục kết quả

"""Chạy một lần đo trong tiến trình mới. Trả về Dict các trường của dòng "RESULT ..." (hoặc trạng thái lỗi)."""
function run_ours(input, ms, variant; out = "NUL", stats = false, timeout = TIMEOUT_S)   # chạy run_one.jl trong tiến trình MỚI
    args = String[input, ms, variant, out]   # tham số dòng lệnh
    stats && push!(args, "--stats")   # thêm lần chạy bộ đếm nếu cần
    r = run_with_timeout(`$(JULIA_BIN) --project=$(ROOT) $(RUN_ONE) $(args)`; timeout = timeout)   # chạy, quá 600 giây thì dừng
    res = Dict{String,String}("status" => string(r.status), "wall" => string(r.wall_s))   # trạng thái và thời gian cả tiến trình
    if r.status == :ok   # chạy thành công
        m = match(r"RESULT (.*)", r.output)                    # tìm dòng kết quả trong output
        m === nothing && (res["status"] = "error"; return res)   # không có dòng RESULT → coi là lỗi
        for kv in split(m.captures[1])                         # "k=v k=v ..." → Dict
            k, v = split(kv, "=", limit = 2)   # tách tên=giá trị
            res[k] = v   # lưu
        end
    else
        res["error"] = first(replace(r.output, '\n' => ' '), 300)   # giữ 300 ký tự đầu của thông báo lỗi
    end
    return res   # kết quả một lần đo
end

"""Số lần lặp: chạy dưới 1 giây thì lặp nhiều hơn vì đo ngắn dao động nhiều."""
repeats_for(seconds, base) = seconds < 1 ? max(base, REPEATS_SHORT) : base   # chạy dưới 1 giây: lặp 5 lần thay vì 3

"""Chạy và ghi kết quả ra file tạm (như mọi thí nghiệm khác), rồi xóa file đó."""
function ours_tmp(input, ms, variant; kw...)   # đo với file kết quả tạm
    out = tempname()   # file tạm
    try
        return run_ours(input, ms, variant; out = out, kw...)   # đo
    finally
        isfile(out) && rm(out)   # luôn xóa file tạm (kể cả khi lỗi)
    end
end

const HEADER_RUN = ["experiment", "dataset", "kind", "minsup", "sigma", "variant", "repeat", "status",   # cột của e8_ablation*.csv
                    "n_itemsets", "t_read_s", "t_algo_s", "t_wall_s", "maxrss_mb", "commit", "machine", "date"]   # (tiếp)

"""Ghi một lần đo vào CSV."""
function record_ours!(path, exp, ds, ms, variant, rep, r)   # ghi một lần đo
    p = provenance()   # commit, máy, thời điểm
    ok = r["status"] == "ok"   # lần đo thành công?
    append_csv(path, HEADER_RUN, [exp, ds, dataset_kind(ds), ms, get(r, "sigma", ""), variant, rep, r["status"],   # một dòng CSV
        ok ? r["n"] : "", ok ? r["t_read"] : "", ok ? r["t_mine"] : "", r["wall"],   # số tập, thời gian đọc, khai thác, cả tiến trình
        ok ? round(parse(Int, r["maxrss"]) / 2^20; digits = 1) : "", p.commit, p.machine, p.date])   # RAM đỉnh (MiB) và nguồn gốc
end

"""
Đo một cấu hình theo giao thức: chạy lần 1, rồi lặp thêm cho đủ `repeats` lần
(`REPEATS_SHORT` lần nếu lần 1 dưới 1 giây). Trả về kết quả lần 1.
"""
function measure_ours!(path, exp, ds, input, ms, variant, repeats)   # đo theo giao thức: lần 1, rồi lặp thêm
    r = ours_tmp(input, ms, variant)   # lần đo thứ nhất
    record_ours!(path, exp, ds, ms, variant, 1, r)   # ghi lần 1
    r["status"] == "ok" || return r                            # lỗi hoặc quá giờ: không lặp nữa
    nrep = repeats_for(parse(Float64, r["t_mine"]), repeats)   # số lần lặp tùy độ dài lần 1
    for rep in 2:nrep   # các lần còn lại
        record_ours!(path, exp, ds, ms, variant, rep, ours_tmp(input, ms, variant))   # đo và ghi
    end
    return r   # trả lần 1 (để in tiến độ)
end

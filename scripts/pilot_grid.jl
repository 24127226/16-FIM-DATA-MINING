# Chạy thử để chọn lưới minsup cho từng bộ dữ liệu (KE_HOACH_DU_AN.md, mục 8.2).
#
#   julia --project=. scripts/pilot_grid.jl [bộ dữ liệu...]
#
# Với mỗi mức ứng viên: đếm số tập bằng bản mặc định của nhóm (nhanh) và đo thời gian SPMF Eclat
# (cài đặt tham chiếu chậm nhất). Quy tắc chọn 7 mức:
#   - mức cao nhất có ít nhất khoảng 10 tập phổ biến;
#   - mức thấp nhất: SPMF Eclat chạy xong trong ≤ 5 phút và output ≤ khoảng 10⁷ tập.
# Kết quả chạy thử ghi vào results/pilot_grid.csv để minh bạch cách chọn.

using EclatFIM
include(joinpath(@__DIR__, "config.jl"))

const CANDIDATES = Dict(
    "chess" => ["90%", "85%", "80%", "75%", "70%", "65%", "60%", "55%", "50%"],
    "mushroom" => ["30%", "25%", "20%", "15%", "10%", "7.5%", "5%", "3%"],
    "accidents" => ["90%", "85%", "80%", "75%", "70%", "65%", "60%", "55%", "50%"],
    "retail" => ["1%", "0.5%", "0.2%", "0.1%", "0.05%", "0.02%", "0.01%"],
    "T10I4D100K" => ["2%", "1%", "0.5%", "0.2%", "0.1%", "0.05%", "0.02%", "0.01%"],
)

function main(args)
    names = isempty(args) ? [d[1] for d in DATASETS] : args
    path = rootpath("results", "pilot_grid.csv")
    header = ["dataset", "minsup", "sigma", "n_itemsets", "t_best_s", "t_spmf_eclat_s", "spmf_status"]
    for ds in names
        db = read_spmf(dataset_path(ds))
        N = n_transactions(db)
        for ms in CANDIDATES[ds]
            σ = minsup_count(parse_minsup(ms), N)
            cnt = Ref(0)
            t = @elapsed eclat!((i, s) -> (cnt[] += 1), db, σ)
            if cnt[] > 20_000_000
                println(rpad("$ds $ms", 18), cnt[], " tập: quá lớn, dừng")
                append_csv(path, header, [ds, ms, σ, cnt[], round(t; digits = 3), "", "bo_qua"])
                break
            end
            out = tempname()
            s = run_spmf("Eclat", dataset_path(ds), out, ms; xmx = JAVA_XMX, timeout = 300)
            isfile(out) && rm(out)
            secs = s.status == :ok ? s.algo_ms / 1000 : NaN
            println(rpad("$ds $ms", 18), "σ = ", σ, ", ", cnt[], " tập, nhóm ", round(t; digits = 3),
                    " s, SPMF Eclat ", s.status == :ok ? "$(secs) s" : string(s.status))
            append_csv(path, header, [ds, ms, σ, cnt[], round(t; digits = 3), secs, s.status])
            s.status == :ok || break
        end
    end
end

main(ARGS)

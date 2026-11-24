# Tạo các tập con lồng nhau (10% ⊂ 25% ⊂ 50% ⊂ 75% ⊂ 100%) cho thí nghiệm E5 (Scalability, R13).
#
# Cách dùng (từ gốc repo):
#   julia --project=. scripts/subsample.jl
#   julia --project=. scripts/subsample.jl data/benchmark/retail.txt

using Random
include(joinpath(@__DIR__, "config.jl"))

"""
    make_nested_subsamples(input_path, out_dir; fracs, seed)

Đọc toàn bộ giao dịch hợp lệ của `input_path`, hoán vị chỉ số bằng `MersenneTwister(seed)`,
sau đó xuất các tập con lồng nhau (tập nhỏ là tiền tố của tập lớn, giữ đúng thứ tự gốc
của các giao dịch được chọn để dễ đối chiếu).
"""
function make_nested_subsamples(input_path::AbstractString, out_dir::AbstractString;
                                fracs::Vector{Float64} = SUBSAMPLE_FRACS,
                                seed::Int = SEED)
    isfile(input_path) || error("Không tìm thấy file input: $input_path")
    lines = String[]
    open(input_path, "r") do io
        for line in eachline(io)
            s = strip(line)
            isempty(s) && continue
            c = first(s)
            (c == '#' || c == '%' || c == '@') && continue
            push!(lines, s)
        end
    end

    n = length(lines)
    rng = MersenneTwister(seed)
    perm = randperm(rng, n)

    base = first(splitext(basename(input_path)))
    mkpath(out_dir)
    created = NamedTuple{(:frac, :n_tx, :path),Tuple{Float64,Int,String}}[]

    for f in sort(fracs)
        pct = round(Int, f * 100)
        k = clamp(round(Int, f * n), 1, n)
        selected_idx = sort!(perm[1:k])
        dest = joinpath(out_dir, "$(base)_$(pct)pct.txt")
        open(dest, "w") do io
            for idx in selected_idx
                println(io, lines[idx])
            end
        end
        push!(created, (frac = f, n_tx = k, path = dest))
    end
    return created
end

function main(args::Vector{String})
    input_path = isempty(args) ? joinpath(BENCHMARK_DIR, "retail.txt") : args[1]
    out_dir = length(args) >= 2 ? args[2] : SUBSETS_DIR
    created = make_nested_subsamples(input_path, out_dir)
    println("Đã tạo $(length(created)) tập con lồng nhau từ $input_path (seed=$SEED):")
    for c in created
        println("  ✓ $(basename(c.path)): N=$(c.n_tx) ($(round(Int, c.frac * 100))%)")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end

# Sinh CSDL giao dịch tổng hợp cho thí nghiệm E6 (ảnh hưởng của độ dài giao dịch trung bình).
#
#   julia --project=. scripts/gen_synthetic.jl [--N 50000] [--items 1000] [--patterns 500] [--I 4] \
#                                             [--T 5,10,15,20,25,30] [--seed 42]
#
# Theo tinh thần bộ sinh IBM Quest (Agrawal & Srikant, 1994) mà bài báo gốc dùng (§7), bản rút gọn:
#   1. Sinh một kho "mẫu tiềm năng" (potential frequent itemsets): độ dài ~ Poisson(I), một phần
#      item lấy lại từ mẫu trước (tương quan giữa các mẫu), trọng số ~ Exp(1), mức "hỏng" ~ N(0.5, 0.1).
#   2. Mỗi giao dịch có độ dài mục tiêu ~ Poisson(T); ghép dần các mẫu được chọn theo trọng số,
#      mỗi item của mẫu bị bỏ với xác suất (mức hỏng)/2.
# Mọi giá trị T dùng CHUNG một kho mẫu và cùng số giao dịch, số item: chỉ độ dài giao dịch thay đổi.
# Ghi data/synthetic/synth_T<T>.txt (đúng định dạng SPMF: một dấu cách giữa các item).

using Random
include(joinpath(@__DIR__, "config.jl"))

"""Số ngẫu nhiên theo phân phối Poisson(λ) (thuật toán Knuth, đủ dùng với λ ≤ 50)."""
function poisson(rng, λ)
    L = exp(-λ)
    k = 0
    p = 1.0
    while true
        p *= rand(rng)
        p <= L && return k
        k += 1
    end
end

struct Pattern
    items::Vector{Int}
    corruption::Float64
end

function make_patterns(rng, n_patterns, n_items, I)
    pats = Pattern[]
    weights = Float64[]
    prev = Int[]
    for _ in 1:n_patterns
        len = clamp(poisson(rng, I), 1, n_items)
        frac = min(1.0, -0.5 * log(rand(rng)))          # tỉ lệ lấy lại từ mẫu trước ~ Exp(trung bình 0,5)
        take = min(length(prev), round(Int, frac * len))
        items = Set{Int}(shuffle(rng, prev)[1:take])
        while length(items) < len
            push!(items, rand(rng, 1:n_items))
        end
        corruption = clamp(0.5 + 0.1 * randn(rng), 0.0, 1.0)
        push!(pats, Pattern(sort!(collect(items)), corruption))
        push!(weights, -log(rand(rng)))
        prev = pats[end].items
    end
    cumw = cumsum(weights ./ sum(weights))
    return pats, cumw
end

pick(rng, cumw) = min(searchsortedfirst(cumw, rand(rng)), length(cumw))

function make_transaction(rng, T, pats, cumw)
    target = max(1, poisson(rng, T))
    t = Set{Int}()
    while length(t) < target
        p = pats[pick(rng, cumw)]
        items = [x for x in p.items if rand(rng) >= p.corruption / 2]
        isempty(items) && continue
        if length(t) + length(items) > target && !isempty(t) && rand(rng) < 0.5
            break                                        # mẫu không vừa: dừng ở nửa số trường hợp
        end
        union!(t, items)
    end
    return sort!(collect(t))
end

function main(args)
    opt(name, default) = (k = findfirst(==("--" * name), args); k === nothing ? default : args[k+1])
    N = parse(Int, opt("N", "50000"))
    n_items = parse(Int, opt("items", "1000"))
    n_patterns = parse(Int, opt("patterns", "500"))
    I = parse(Float64, opt("I", "4"))
    Ts = parse.(Int, split(opt("T", "5,10,15,20,25,30"), ","))
    seed = parse(Int, opt("seed", string(SEED)))
    dir = rootpath("data", "synthetic")
    mkpath(dir)
    pats, cumw = make_patterns(MersenneTwister(seed), n_patterns, n_items, I)
    for T in Ts
        rng = MersenneTwister(seed + T)                  # mỗi T một dòng ngẫu nhiên riêng, vẫn tái lập được
        path = joinpath(dir, "synth_T$(lpad(T, 2, '0')).txt")
        total = 0
        open(path, "w") do io
            for _ in 1:N
                t = make_transaction(rng, T, pats, cumw)
                total += length(t)
                println(io, join(t, ' '))
            end
        end
        println(rpad(basename(path), 18), "N = ", N, ", L̄ = ", round(total / N; digits = 2))
    end
end

main(ARGS)

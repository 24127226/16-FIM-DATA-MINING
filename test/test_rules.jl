# Kiểm thử sinh luật kết hợp (phần của B): so với giá trị tính tay và với định nghĩa.

@testset "Luật trên ví dụ hiệu sách (tính tay)" begin
    # A=1, C=2, D=3, T=4, W=5; N = 6; minsup 50% (σ = 3)
    db = read_spmf(joinpath(@__DIR__, "..", "data", "toy", "bookstore.txt"))
    fis = eclat(db, 3)
    rs = rules(fis, n_transactions(db); minconf = 0.0)
    find(X, Y) = only(r for r in rs if r.antecedent == Int32.(X) && r.consequent == Int32.(Y))
    # {A} ⇒ {C}: σ(AC) = 4, σ(A) = 4 → conf 1; σ(C) = 6 → lift = 1 / (6/6) = 1
    r = find([1], [2])
    @test r.support_count == 4 && r.confidence == 1.0 && r.lift == 1.0
    # {T} ⇒ {A}: σ(AT) = 3, σ(T) = 4 → conf 0,75; σ(A) = 4 → lift = 0,75 / (4/6) = 1,125
    r = find([4], [1])
    @test r.confidence ≈ 0.75 && r.lift ≈ 1.125 && r.support ≈ 0.5
    # {A, T} ⇒ {W}: σ(ATW) = 3, σ(AT) = 3 → conf 1; σ(W) = 5 → lift = 1,2
    r = find([1, 4], [5])
    @test r.confidence == 1.0 && r.lift ≈ 1.2
    # Bài báo (Fig. 1) liệt kê các luật có confidence 100%: đếm lại
    @test count(r -> r.confidence == 1.0, rs) == length(rules(fis, 6; minconf = 1.0))
    @test all(r -> r.confidence >= 0.8, rules(fis, 6; minconf = 0.8))
end

@testset "Số luật đúng bằng định nghĩa" begin
    rng = MersenneTwister(5)
    db = TransactionDB([Int32[x for x in 1:8 if rand(rng) < 0.5] for _ in 1:60], collect(Int64, 1:8))
    fis = eclat(db, 10)
    rs = rules(fis, 60; minconf = 0.0)
    @test length(rs) == sum(2^length(Z) - 2 for Z in keys(fis) if length(Z) >= 2; init = 0)
    for r in rs
        Z = sort(vcat(r.antecedent, r.consequent))
        @test isempty(intersect(r.antecedent, r.consequent))
        @test r.confidence ≈ fis[Z] / fis[r.antecedent]
        @test r.lift ≈ r.confidence / (fis[r.consequent] / 60)
    end
end

@testset "top_k: đúng thứ tự, xác định" begin
    rng = MersenneTwister(9)
    db = TransactionDB([Int32[x for x in 1:10 if rand(rng) < 0.4] for _ in 1:200], collect(Int64, 1:10))
    rs = rules(eclat(db, 8), 200; minconf = 0.2)
    t = top_k(rs, 10; by = :lift)
    @test length(t) == min(10, length(rs))
    @test issorted([r.lift for r in t]; rev = true)
    @test t == top_k(reverse(rs), 10; by = :lift)                # không phụ thuộc thứ tự đầu vào
    @test top_k(rs, 5; by = :confidence)[1].confidence == maximum(r.confidence for r in rs)
    @test format_rule(t[1], string.(1:10)) isa String
end

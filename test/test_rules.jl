# Kiểm thử sinh luật kết hợp và top-k theo lift (mục 7.3, R18).

@testset "Luật kết hợp tính tay trên CSDL nhỏ" begin
    # 4 giao dịch:
    #   T1: {1, 2}
    #   T2: {1, 2}
    #   T3: {1, 3}
    #   T4: {2, 3}
    # σ(1)=3, σ(2)=3, σ(3)=2, σ(1,2)=2, σ(1,3)=1, σ(2,3)=1
    # Với minsup = 2: tập phổ biến là {1}:3, {2}:3, {3}:2, {1,2}:2.
    # Hai luật duy nhất:
    #   {1} ⇒ {2}: sup=2/4=0.5, conf=2/3, lift=(2/3)/(3/4) = 8/9
    #   {2} ⇒ {1}: sup=2/4=0.5, conf=2/3, lift=(2/3)/(3/4) = 8/9
    db = read_spmf(IOBuffer("1 2\n1 2\n1 3\n2 3\n"))
    isets = eclat(db, 2, VARIANTS["v0"])

    rs = rules(isets, n_transactions(db); minconf = 0.5)
    @test length(rs) == 2
    for r in rs
        @test r.support_count == 2
        @test isapprox(r.support, 0.5; atol = 1e-12)
        @test isapprox(r.confidence, 2 / 3; atol = 1e-12)
        @test isapprox(r.lift, 8 / 9; atol = 1e-12)
    end

    # Ngưỡng minconf cao hơn 2/3 -> không còn luật nào
    @test isempty(rules(isets, n_transactions(db); minconf = 0.7))
end

@testset "Pasquier99: kiểm tra lift, confidence và top_k" begin
    p99 = read_spmf(joinpath(REPO_ROOT, "data", "toy", "pasquier99.txt"))
    n = n_transactions(p99)
    isets = eclat(p99, 2, VARIANTS["v0"])

    all_rules = rules(isets, n; minconf = 0.0)
    # Số luật tổng cộng = sum(2^|I| - 2 cho mọi tập |I| >= 2)
    expected_count = sum((1 << length(k)) - 2 for k in keys(isets) if length(k) >= 2)
    @test length(all_rules) == expected_count

    # Mọi luật đều thỏa mãn công thức toán học
    for r in all_rules
        xy = sort!(vcat(r.antecedent, r.consequent))
        @test r.support_count == isets[xy]
        @test isapprox(r.support, isets[xy] / n; atol = 1e-12)
        @test isapprox(r.confidence, isets[xy] / isets[r.antecedent]; atol = 1e-12)
        @test isapprox(r.lift, (isets[xy] * n) / (isets[r.antecedent] * isets[r.consequent]); atol = 1e-12)
    end

    # top_k theo lift phải khớp với sắp xếp toàn bộ
    tk5 = top_k(all_rules, 5; by = :lift)
    @test length(tk5) == 5
    @test issorted([r.lift for r in tk5]; rev = true)
    sorted_lifts = sort([r.lift for r in all_rules]; rev = true)
    @test isapprox([r.lift for r in tk5], sorted_lifts[1:5]; atol = 1e-12)

    # top_k theo confidence và support
    tk_conf = top_k(all_rules, 10; by = :confidence)
    @test length(tk_conf) == 10
    @test issorted([r.confidence for r in tk_conf]; rev = true)

    # Ca biên của top_k và rules
    @test isempty(top_k(all_rules, 0))
    @test isempty(top_k(Rule[], 5))
    @test length(top_k(all_rules, 10_000)) == length(all_rules)
    @test isempty(rules(Dict{Vector{Int32},Int}(), 10; minconf = 0.5))
    @test isempty(rules(isets, 0; minconf = 0.5))

    @test_throws ArgumentError rules(isets, -1; minconf = 0.5)
    @test_throws ArgumentError rules(isets, n; minconf = 1.5)
    @test_throws ArgumentError top_k(all_rules, -1)
    @test_throws ArgumentError top_k(all_rules, 5; by = :invalid)
end

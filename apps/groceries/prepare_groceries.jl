# Chuyển đổi dữ liệu Groceries (CSV) sang định dạng giao dịch SPMF (kèm dòng @ITEM=)
# cho Ứng dụng 1 (phần của B, KE_HOACH_DU_AN.md mục 9.2, R17).
#
# Hỗ trợ 2 phương án biến đổi để so sánh trong bảng B08:
#   - Phương án 1 (:fine)   : giữ nguyên 169 mặt hàng gốc (phương án chọn).
#   - Phương án 2 (:coarse) : gộp mặt hàng theo nhóm hàng cấp cao (~12 nhóm siêu thị).

using DataStructures: counter, inc!

"""Đọc file `groceries.csv`, trả về danh sách các giỏ hàng (mỗi giỏ là tập tên mặt hàng đã chuẩn hóa)."""
function load_groceries_raw(csv_path::AbstractString)::Vector{Vector{String}}
    isfile(csv_path) || error("Không tìm thấy $csv_path. Hãy chạy `julia --project=. scripts/fetch_data.jl groceries`.")
    baskets = Vector{Vector{String}}()
    open(csv_path, "r") do io
        for line in eachline(io)
            s = strip(line)
            isempty(s) && continue
            items = String[]
            for tok in split(s, ',')
                name = strip(tok)
                isempty(name) && continue
                name in items || push!(items, name)
            end
            isempty(items) || push!(baskets, items)
        end
    end
    return baskets
end

"""Ánh xạ tên mặt hàng Groceries sang nhóm hàng cấp cao (phương án so sánh cho B08)."""
function map_to_category(item::AbstractString)::String
    s = lowercase(item)
    if occursin(r"milk|yogurt|butter|cheese|cream|curd|margarine|ice cream|pudding|mayonnaise|egg", s)
        return "dairy_eggs"
    elseif occursin(r"fruit|vegetable|berries|herb|onion|grape|nut|prune|plant|flower|potato|salad", s)
        return "produce"
    elseif occursin(r"beef|pork|chicken|sausage|ham|frankfurter|turkey|meat|fish|liver|poultry|salami", s)
        return "meat_seafood"
    elseif occursin(r"bread|rolls|buns|pastry|cake|waffle|zwieback|bakery|dough|flour|bun|toast|cracker", s)
        return "bakery"
    elseif occursin(r"beer|wine|liquor|brandy|rum|whisky|prosecco|sparkling|aperitif|alcohol", s)
        return "alcohol"
    elseif occursin(r"water|soda|juice|coffee|tea|cocoa|drink|syrup|lemonade|beverag", s)
        return "beverages_nonalc"
    elseif occursin(r"chocolat|candy|sweet|snack|popcorn|gum|jam|honey|sugar|dessert|biscuit|wafer|marshmallow|syrup|nut snack", s)
        return "snacks_sweets"
    elseif occursin(r"frozen|instant|ready|pizza|spread|soup|canned|preserved", s)
        return "frozen_ready"
    elseif occursin(r"cleaner|detergent|softener|bag|napkin|towel|foil|cling|cookware|dish|bulb|candle|match|bathroom|kitchen|house|decalcifier|abrasive|toilet|tissue|sponge|scour", s)
        return "household_cleaning"
    elseif occursin(r"soap|shampoo|cosmetic|hygiene|dental|skin|hair|diaper|sanitary|rub|care|deodorant|lotion|perfume|make up|male|female", s)
        return "personal_care"
    elseif occursin(r"rice|pasta|oil|vinegar|salt|spice|sauce|cereal|oatmeal|mustard|ketchup|baking|yeast|pickle|seasoning|noodle|grain|honey|dressing|baby food|organic", s)
        return "pantry_dry"
    else
        return "other"
    end
end

"""
    export_baskets_spmf(baskets, out_path) -> (id_to_name, item_counts)

Xuất danh sách giỏ hàng sang file định dạng SPMF kèm header `@ITEM=mã=tên`.
Dùng `DataStructures.counter` để đếm tần suất từng mặt hàng (R03).
"""
function export_baskets_spmf(baskets::Vector{Vector{String}}, out_path::AbstractString)
    counts = counter(String)
    for b in baskets
        for item in b
            inc!(counts, item)
        end
    end

    names = sort!(collect(keys(counts)))
    name_to_id = Dict{String,Int}(name => idx for (idx, name) in enumerate(names))
    id_to_name = Dict{Int64,String}(Int64(idx) => name for (idx, name) in enumerate(names))

    mkpath(dirname(out_path))
    open(out_path, "w") do io
        println(io, "@CONVERTED_FROM_TEXT")
        for (idx, name) in enumerate(names)
            println(io, "@ITEM=", idx, "=", name)
        end
        for b in baskets
            ids = sort!(unique([name_to_id[x] for x in b]))
            println(io, join(ids, ' '))
        end
    end

    return (id_to_name = id_to_name, counts = counts)
end

"""Chuẩn bị cả hai phương án biến đổi dữ liệu Groceries."""
function prepare_all_groceries(csv_path::AbstractString, out_dir::AbstractString)
    raw = load_groceries_raw(csv_path)

    # Phương án 1: 169 mặt hàng gốc
    fine_path = joinpath(out_dir, "groceries_items.txt")
    fine_meta = export_baskets_spmf(raw, fine_path)

    # Phương án 2: gộp theo nhóm hàng cấp cao
    coarse_baskets = [unique([map_to_category(x) for x in b]) for b in raw]
    coarse_path = joinpath(out_dir, "groceries_categories.txt")
    coarse_meta = export_baskets_spmf(coarse_baskets, coarse_path)

    return (
        raw = raw,
        fine = (path = fine_path, id_to_name = fine_meta.id_to_name, counts = fine_meta.counts),
        coarse = (path = coarse_path, id_to_name = coarse_meta.id_to_name, counts = coarse_meta.counts),
    )
end

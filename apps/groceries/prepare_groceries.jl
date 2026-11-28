# Mô-đun tiền xử lý và biến đổi dữ liệu Groceries (CSV) sang định dạng giao dịch SPMF
# kèm bảng ánh xạ `@ITEM=mã=tên` phục vụ Ứng dụng 1.
#
# Hai phương án biểu diễn được cài đặt phục vụ so sánh định lượng (Bảng B08):
#   - Phương án 1 (:fine)   : giữ nguyên 169 mặt hàng gốc (phương án lựa chọn).
#   - Phương án 2 (:coarse) : gom nhóm mặt hàng theo 12 nhóm hàng cấp cao.

using DataStructures: counter, inc!                          # Dùng counter của DataStructures.jl để đếm tần suất sản phẩm

"""
    load_groceries_raw(csv_path::AbstractString) -> Vector{Vector{String}}

Mục đích hàm: Đọc tệp `groceries.csv` (mỗi dòng là một hóa đơn siêu thị phân tách bằng dấu phẩy),
làm sạch khoảng trắng và loại bỏ sản phẩm trùng lặp trong cùng một giỏ hàng.
"""
function load_groceries_raw(csv_path::AbstractString)::Vector{Vector{String}}
    isfile(csv_path) || error("Không tìm thấy $csv_path. Hãy chạy `julia --project=. scripts/fetch_data.jl groceries`.")
    baskets = Vector{Vector{String}}()                       # Danh sách chứa toàn bộ 9.835 giỏ hàng
    open(csv_path, "r") do io
        for line in eachline(io)                             # Đọc từng dòng hóa đơn
            s = strip(line)                                  # Xóa khoảng trắng và ký tự xuống dòng thừa
            isempty(s) && continue                           # Bỏ qua dòng trống
            items = String[]                                 # Danh sách mặt hàng trong giỏ hiện tại
            for tok in split(s, ',')                         # Tách từng tên sản phẩm theo dấu phẩy
                name = strip(tok)
                isempty(name) && continue                    # Bỏ qua ô rỗng
                name in items || push!(items, name)          # Khử trùng lặp nếu cùng 1 sản phẩm xuất hiện 2 lần trong hóa đơn
            end
            isempty(items) || push!(baskets, items)          # Chỉ thêm giỏ khác rỗng vào danh sách
        end
    end
    return baskets
end

"""
    map_to_category(item::AbstractString) -> String

Mục đích hàm: Ánh xạ tên một mặt hàng chi tiết (trong 169 mặt hàng của Groceries) về 1 trong 12
nhóm hàng siêu thị cấp cao (phục vụ phương án biến đổi thứ 2 trong Bảng B08 để so sánh mật độ).
"""
function map_to_category(item::AbstractString)::String
    s = lowercase(item)                                      # Đưa về chữ thường để khớp biểu thức chính quy ổn định
    if occursin(r"milk|yogurt|butter|cheese|cream|curd|margarine|ice cream|pudding|mayonnaise|egg", s)
        return "dairy_eggs"                                  # Nhóm sữa, chế phẩm sữa và trứng
    elseif occursin(r"fruit|vegetable|berries|herb|onion|grape|nut|prune|plant|flower|potato|salad", s)
        return "produce"                                     # Nhóm rau củ quả tươi
    elseif occursin(r"beef|pork|chicken|sausage|ham|frankfurter|turkey|meat|fish|liver|poultry|salami", s)
        return "meat_seafood"                                # Nhóm thịt và hải sản
    elseif occursin(r"bread|rolls|buns|pastry|cake|waffle|zwieback|bakery|dough|flour|bun|toast|cracker", s)
        return "bakery"                                      # Nhóm bánh mì và đồ nướng
    elseif occursin(r"beer|wine|liquor|brandy|rum|whisky|prosecco|sparkling|aperitif|alcohol", s)
        return "alcohol"                                     # Nhóm đồ uống có cồn
    elseif occursin(r"water|soda|juice|coffee|tea|cocoa|drink|syrup|lemonade|beverag", s)
        return "beverages_nonalc"                            # Nhóm nước giải khát không cồn
    elseif occursin(r"chocolat|candy|sweet|snack|popcorn|gum|jam|honey|sugar|dessert|biscuit|wafer|marshmallow|syrup|nut snack", s)
        return "snacks_sweets"                               # Nhóm bánh kẹo và đồ ăn vặt
    elseif occursin(r"frozen|instant|ready|pizza|spread|soup|canned|preserved", s)
        return "frozen_ready"                                # Nhóm thực phẩm đông lạnh / chế biến sẵn
    elseif occursin(r"cleaner|detergent|softener|bag|napkin|towel|foil|cling|cookware|dish|bulb|candle|match|bathroom|kitchen|house|decalcifier|abrasive|toilet|tissue|sponge|scour", s)
        return "household_cleaning"                          # Nhóm đồ gia dụng và tẩy rửa
    elseif occursin(r"soap|shampoo|cosmetic|hygiene|dental|skin|hair|diaper|sanitary|rub|care|deodorant|lotion|perfume|make up|male|female", s)
        return "personal_care"                               # Nhóm chăm sóc cá nhân
    elseif occursin(r"rice|pasta|oil|vinegar|salt|spice|sauce|cereal|oatmeal|mustard|ketchup|baking|yeast|pickle|seasoning|noodle|grain|honey|dressing|baby food|organic", s)
        return "pantry_dry"                                  # Nhóm thực phẩm khô và gia vị
    else
        return "other"                                       # Nhóm hàng khác còn lại
    end
end

"""
    export_baskets_spmf(baskets, out_path) -> (id_to_name, counts)

Mục đích hàm: Chuyển danh sách giỏ hàng dạng chữ sang tệp giao dịch chuẩn SPMF (các số nguyên
cách nhau dấu cách) kèm phần đầu siêu dữ liệu `@ITEM=mã=tên` để tra ngược tên mặt hàng khi phân tích luật.
"""
function export_baskets_spmf(baskets::Vector{Vector{String}}, out_path::AbstractString)
    counts = counter(String)                                 # Bộ đếm tần suất từng mặt hàng bằng DataStructures.counter
    for b in baskets
        for item in b
            inc!(counts, item)                               # Tăng số lần xuất hiện của mặt hàng `item` lên 1
        end
    end

    names = sort!(collect(keys(counts)))                     # Sắp tên mặt hàng theo thứ tự bảng chữ cái để gán mã cố định
    name_to_id = Dict{String,Int}(name => idx for (idx, name) in enumerate(names))   # Ánh xạ tên -> mã số 1..m
    id_to_name = Dict{Int64,String}(Int64(idx) => name for (idx, name) in enumerate(names)) # Ánh xạ ngược mã số -> tên

    mkpath(dirname(out_path))                                # Tạo thư mục đích nếu chưa có
    open(out_path, "w") do io
        println(io, "@CONVERTED_FROM_TEXT")                  # Dòng header chuẩn SPMF (sẽ được read_spmf tự bỏ qua)
        for (idx, name) in enumerate(names)                  # Ghi bảng từ điển mã -> tên sản phẩm
            println(io, "@ITEM=", idx, "=", name)
        end
        for b in baskets                                     # Ghi từng hóa đơn thành 1 dòng mã số tăng dần
            ids = sort!(unique([name_to_id[x] for x in b]))
            println(io, join(ids, ' '))
        end
    end

    return (id_to_name = id_to_name, counts = counts)        # Trả về bảng tên và bộ đếm tần suất
end

"""
    prepare_all_groceries(csv_path, out_dir)

Mục đích hàm: Chạy trọn gói tiền xử lý và xuất đồng thời cả hai phương án biến đổi dữ liệu
(`groceries_items.txt` 169 mặt hàng gốc và `groceries_categories.txt` 12 nhóm hàng).
"""
function prepare_all_groceries(csv_path::AbstractString, out_dir::AbstractString)
    raw = load_groceries_raw(csv_path)                       # Đọc toàn bộ giỏ hàng thô từ CSV

    # Phương án 1: giữ nguyên 169 mặt hàng chi tiết
    fine_path = joinpath(out_dir, "groceries_items.txt")
    fine_meta = export_baskets_spmf(raw, fine_path)

    # Phương án 2: gộp mỗi mặt hàng về 12 nhóm cấp cao và khử trùng nhóm trong cùng giỏ
    coarse_baskets = [unique([map_to_category(x) for x in b]) for b in raw]
    coarse_path = joinpath(out_dir, "groceries_categories.txt")
    coarse_meta = export_baskets_spmf(coarse_baskets, coarse_path)

    return (
        raw = raw,
        fine = (path = fine_path, id_to_name = fine_meta.id_to_name, counts = fine_meta.counts),
        coarse = (path = coarse_path, id_to_name = coarse_meta.id_to_name, counts = coarse_meta.counts),
    )
end

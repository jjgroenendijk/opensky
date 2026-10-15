-- Fix what the gfm writer cannot express, so no content is lost.

-- Fence every code block with its language. The gfm writer drops a language it does
-- not know, such as papyrus.
function CodeBlock(block)
  local fence = "```"
  while block.text:find(fence, 1, true) do
    fence = fence .. "`"
  end
  local language = block.classes[1] or "text"
  return pandoc.RawBlock("gfm", fence .. language .. "\n" .. block.text .. "\n" .. fence)
end

local function all_rows(tbl)
  local rows = {}
  for _, row in ipairs(tbl.head.rows) do table.insert(rows, row) end
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.head) do table.insert(rows, row) end
    for _, row in ipairs(body.body) do table.insert(rows, row) end
  end
  for _, row in ipairs(tbl.foot.rows) do table.insert(rows, row) end
  return rows
end

local function has_line_break(blocks)
  local found = false
  pandoc.Blocks(blocks):walk({ LineBreak = function() found = true end })
  return found
end

local function is_simple(cell)
  if cell.row_span ~= 1 or cell.col_span ~= 1 or #cell.contents > 1 then return false end
  local block = cell.contents[1]
  if block == nil then return true end
  return (block.t == "Plain" or block.t == "Para") and not has_line_break(cell.contents)
end

local function slash() return { pandoc.Space(), pandoc.Str("/"), pandoc.Space() } end

-- List items become separate blocks, so flattening keeps a separator between them.
local function unlist(blocks)
  local flat = {}
  for _, block in ipairs(blocks) do
    if block.t == "BulletList" or block.t == "OrderedList" then
      for _, item in ipairs(block.content) do
        for _, inner in ipairs(unlist(item)) do table.insert(flat, inner) end
      end
    else
      table.insert(flat, block)
    end
  end
  return flat
end

-- A pipe table holds one line of inline text per cell. The writer prints [TABLE] for
-- anything else. A layout table, one row or one column, is unwrapped into its cells;
-- the cells of any other table are flattened to one line.
function Table(tbl)
  local rows = all_rows(tbl)
  local complex = false
  for _, row in ipairs(rows) do
    for _, cell in ipairs(row.cells) do
      if not is_simple(cell) then complex = true end
    end
  end
  if not complex then return nil end
  local widest = 0
  for _, row in ipairs(rows) do widest = math.max(widest, #row.cells) end
  if #rows == 1 or widest <= 1 then
    local blocks = {}
    for _, row in ipairs(rows) do
      for _, cell in ipairs(row.cells) do
        for _, block in ipairs(cell.contents) do table.insert(blocks, block) end
      end
    end
    return blocks
  end
  for _, row in ipairs(rows) do
    for _, cell in ipairs(row.cells) do
      local inlines = pandoc.utils.blocks_to_inlines(unlist(cell.contents), slash())
      inlines = pandoc.Inlines(inlines):walk({ LineBreak = slash })
      cell.contents = { pandoc.Plain(inlines) }
      cell.row_span = 1
      cell.col_span = 1
    end
  end
  return tbl
end

local blank = { LineBreak = true, Space = true, SoftBreak = true }

-- A bare <br> between blocks becomes a paragraph of line breaks, written as a lone
-- backslash. Drop such paragraphs and any break that starts or ends a paragraph.
local function trim_breaks(block)
  local inlines = block.content
  while #inlines > 0 and blank[inlines[#inlines].t] do inlines:remove(#inlines) end
  while #inlines > 0 and blank[inlines[1].t] do inlines:remove(1) end
  if #inlines == 0 then return {} end
  block.content = inlines
  return block
end

Para = trim_breaks
Plain = trim_breaks

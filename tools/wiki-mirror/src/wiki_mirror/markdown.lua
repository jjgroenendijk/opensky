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

-- The gfm writer ignores row and column spans, so the cells after a span slide into the
-- wrong column. Give each spanned position an empty cell instead.
local function expand_spans(rows)
  local carried = {}
  local expanded = pandoc.List()
  for _, row in ipairs(rows) do
    local cells = pandoc.List()
    local column = 1
    local function fill(last)
      while column <= last and (carried[column] or 0) > 0 do
        carried[column] = carried[column] - 1
        cells:insert(pandoc.Cell({}))
        column = column + 1
      end
    end
    for _, cell in ipairs(row.cells) do
      fill(math.huge)
      local width, height = cell.col_span, cell.row_span
      cell.col_span, cell.row_span = 1, 1
      cells:insert(cell)
      for offset = 0, width - 1 do
        if height > 1 then carried[column + offset] = height - 1 end
        if offset > 0 then cells:insert(pandoc.Cell({})) end
      end
      column = column + width
    end
    fill(#carried)
    row.cells = cells
    expanded:insert(row)
  end
  return expanded
end

local function expand_table_spans(tbl)
  local head = tbl.head
  head.rows = expand_spans(head.rows)
  tbl.head = head
  local bodies = pandoc.List()
  for _, body in ipairs(tbl.bodies) do
    body.head = expand_spans(body.head)
    body.body = expand_spans(body.body)
    bodies:insert(body)
  end
  tbl.bodies = bodies
  local foot = tbl.foot
  foot.rows = expand_spans(foot.rows)
  tbl.foot = foot
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

-- A row of a nested table becomes one line: "1 (0x1): Include Directory Names".
local function row_line(row)
  local line = pandoc.Inlines({})
  local separator = #row.cells == 2 and ": " or ", "
  for _, cell in ipairs(row.cells) do
    local text = pandoc.utils.blocks_to_inlines(cell.contents, { pandoc.Space() })
    if #text > 0 then
      if #line > 0 then line:extend({ pandoc.Str(separator:sub(1, 1)), pandoc.Space() }) end
      line:extend(text)
    end
  end
  return pandoc.Plain(line)
end

-- List items and nested table rows become separate blocks, so flattening keeps a
-- separator between them.
local function unlist(blocks)
  local flat = {}
  for _, block in ipairs(blocks) do
    if block.t == "BulletList" or block.t == "OrderedList" then
      for _, item in ipairs(block.content) do
        for _, inner in ipairs(unlist(item)) do table.insert(flat, inner) end
      end
    elseif block.t == "Table" then
      for _, row in ipairs(all_rows(block)) do table.insert(flat, row_line(row)) end
    else
      table.insert(flat, block)
    end
  end
  return flat
end

local function has_header(tbl)
  for _, row in ipairs(tbl.head.rows) do
    for _, cell in ipairs(row.cells) do
      if #cell.contents > 0 then return true end
    end
  end
  return false
end

local function cell_inlines(cell)
  if cell == nil then return pandoc.Inlines({}) end
  local inlines = pandoc.utils.blocks_to_inlines(unlist(cell.contents), slash())
  return pandoc.Inlines(inlines):walk({ LineBreak = slash })
end

-- An infobox is a table of label and value rows without a header. A pipe table must
-- have a header, so it would get an empty one; a list of labelled lines reads better.
local function key_value_list(rows)
  local items = {}
  for _, row in ipairs(rows) do
    local label, value = cell_inlines(row.cells[1]), cell_inlines(row.cells[2])
    if #label == 1 and label[1].t == "Strong" then label = label[1].content end
    local text = pandoc.utils.stringify(label)
    local line = pandoc.Inlines({})
    if #value == 0 then
      line:extend(label)
    elseif text ~= "" then
      if not text:find(":%s*$") then label:insert(pandoc.Str(":")) end
      line:extend({ pandoc.Strong(label), pandoc.Space() })
    end
    line:extend(value)
    if #line > 0 then table.insert(items, { pandoc.Plain(line) }) end
  end
  return pandoc.BulletList(items)
end

-- A pipe table holds one line of inline text per cell. The writer prints [TABLE] for
-- anything else. A layout table, one row or one column, is unwrapped into its cells;
-- the cells of any other table are flattened to one line.
local function cell_blocks(rows)
  local blocks = {}
  for _, row in ipairs(rows) do
    for _, cell in ipairs(row.cells) do
      for _, block in ipairs(cell.contents) do table.insert(blocks, block) end
    end
  end
  return blocks
end

-- A cell that holds a heading or a table is part of a page layout, not of a data table.
local function holds_layout(rows)
  local found = false
  local mark = function() found = true end
  for _, row in ipairs(rows) do
    for _, cell in ipairs(row.cells) do
      pandoc.Blocks(cell.contents):walk({ Header = mark, Table = mark })
    end
  end
  return found
end

local function pipe_table(tbl)
  expand_table_spans(tbl)
  local rows = all_rows(tbl)
  local widest = 0
  for _, row in ipairs(rows) do widest = math.max(widest, #row.cells) end
  if #rows == 1 or widest <= 1 or holds_layout(rows) then return cell_blocks(rows) end
  if widest == 2 and not has_header(tbl) then return key_value_list(rows) end
  for _, row in ipairs(rows) do
    for _, cell in ipairs(row.cells) do
      if not is_simple(cell) then cell.contents = { pandoc.Plain(cell_inlines(cell)) } end
    end
  end
  return tbl
end

-- The writer puts a caption below the table with the table's classes, as "Title
-- {.wikitable}". Give the caption its own line above the table instead.
function Table(tbl)
  local caption = pandoc.utils.blocks_to_inlines(tbl.caption.long)
  tbl.caption = pandoc.Caption()
  tbl.attr = pandoc.Attr()
  local result = pipe_table(tbl)
  if #caption == 0 then return result end
  local blocks = pandoc.Blocks({ pandoc.Para({ pandoc.Strong(caption) }) })
  blocks:extend(pandoc.Blocks(result))
  return blocks
end

local blank = { LineBreak = true, Space = true, SoftBreak = true }

-- A paragraph of no-break spaces, used on the wiki as a spacer, is also blank.
local function is_blank(inline)
  return blank[inline.t] or (inline.t == "Str" and inline.text:gsub("\u{a0}", "") == "")
end

-- A bare <br> between blocks becomes a paragraph of line breaks, written as a lone
-- backslash. Drop such paragraphs and any break that starts or ends a paragraph.
local function trim_breaks(block)
  local inlines = block.content
  while #inlines > 0 and is_blank(inlines[#inlines]) do inlines:remove(#inlines) end
  while #inlines > 0 and is_blank(inlines[1]) do inlines:remove(1) end
  if #inlines == 0 then return {} end
  block.content = inlines
  return block
end

Para = trim_breaks
Plain = trim_breaks

-- GFM has no definition list; the writer fakes one per <dl>, and the wiki writes one <dl>
-- per term. Write the term as its own line, then its text.
function DefinitionList(list)
  local blocks = {}
  for _, item in ipairs(list.content) do
    local term, definitions = item[1], item[2]
    if #term > 0 then table.insert(blocks, pandoc.Para(term)) end
    for _, definition in ipairs(definitions) do
      for _, block in ipairs(definition) do table.insert(blocks, block) end
    end
  end
  return blocks
end

local function continues(last, block)
  if last == nil or last.t ~= block.t then return false end
  if block.t == "BulletList" then return true end
  return block.t == "OrderedList" and block.start == last.start + #last.content
end

-- The writer separates two lists in a row with a "&nbsp;" line, so join them. An
-- ordered list joins only when its numbers go on from the list before it.
function Blocks(blocks)
  local joined = pandoc.Blocks({})
  for _, block in ipairs(blocks) do
    local last = joined[#joined]
    if continues(last, block) then
      last.content:extend(block.content)
    else
      joined:insert(block)
    end
  end
  return joined
end

-- An id that a link points at, kept as an empty anchor: `<a id="iron-helmet"></a>`.
function Span(span)
  if span.identifier == "" or span.classes:includes("mw-headline") then return nil end
  local anchor = pandoc.RawInline("gfm", '<a id="' .. span.identifier .. '"></a>')
  local inlines = pandoc.Inlines({ anchor })
  inlines:extend(span.content)
  return inlines
end

-- The anchor a GitHub renderer makes from heading text: "Iron Armor" becomes "iron-armor".
local function slug(text)
  local lowered = pandoc.text.lower(text):gsub("[^%w%-_ \128-\255]", "")
  return (lowered:gsub("^%s+", ""):gsub("%s+$", ""):gsub(" ", "-"))
end

-- A section id that the heading text does not produce, such as the id of a second
-- "Shields" heading or of a heading that holds an image, stays as an anchor.
function Header(header)
  local id
  header.content = header.content:walk({
    Span = function(span)
      if span.classes:includes("mw-headline") then
        id = span.identifier
        return span.content
      end
    end,
  })
  local text = pandoc.utils.stringify(header.content:walk({ Image = function() return {} end }))
  if id ~= nil and id ~= "" and slug(text) ~= id then
    header.content:insert(1, pandoc.RawInline("gfm", '<a id="' .. id .. '"></a>'))
  end
  return header
end

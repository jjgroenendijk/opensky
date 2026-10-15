-- Write every code block as a fenced block with its language. The gfm writer
-- drops a language it does not know, such as papyrus.
function CodeBlock(block)
  local fence = "```"
  while block.text:find(fence, 1, true) do
    fence = fence .. "`"
  end
  local language = block.classes[1] or "text"
  return pandoc.RawBlock("gfm", fence .. language .. "\n" .. block.text .. "\n" .. fence)
end

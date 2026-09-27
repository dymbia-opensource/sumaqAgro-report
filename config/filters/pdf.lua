--[[
  pdf.lua — Filtro Lua para exportar el informe (Markdown para GitHub) a PDF.

  Resuelve lo que Pandoc NO convierte a LaTeX por sí solo:
    1. Bloques HTML (<p align="center"><img></p>, <table> de entrevistas, etc.)
       -> se re-interpretan como HTML y se convierten a elementos Pandoc.
    2. <br> dentro de tablas Markdown -> salto de línea real.
    3. <img> en línea (fotos del equipo) -> imagen real.
    4. <div style="page-break-after: always;"></div> -> \clearpage.
    5. Anchos en px de las imágenes -> porcentaje del ancho de línea.
    6. Imágenes solas en un párrafo -> centradas.
    7. Cada encabezado de nivel 1 (# ...) inicia en una página nueva.
    8. Genera la carátula a partir del bloque `cover:` de metadata.yaml.

  Compatible con Pandoc 2.9+ y 3.x.
]]

local stringify = pandoc.utils.stringify
local MAX_PX = 650  -- ancho (px) que se considera 100% del ancho de línea

local function latex(s) return pandoc.RawBlock('latex', s) end
local function is_html(fmt) return fmt == 'html' or fmt == 'html5' end

-- ---------------------------------------------------------------- pasada 1
local function html_attr(tag, name)
  return tag:match(name .. '%s*=%s*"([^"]*)"') or tag:match(name .. "%s*=%s*'([^']*)'")
end

local function img_from_tag(tag)
  local src = html_attr(tag, 'src')
  if not src then return nil end
  local img = pandoc.Image({pandoc.Str(html_attr(tag, 'alt') or '')}, src)
  local w = html_attr(tag, 'width')
  if w then img.attributes.width = w end
  return img
end

local pass1 = {
  RawBlock = function(el)
    if not is_html(el.format) then return nil end
    local t = el.text
    if t:match('page%-break') then return latex('\\clearpage') end
    if t:match('^%s*<!%-%-') then return {} end            -- comentarios HTML
    local ok, doc = pcall(pandoc.read, t, 'html')
    if ok and doc and #doc.blocks > 0 then return doc.blocks end
    return nil
  end,

  RawInline = function(el)
    if not is_html(el.format) then return nil end
    local t = el.text
    if t:match('^<br') then return pandoc.LineBreak() end
    if t:match('^<img') then return img_from_tag(t) or {} end
    -- etiquetas de formato sueltas (<b>, </b>, <span ...>, etc.): se omiten
    if t:match('^</?%a[%w]*[^>]*>$') then return {} end
    return pandoc.Str(t)
  end,
}

-- ---------------------------------------------------------------- pasada 2
local function normalize_width(img)
  -- Se reconstruyen los atributos: solo se conserva `width` (en %),
  -- el alto se calcula manteniendo la proporción.
  local w = img.attributes.width
  local attrs = {}
  if w then
    local px = tonumber(w:match('^(%d+)%s*p?x?$'))
    if px then
      w = math.min(100, math.floor(px * 100 / MAX_PX + 0.5)) .. '%'
    end
    attrs = { {'width', w} }
  end
  img.attr = pandoc.Attr(img.identifier, img.classes, attrs)
  return img
end

-- Anchos de columna: en tablas con texto largo (o saltos <br>) se reparten
-- según la cantidad de texto de cada columna, en lugar de los guiones de
-- la fila separadora (| :--- |), que en GitHub no importan pero en PDF sí.
local function cell_text(cell)
  -- Pandoc 3: Cell {contents=...}; Pandoc 2.9: lista de bloques
  local c = cell.contents or cell
  return stringify(c)
end

local function rows_of(tbl)
  local rows = {}
  if tbl.bodies then                                   -- Pandoc >= 2.10
    for _, r in ipairs(tbl.head.rows or {}) do rows[#rows + 1] = r.cells end
    for _, b in ipairs(tbl.bodies) do
      for _, r in ipairs(b.body) do rows[#rows + 1] = r.cells end
    end
  else                                                 -- Pandoc 2.9
    rows[#rows + 1] = tbl.headers
    for _, r in ipairs(tbl.rows) do rows[#rows + 1] = r end
  end
  return rows
end

local function fix_table(tbl)
  -- Imágenes dentro de celdas (fotos, capturas): ocupan el ancho de su columna
  if tbl.walk then
    tbl = tbl:walk({ Image = function(i)
      i.attr = pandoc.Attr(i.identifier, i.classes, {}) return i end })
  end
  local rows = rows_of(tbl)
  local ncols = tbl.colspecs and #tbl.colspecs or #tbl.widths
  if ncols < 2 then return tbl end
  local weight, longest_row = {}, 0
  for i = 1, ncols do weight[i] = 0 end
  for _, cells in ipairs(rows) do
    local rowlen = 0
    for i, cell in ipairs(cells) do
      if i <= ncols then
        local n = utf8 and utf8.len(cell_text(cell)) or #cell_text(cell)
        n = n or 0
        rowlen = rowlen + n
        weight[i] = math.max(weight[i], math.min(n, 400))
      end
    end
    longest_row = math.max(longest_row, rowlen)
  end
  if longest_row < 90 then return tbl end              -- tabla corta: anchos sin cambios
  local total = 0
  for i = 1, ncols do
    weight[i] = math.sqrt(math.max(weight[i], 6))      -- suaviza extremos
    total = total + weight[i]
  end
  for i = 1, ncols do
    local w = weight[i] / total * 0.98
    if tbl.colspecs then tbl.colspecs[i][2] = w else tbl.widths[i] = w end
  end
  return tbl
end

local pass2 = {
  -- ::: {.center} ... ::: -> contenido centrado (carátula)
  Div = function(el)
    if el.classes:includes('center') then
      local out = { latex('\\begin{center}') }
      for _, b in ipairs(el.content) do out[#out + 1] = b end
      out[#out + 1] = latex('\\end{center}')
      return out
    end
  end,

  Image = normalize_width,
  Table = fix_table,

  Para = function(el)
    -- Las imágenes se separan del texto y se centran en su propio bloque
    -- (evita que una imagen que sigue a un texto se salga del margen).
    local has_img = false
    for _, x in ipairs(el.content) do
      if x.t == 'Image' then has_img = true break end
    end
    if not has_img then return nil end
    local out, buf = {}, {}
    local function flush()
      local only_space = true
      for _, x in ipairs(buf) do
        if x.t ~= 'Space' and x.t ~= 'SoftBreak' and x.t ~= 'LineBreak' then only_space = false end
      end
      if not only_space then out[#out + 1] = pandoc.Para(buf) end
      buf = {}
    end
    for _, x in ipairs(el.content) do
      if x.t == 'Image' then
        flush()
        out[#out + 1] = latex('\\begin{center}')
        out[#out + 1] = pandoc.Para({x})
        out[#out + 1] = latex('\\end{center}')
      else
        buf[#buf + 1] = x
      end
    end
    flush()
    return out
  end,

  Header = function(el)
    if el.level == 1 then return { latex('\\clearpage'), el } end
  end,
}

-- ---------------------------------------------------------------- carátula
local function esc(s)
  return (s:gsub('([&%%$#_{}])', '\\%1'))
end

local function m(meta, key) return meta[key] and esc(stringify(meta[key])) or '' end

local function build_cover(meta)
  local c = meta.cover
  if not c then return nil end
  local L = {}
  local function add(s) L[#L + 1] = s end
  add('\\begin{titlepage}\\centering')
  if c.logo then
    add('\\includegraphics[width=3.2cm]{' .. stringify(c.logo) .. '}\\par\\vspace{0.8cm}')
  end
  add('{\\large\\bfseries ' .. m(c, 'university') .. '\\par}\\vspace{0.2cm}')
  add('{\\large ' .. m(c, 'faculty') .. '\\par}')
  add('{\\large ' .. m(c, 'career') .. ' --- Ciclo ' .. m(c, 'term') .. '\\par}\\vspace{0.8cm}')
  add('{\\large\\bfseries ' .. m(c, 'course-code') .. ' ' .. m(c, 'course-name') .. '\\par}\\vspace{0.3cm}')
  add('{\\large NRC: ' .. m(c, 'nrc') .. '\\par}\\vspace{0.3cm}')
  add('{\\large Docente: ' .. m(c, 'instructor') .. '\\par}\\vspace{1cm}')
  add('{\\LARGE\\bfseries ' .. m(c, 'report-title') .. '\\par}\\vspace{0.3cm}')
  add('{\\large Entrega: ' .. m(c, 'milestone') .. '\\par}\\vspace{0.8cm}')
  add('{\\large Startup: \\textbf{' .. m(c, 'startup') .. '}\\par}\\vspace{0.2cm}')
  add('{\\large Producto: \\textbf{' .. m(c, 'product') .. '}\\par}\\vspace{0.8cm}')
  add('{\\large\\bfseries Integrantes\\par}\\vspace{0.3cm}')
  add('\\begin{tabular}{ll}\\textbf{Código} & \\textbf{Apellidos y Nombres}\\\\\\hline')
  for _, mem in ipairs(c.members or {}) do
    add(m(mem, 'code') .. ' & ' .. m(mem, 'name') .. '\\\\')
  end
  add('\\end{tabular}\\par\\vfill')
  add('{\\large ' .. m(c, 'date') .. '\\par}')
  add('\\end{titlepage}')
  return latex(table.concat(L, '\n'))
end

local pass3 = {
  Pandoc = function(doc)
    local cover = build_cover(doc.meta)
    if cover then table.insert(doc.blocks, 1, cover) end
    return doc
  end,
}

return { pass1, pass2, pass3 }

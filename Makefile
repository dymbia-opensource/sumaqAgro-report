# =====================================================================
# Compilación del Informe (Docs-as-Code) — Pandoc + XeLaTeX
#   make pdf                    -> dist/upc-pre-202620-1asi0729-7742-dymbia-report-tb1.pdf
#   make pdf MILESTONE=av2      -> ...-report-av2.pdf
#   make pdf FONTS=linux        -> usa Liberation Sans/Mono (Linux / WSL)
# =====================================================================
CONFIG    = config/build.yaml
DIST_DIR  = dist
NRC       = 7742
STARTUP   = dymbia
MILESTONE = tb1
OUTPUT    = $(DIST_DIR)/upc-pre-202620-1asi0729-$(NRC)-$(STARTUP)-report-$(MILESTONE).pdf

ifeq ($(FONTS),linux)
FONT_OPTS = -V mainfont="Liberation Sans" -V monofont="Liberation Mono"
endif

.PHONY: all pdf tex clean

all: pdf

pdf:
	@mkdir -p $(DIST_DIR)
	pandoc --defaults=$(CONFIG) $(FONT_OPTS) -o $(OUTPUT)
	@echo "PDF generado: $(OUTPUT)"

# Útil para depurar errores de LaTeX: genera el .tex intermedio
tex:
	@mkdir -p $(DIST_DIR)
	pandoc --defaults=$(CONFIG) $(FONT_OPTS) -s -o $(DIST_DIR)/report.tex

clean:
	@rm -rf $(DIST_DIR)
